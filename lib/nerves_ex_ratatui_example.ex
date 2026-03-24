defmodule NervesExRatatuiExample do
  @moduledoc """
  Example Nerves project demonstrating ExRatatui on embedded hardware.

  Includes two TUI applications:

  - `LedTui` — toggle the built-in green ACT LED on a Raspberry Pi
  - `SystemMonitorTui` — live dashboard for BEAM and system metrics

  Both work on any machine. On non-Nerves hosts the LED TUI runs in simulation
  mode and the system monitor reads `/proc/meminfo` when available.
  """
end
