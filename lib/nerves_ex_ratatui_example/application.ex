defmodule NervesExRatatuiExample.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Children for all targets
      ] ++ target_children()

    opts = [strategy: :one_for_one, name: NervesExRatatuiExample.Supervisor]
    Supervisor.start_link(children, opts)
  end

  if Mix.target() == :host do
    defp target_children do
      [
        # Children that only run on the host during development or test.
      ]
    end
  else
    defp target_children do
      [
        # Distribution listeners — any named BEAM node that shares the
        # release cookie can attach from the network with
        # `ExRatatui.Distributed.attach/3`. The device runs each TUI's
        # callbacks; the attaching node renders locally via its own NIF.
        Supervisor.child_spec(
          {ExRatatui.Distributed.Listener, mod: SystemMonitorTui, name: :system_monitor_dist},
          id: :system_monitor_dist
        ),
        Supervisor.child_spec(
          {ExRatatui.Distributed.Listener, mod: LedTui, name: :led_tui_dist},
          id: :led_tui_dist
        )
      ]
    end
  end
end
