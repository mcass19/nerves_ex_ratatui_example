# Nerves ExRatatui Example

Example Nerves project demonstrating [ExRatatui](https://github.com/mcass19/ex_ratatui) on embedded hardware. Includes three TUI applications that work on any machine. On a Raspberry Pi they render directly to the HDMI console, are reachable over SSH, **and** can be attached to over Erlang distribution from any BEAM node on the network — no NIF or terminal needed on the Pi.

Two of the apps (`SystemMonitorTui` and `LedTui`) use the **callback runtime** (`mount/1`, `handle_event/2`, `handle_info/2`). The third (`SystemMonitorReducerTui`) uses the **reducer runtime** (`init/1`, `update/2`, `subscriptions/1`) — same dashboard, different architecture.

![Nerves ExRatatui Demo](https://raw.githubusercontent.com/mcass19/nerves_ex_ratatui_example/main/assets/nerves_demo.gif)

## Quick start

```sh
git clone https://github.com/mcass19/nerves_ex_ratatui_example.git
cd nerves_ex_ratatui_example
mix deps.get
```

```sh
mix run -e "SystemMonitorTui.run()"           # system dashboard (callback runtime)
mix run -e "SystemMonitorReducerTui.run()"    # system dashboard (reducer runtime)
mix run -e "LedTui.run()"                     # LED control (simulation on non-Nerves)
```

Press `q` to quit either TUI.

## Deploy to a Raspberry Pi

### Prerequisites

- Raspberry Pi (any model — RPi Zero, 3, 4, 5 all have an ACT LED)
- Micro SD card
- HDMI display + USB keyboard *or* a network connection for SSH

### Build and flash

```sh
export MIX_TARGET=rpi4    # or rpi0, rpi3, rpi5, etc.
mix deps.get
mix firmware
mix burn                  # insert SD card first
```

Over-the-air updates after the first deploy:

```sh
mix firmware
mix upload nerves.local
```

### Run on the Pi (HDMI/console)

Connect HDMI + USB keyboard, power on, and at the IEx prompt:

```elixir
iex> SystemMonitorTui.run()
iex> SystemMonitorReducerTui.run()
iex> LedTui.run()
```

### Run over SSH (no display required)

All three TUIs are registered as SSH subsystems via the `nerves_ssh` daemon that ships with `nerves_pack`. From any machine whose public key is in your `~/.ssh/`:

```sh
ssh -t nerves@nerves.local -s Elixir.SystemMonitorTui
ssh -t nerves@nerves.local -s Elixir.SystemMonitorReducerTui
ssh -t nerves@nerves.local -s Elixir.LedTui
```

The `-t` is **required**: OpenSSH doesn't allocate a PTY by default for `-s` (subsystem) mode, and without one your local terminal stays in cooked mode — keystrokes get line-buffered and echoed locally on top of the TUI, and the alt-screen teardown on disconnect bleeds into your shell prompt.

The TUI runs entirely on the device — the SSH channel just shuttles render bytes to your terminal and key events back to the Pi. Quit with `q` and the channel cleans up its alt-screen on the way out, leaving your scrollback intact.

Plain `ssh nerves@nerves.local` (no `-s`) still drops you into the regular Nerves IEx shell, so the manual `iex> SystemMonitorTui.run()` path keeps working unchanged.

> **How it works:** `ExRatatui.SSH.subsystem/1` plugs an `ExRatatui.App` module into the OTP `:ssh.subsystem_spec()` shape that `nerves_ssh` already speaks. Each connected client gets its own isolated TUI session — multiple `ssh` clients to the same Pi are independent. See the [SSH transport guide](https://hexdocs.pm/ex_ratatui/ssh_transport.html) in the ex_ratatui docs for the full architecture.

The subsystem name is the full Elixir module name as a charlist, so multiple TUIs in the same firmware get distinct names and don't collide. See `test/ssh_subsystems_test.exs` for the spec-shape checks.

### Run over Erlang distribution (no NIF on the Pi)

All three TUIs have `ExRatatui.Distributed.Listener`s in the supervision tree. Any BEAM node that shares the same cookie can attach from the network — the Pi runs the TUI callbacks and sends widget structs as plain BEAM terms; the connected node renders them with its own NIF. No Rust toolchain or cross-compilation needed on the device for distribution sessions.

#### 1. Find the device's IP address

From the IEx prompt on the Pi (via SSH or HDMI), check which interface has an address — USB gadget, Ethernet, or WiFi:

```elixir
iex> VintageNet.get(["interface", "usb0", "addresses"])
iex> VintageNet.get(["interface", "eth0", "addresses"])
iex> VintageNet.get(["interface", "wlan0", "addresses"])
```

Look for the `%{family: :inet, address: {a, b, c, d}}` entry. For USB gadget mode it's typically something like `172.31.216.141`.

#### 2. Start EPMD and enable distribution

EPMD (Erlang Port Mapper Daemon) doesn't run by default on Nerves — start it first, then make the device a distributed node:

```elixir
iex> System.cmd("epmd", ["-daemon"])
{"", 0}
iex> Node.start(:"nerves@172.31.216.141", :longnames)
{:ok, _}
```

Replace the IP with the address you found in step 1.

#### 3. Get the release cookie

```elixir
iex> Node.get_cookie()
:"NKJH..."
```

Copy this value. Your node needs the same cookie to connect.

#### 4. Attach from another node

With `ex_ratatui` on the code path, start a node on the same subnet. For USB gadget mode the dev machine is typically one IP away (e.g. `172.31.216.142`):

```sh
iex --name dev@172.31.216.142 --cookie <cookie-from-step-3> -S mix
iex> ExRatatui.Distributed.attach(:"nerves@172.31.216.141", SystemMonitorTui, listener: :system_monitor_dist)
iex> ExRatatui.Distributed.attach(:"nerves@172.31.216.141", SystemMonitorReducerTui, listener: :system_monitor_reducer_dist)
iex> ExRatatui.Distributed.attach(:"nerves@172.31.216.141", LedTui, listener: :led_tui_dist)
```

The `listener:` option tells `attach/3` which named Listener to connect to — each TUI has its own (`:system_monitor_dist`, `:system_monitor_reducer_dist`, and `:led_tui_dist`). Quit with `q`.

> **Why distribution?** SSH shuttles rendered ANSI bytes over the wire, so the device loads the NIF and does all the rendering. Distribution sends the raw widget structs instead — the connected node renders them locally. This means the Pi never touches the Rust NIF for distribution sessions, which is ideal for constrained devices or targets where cross-compiling the NIF is inconvenient. Both transports coexist in the same firmware.

## System Monitor

A btop/fastfetch-inspired BEAM system monitor with two tabs.

### Overview

Six-panel dashboard updating in real time:

| Panel | What it shows |
|---|---|
| **Host Info** | OS, kernel, CPU model + cores, architecture, system uptime, primary IP |
| **System Info** | OTP/ERTS/Elixir versions, schedulers, process/port/atom counts, BEAM uptime |
| **Memory** | RAM + Swap bars, cached/free breakdown — colors shift green/yellow/red |
| **CPU & Disk** | Load averages (1/5/15 min), CPU temperature, disk usage |
| **Memory Pools** | BEAM memory: processes, binary, ETS, atom, code |
| **Scheduler Utilization** | Per-scheduler wall-time usage with live progress bars |

### Processes

Top 20 BEAM processes by memory, with reductions and message queue length.

### Controls

| Key | Action |
|---|---|
| `1` / `2` | Switch tabs (Overview / Processes) |
| `j` / `Down` | Scroll down in process table |
| `k` / `Up` | Scroll up in process table |
| `q` | Quit |

## System Monitor — Reducer Runtime

`SystemMonitorReducerTui` is the same system dashboard rebuilt with ExRatatui's **reducer runtime**. Instead of separate `handle_event/2` and `handle_info/2` callbacks, all messages flow through a single `update/2`:

```elixir
use ExRatatui.App, runtime: :reducer

def update({:event, %Event.Key{code: "q", kind: "press"}}, state), do: {:stop, state}
def update({:info, :refresh}, state) do
  cmd = Command.async(fn -> collect_metrics(state) end, &{:metrics_collected, &1})
  {:noreply, state, commands: [cmd], render?: false}
end
def update({:info, {:metrics_collected, metrics}}, state) do
  {:noreply, %{state | metrics: metrics}}
end
```

Key differences from the callback version:

| Feature | Callback (`SystemMonitorTui`) | Reducer (`SystemMonitorReducerTui`) |
|---|---|---|
| **Timer** | `Process.send_after/3` in `handle_info/2` | `Subscription.interval/3` in `subscriptions/1` — auto-reconciled |
| **Message handling** | Split across `handle_event/2` + `handle_info/2` | Single `update/2` with `{:event, _}` and `{:info, _}` |
| **Async work** | N/A (blocks in `handle_info`) | `Command.async/2` — `/proc` reads run off the server process |
| **Render control** | Always re-renders | `render?: false` skips render on async kick-off |

Both versions produce identical output, work on all three transports, and use the same controls.

## LED Control

Toggle the Raspberry Pi's ACT LED from a TUI. Runs in simulation mode on non-Nerves hosts.

```
╭ ExRatatui + Nerves ───────╮
│  Nerves LED Control       │
╰───────────────────────────╯
╭───────────────────────────╮
│                           │
│   ACT LED:  [ ON ]        │
│                           │
│       ( * )               │
│                           │
╰───────────────────────────╯
─────────────────────────────
 space: toggle LED | q: quit
```

### Controls

| Key | Action |
|---|---|
| `space` | toggle LED |
| `q` | Quit |

## See also

- **[ex_ratatui](https://github.com/mcass19/ex_ratatui)** — the underlying Elixir bindings to Rust [ratatui](https://ratatui.rs), including the [SSH transport guide](https://hexdocs.pm/ex_ratatui/ssh_transport.html) and [distribution transport guide](https://hexdocs.pm/ex_ratatui/distributed_transport.html).
- **[phoenix_ex_ratatui_example](https://github.com/mcass19/phoenix_ex_ratatui_example)** — the Phoenix counterpart to this project: an admin TUI served over SSH and distribution alongside a public LiveView, sharing PubSub between the browser and the terminal. Same library, different deployment shape.

## License

MIT — see [LICENSE](https://github.com/mcass19/nerves_ex_ratatui_example/blob/main/LICENSE) for details.
