defmodule LedTui do
  @moduledoc """
  TUI for controlling the built-in LED on a Raspberry Pi.

  Uses the onboard green ACT LED via Linux sysfs — no external wiring needed.
  When the LED sysfs path is not available (laptop, CI), it runs in simulation
  mode where the TUI works identically but no hardware is toggled.

  ## Running (simulation mode)

      cd nerves_ex_ratatui_example
      mix deps.get
      mix run -e "LedTui.run()"

  ## Controls

  - `space` — toggle LED on/off
  - `q` — quit
  """

  use ExRatatui.App

  require Logger

  alias ExRatatui.Event
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph}

  @default_led_path "/sys/class/leds/ACT"

  @impl true
  def mount(opts) do
    led_path = Keyword.get(opts, :led_path, @default_led_path)
    hardware? = setup_led(led_path)

    if hardware? do
      Logger.info("LED at #{led_path} — controlling onboard ACT LED")
    else
      Logger.info("LED sysfs not found — running in simulation mode")
    end

    {:ok, %{led_on: false, hardware: hardware?, led_path: led_path}}
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: " ", kind: "press"}, state) do
    led_on = not state.led_on
    write_led(state, led_on)
    {:noreply, %{state | led_on: led_on}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    write_led(state, false)
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header_area, body_area, footer_area] =
      Layout.split(area, :vertical, [{:length, 3}, {:min, 0}, {:length, 3}])

    [
      {header_widget(state), header_area},
      {body_widget(state), body_area},
      {footer_widget(), footer_area}
    ]
  end

  # -- Widgets --

  defp header_widget(state) do
    mode = if state.hardware, do: "", else: " (simulation)"

    %Paragraph{
      text: "  Nerves LED Control#{mode}",
      style: %Style{fg: :cyan, modifiers: [:bold]},
      block: %Block{
        title: " ExRatatui + Nerves ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }
  end

  defp body_widget(state) do
    {status, status_color} =
      if state.led_on, do: {"ON", :green}, else: {"OFF", :red}

    indicator =
      if state.led_on, do: "( * )", else: "(   )"

    text = """
      ACT LED:  [ #{status} ]

          #{indicator}
    """

    %Paragraph{
      text: text,
      style: %Style{fg: status_color, modifiers: [:bold]},
      alignment: :center,
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp footer_widget do
    %Paragraph{
      text: " space: toggle LED  |  q: quit",
      style: %Style{fg: :dark_gray},
      block: %Block{
        borders: [:top],
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  # -- LED helpers (sysfs) --

  defp setup_led(led_path) do
    if File.dir?(led_path) do
      File.write(Path.join(led_path, "trigger"), "none")
      true
    else
      false
    end
  end

  defp write_led(%{hardware: false}, _on?), do: :ok

  defp write_led(%{hardware: true, led_path: led_path}, on?) do
    value = if on?, do: "1", else: "0"
    File.write(Path.join(led_path, "brightness"), value)
  end

  # -- Entry point --

  @doc """
  Starts the TUI and blocks until it exits.

  Accepts the same options as `start_link/1`.
  """
  def run(opts \\ []) do
    {:ok, pid} = start_link(opts)
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end
  end
end
