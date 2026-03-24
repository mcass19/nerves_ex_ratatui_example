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
        # Children for all targets except host
      ]
    end
  end
end
