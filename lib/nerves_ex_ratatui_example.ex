defmodule NervesExRatatuiExample do
  @moduledoc """
  Example Nerves project demonstrating ExRatatui on embedded hardware.

  Provides a terminal UI for toggling the built-in ACT LED on a Raspberry Pi.
  When the LED sysfs path is not available (laptop, CI), it runs in simulation
  mode where the TUI works identically but no hardware is toggled.
  """
end
