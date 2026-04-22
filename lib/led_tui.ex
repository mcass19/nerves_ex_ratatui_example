defmodule LedTui do
  @moduledoc """
  TUI for controlling the built-in LED on a Raspberry Pi.

  Uses the onboard green ACT LED via Linux sysfs — no external wiring needed.
  When the LED sysfs path is not available (laptop, CI), it runs in simulation
  mode where the TUI works identically but no hardware is toggled.

  The body is a `ExRatatui.Widgets.Canvas` that draws a torch: when the LED
  is off the torch is rendered in muted grays; when it's on a yellow light
  beam is projected from the bulb, filled with scattered `Points` for a
  "sparkle" effect.

  ## Running (simulation mode)

      cd nerves_ex_ratatui_example
      mix deps.get
      mix run -e "LedTui.run()"

  ## Controls

  - `space` — toggle LED on/off
  - `q` — quit
  """

  use ExRatatui.App

  alias ExRatatui.Event
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.{Block, Canvas, Paragraph}
  alias ExRatatui.Widgets.Canvas.{Circle, Label, Points, Rectangle}
  alias ExRatatui.Widgets.Canvas.Line, as: CanvasLine

  @default_led_path "/sys/class/leds/ACT"
  @canvas_x_bounds {0.0, 100.0}
  @canvas_y_bounds {0.0, 50.0}

  @impl true
  def mount(opts) do
    led_path = Keyword.get(opts, :led_path, @default_led_path)
    hardware? = setup_led(led_path)

    state = %{
      led_on: false,
      hardware: hardware?,
      led_path: led_path,
      toggles: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: " ", kind: "press"}, state) do
    led_on = not state.led_on
    write_led(state, led_on)

    new_state = %{state | led_on: led_on, toggles: state.toggles + 1}

    {:noreply, new_state}
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
      Layout.split(area, :vertical, [
        {:length, 3},
        {:min, 0},
        {:length, 3}
      ])

    [
      {header_widget(state), header_area},
      {torch_canvas(state), body_area},
      {footer_widget(), footer_area}
    ]
  end

  # -- Widgets --

  defp header_widget(state) do
    mode_suffix =
      if state.hardware do
        [
          Span.new("  "),
          Span.new(" HARDWARE ",
            style: %Style{bg: :magenta, fg: :white, modifiers: [:bold]}
          )
        ]
      else
        [
          Span.new("  "),
          Span.new(" SIMULATION ",
            style: %Style{bg: :dark_gray, fg: :white, modifiers: [:bold]}
          )
        ]
      end

    status_badge =
      if state.led_on do
        Span.new(" ON  ", style: %Style{bg: :green, fg: :black, modifiers: [:bold]})
      else
        Span.new(" OFF ", style: %Style{bg: :red, fg: :white, modifiers: [:bold]})
      end

    title =
      Line.new(
        [
          Span.new(" "),
          Span.new("Nerves LED Control", style: %Style{fg: :cyan, modifiers: [:bold]}),
          Span.new("   "),
          status_badge,
          Span.new("  "),
          Span.new("toggles: ", style: %Style{fg: :dark_gray}),
          Span.new(Integer.to_string(state.toggles),
            style: %Style{fg: :yellow, modifiers: [:bold]}
          )
        ] ++ mode_suffix
      )

    %Paragraph{
      text: title,
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("ExRatatui", style: %Style{fg: :magenta, modifiers: [:bold]}),
            Span.new(" + ", style: %Style{fg: :dark_gray}),
            Span.new("Nerves", style: %Style{fg: :blue, modifiers: [:bold]}),
            Span.new(" ")
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }
  end

  defp torch_canvas(state) do
    title =
      if state.led_on do
        Line.new([
          Span.new(" "),
          Span.new("Torch", style: %Style{fg: :yellow, modifiers: [:bold]}),
          Span.new(" — emitting", style: %Style{fg: :yellow}),
          Span.new(" ")
        ])
      else
        Line.new([
          Span.new(" "),
          Span.new("Torch", style: %Style{fg: :white, modifiers: [:bold]}),
          Span.new(" — idle", style: %Style{fg: :dark_gray}),
          Span.new(" ")
        ])
      end

    border_color = if state.led_on, do: :yellow, else: :dark_gray

    %Canvas{
      x_bounds: @canvas_x_bounds,
      y_bounds: @canvas_y_bounds,
      marker: :braille,
      shapes: torch_shapes(state.led_on),
      block: %Block{
        title: title,
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: border_color}
      }
    }
  end

  # The torch is drawn as a rectangle body, a circular reflector/head,
  # a small switch bump on top and a circular bulb. When the LED is on
  # we overlay a beam (three Lines fanning from the bulb), scattered
  # sparkle Points filling the cone, and a label calling out the beam.
  defp torch_shapes(false) do
    body_color = :dark_gray

    [
      %Rectangle{x: 10.0, y: 18.0, width: 32.0, height: 10.0, color: body_color},
      %Rectangle{x: 42.0, y: 15.0, width: 8.0, height: 16.0, color: body_color},
      %Rectangle{x: 14.0, y: 28.0, width: 4.0, height: 2.0, color: body_color},
      %Circle{x: 48.0, y: 23.0, radius: 2.5, color: body_color},
      %Label{x: 22.0, y: 10.0, text: "press space to light", color: :dark_gray}
    ]
  end

  defp torch_shapes(true) do
    body_color = :yellow
    beam_color = :yellow

    [
      %Rectangle{x: 10.0, y: 18.0, width: 32.0, height: 10.0, color: body_color},
      %Rectangle{x: 42.0, y: 15.0, width: 8.0, height: 16.0, color: body_color},
      %Rectangle{x: 14.0, y: 28.0, width: 4.0, height: 2.0, color: :green},
      %Circle{x: 48.0, y: 23.0, radius: 2.5, color: :white},
      # Beam cone: top, middle, bottom lines fanning from the bulb
      %CanvasLine{x1: 50.5, y1: 23.0, x2: 95.0, y2: 42.0, color: beam_color},
      %CanvasLine{x1: 50.5, y1: 23.0, x2: 98.0, y2: 23.0, color: :white},
      %CanvasLine{x1: 50.5, y1: 23.0, x2: 95.0, y2: 4.0, color: beam_color},
      # Scattered sparkle points inside the cone for a "bright" feel
      %Points{coords: beam_sparkles(), color: :yellow},
      %Points{coords: beam_core_sparkles(), color: :white},
      %Label{x: 74.0, y: 36.0, text: "light", color: :yellow}
    ]
  end

  # Procedurally scatter points inside the beam cone. Static coordinates
  # are used (no rng) so the drawing stays deterministic frame-to-frame.
  defp beam_sparkles do
    for x <- 55..95//3, y_off <- -18..18//3 do
      ratio = (x - 55) / 40.0
      max_y = ratio * 18.0
      y = y_off * 1.0

      if abs(y) <= max_y do
        {x * 1.0, 23.0 + y}
      end
    end
    |> Enum.reject(&is_nil/1)
  end

  defp beam_core_sparkles do
    for x <- 55..95//2 do
      {x * 1.0, 23.0}
    end
  end

  defp footer_widget do
    %Paragraph{
      text:
        Line.new([
          Span.new(" space ", style: %Style{bg: :cyan, fg: :black, modifiers: [:bold]}),
          Span.new(" toggle LED  "),
          Span.new(" q ", style: %Style{bg: :red, fg: :white, modifiers: [:bold]}),
          Span.new(" quit")
        ]),
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
