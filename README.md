# Nerves ExRatatui Example

Example Nerves project demonstrating [ExRatatui](https://github.com/mcass19/ex_ratatui)
on embedded hardware. Includes two TUI applications:

- **LedTui** — toggle the built-in green ACT LED on a Raspberry Pi
- **SystemMonitorTui** — live dashboard for BEAM and system metrics

Both work on any machine (laptop, CI). On non-Nerves hosts the LED TUI runs in
simulation mode and the system monitor reads `/proc/meminfo` when available.

## Examples

### LED Control

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

### System Monitor

```
╭ ExRatatui + Nerves ──────────────────────────────────────╮
│  BEAM System Monitor                                     │
╰──────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────╮
│  [1] Overview │ [2] Processes                            │
╰──────────────────────────────────────────────────────────╯
╭ Memory Usage ────────────────╮╭ System Info ──────────────╮
│  ████████░░░░ 1.2 GB / 4 GB ││  OTP:        27           │
╰──────────────────────────────╯│  Schedulers: 4/4          │
╭ Memory Pools ────────────────╮│  Processes:  312/262144   │
│  Processes [████░░] 45.2%    ││  Uptime:     2h 15m 30s   │
│  Binary    [██░░░░] 22.1%    │╰───────────────────────────╯
│  ETS       [█░░░░░]  8.3%   │╭ Scheduler Utilization ────╮
╰──────────────────────────────╯│  Sched 1  [███░░░░]  42%  │
                                │  Sched 2  [██░░░░░]  28%  │
                                ╰───────────────────────────╯
 1/2: tabs | j/k: scroll | q: quit
```

## Quick start (simulation)

No hardware needed. Run on any machine:

```sh
git clone https://github.com/mcass19/nerves_ex_ratatui_example.git
cd nerves_ex_ratatui_example
mix deps.get
```

LED control:
```sh
mix run -e "LedTui.run()"
```

System monitor:
```sh
mix run -e "SystemMonitorTui.run()"
```

Press `q` to quit either TUI.

## Deploy to a Raspberry Pi

### Prerequisites

- Raspberry Pi (any model — RPi Zero, 3, 4, 5 all have an ACT LED)
- Micro SD card
- HDMI display + USB keyboard (the TUI renders to the Pi's console)

### Build and flash

```sh
export MIX_TARGET=rpi4    # or rpi0, rpi3, rpi5, etc.
mix deps.get
mix firmware
mix burn                  # insert SD card first
```

After the first deploy, push firmware updates over the network:

```sh
mix firmware
mix upload nerves.local
```

### Run

Insert the SD card into the Pi, connect an HDMI display and USB keyboard,
then power on. Once you see the IEx prompt, start either TUI:

```elixir
iex> LedTui.run()            # LED control
iex> SystemMonitorTui.run()   # system dashboard
```

Press `q` to quit back to IEx. Run the command again to restart.

> **Note:** The TUI uses the BEAM's stdout, which is the Pi's physical
> console (HDMI/UART). It does not work over SSH — SSH sessions use
> Erlang's shell, not a real terminal.

