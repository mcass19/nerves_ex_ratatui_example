# Nerves ExRatatui Example

Example Nerves project demonstrating [ExRatatui](https://github.com/mcass19/ex_ratatui)
on embedded hardware. Includes two TUI applications that work on any machine
(laptop, CI) — on a Raspberry Pi they render directly to the HDMI console.

![System Monitor](assets/system_monitor.png)
![LED](assets/led.png)

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
- HDMI display + USB keyboard

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

### Run on the Pi

Connect HDMI + USB keyboard, power on, and at the IEx prompt:

```elixir
iex> SystemMonitorTui.run()
iex> LedTui.run()
```

> **Note:** The TUI renders to the Pi's physical console (HDMI/UART).
> It does not work over SSH.

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

Toggle the Raspberry Pi's ACT LED from a TUI. Runs in simulation mode on
non-Nerves hosts.

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

