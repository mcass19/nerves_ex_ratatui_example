# Nerves ExRatatui Example

Example Nerves project demonstrating [ExRatatui](https://github.com/mcass19/ex_ratatui) on embedded hardware. Includes two TUI applications that work on any machine. On a Raspberry Pi they render directly to the HDMI console **and** are reachable over SSH from any laptop on the network.

![Nerves ExRatatui Demo](https://raw.githubusercontent.com/mcass19/nerves_ex_ratatui_example/main/assets/nerves_demo.gif)

## Quick start

```sh
git clone https://github.com/mcass19/nerves_ex_ratatui_example.git
cd nerves_ex_ratatui_example
mix deps.get
```

```sh
mix run -e "SystemMonitorTui.run()"   # system dashboard
mix run -e "LedTui.run()"             # LED control (simulation on non-Nerves)
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
iex> LedTui.run()
```

### Run over SSH (no display required)

Both TUIs are also registered as SSH subsystems via the `nerves_ssh` daemon that ships with `nerves_pack`. From any machine whose public key is in your `~/.ssh/`:

```sh
ssh -t nerves@nerves.local -s Elixir.SystemMonitorTui
ssh -t nerves@nerves.local -s Elixir.LedTui
```

The `-t` is **required**: OpenSSH doesn't allocate a PTY by default for `-s` (subsystem) mode, and without one your local terminal stays in cooked mode — keystrokes get line-buffered and echoed locally on top of the TUI, and the alt-screen teardown on disconnect bleeds into your shell prompt.

The TUI runs entirely on the device — the SSH channel just shuttles render bytes to your terminal and key events back to the Pi. Quit with `q` and the channel cleans up its alt-screen on the way out, leaving your scrollback intact.

Plain `ssh nerves@nerves.local` (no `-s`) still drops you into the regular Nerves IEx shell, so the manual `iex> SystemMonitorTui.run()` path keeps working unchanged.

> **How it works:** `ExRatatui.SSH.subsystem/1` plugs an `ExRatatui.App` module into the OTP `:ssh.subsystem_spec()` shape that `nerves_ssh` already speaks. Each connected client gets its own isolated TUI session — multiple `ssh` clients to the same Pi are independent. See the [SSH transport guide](https://hexdocs.pm/ex_ratatui/ssh_transport.html) in the ex_ratatui docs for the full architecture.

The subsystem name is the full Elixir module name as a charlist, so multiple TUIs in the same firmware get distinct names and don't collide. See `test/ssh_subsystems_test.exs` for the spec-shape checks.

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

- **[ex_ratatui](https://github.com/mcass19/ex_ratatui)** — the underlying Elixir bindings to Rust [ratatui](https://ratatui.rs), including the [SSH transport guide](https://hexdocs.pm/ex_ratatui/ssh_transport.html).
- **[phoenix_ex_ratatui_example](https://github.com/mcass19/phoenix_ex_ratatui_example)** — the Phoenix counterpart to this project: an admin TUI served over SSH alongside a public LiveView, sharing PubSub between the browser and the terminal. Same library, different deployment shape.

## License

MIT — see [LICENSE](https://github.com/mcass19/nerves_ex_ratatui_example/blob/main/LICENSE) for details.
