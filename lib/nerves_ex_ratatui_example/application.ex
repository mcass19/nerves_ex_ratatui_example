defmodule NervesExRatutuiExample.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Children for all targets
      ] ++ target_children()

    opts = [strategy: :one_for_one, name: NervesExRatutuiExample.Supervisor]
    Supervisor.start_link(children, opts)
  end

  if Mix.target() == :host do
    defp target_children do
      [
        # On host, start the TUI manually with: LedTui.run()
      ]
    end
  else
    defp target_children do
      [
        LedTui
      ]
    end
  end
end
