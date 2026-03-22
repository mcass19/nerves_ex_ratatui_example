defmodule LedTuiTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event

  describe "mount/1" do
    test "starts with LED off in simulation mode" do
      {:ok, state} = LedTui.mount([])

      assert state.led_on == false
      assert state.hardware == false
    end
  end

  describe "handle_event/2" do
    test "space toggles LED on" do
      {:ok, state} = LedTui.mount([])

      {:noreply, state} = LedTui.handle_event(%Event.Key{code: " ", kind: "press"}, state)
      assert state.led_on == true
    end

    test "space toggles LED off again" do
      {:ok, state} = LedTui.mount([])

      {:noreply, state} = LedTui.handle_event(%Event.Key{code: " ", kind: "press"}, state)
      {:noreply, state} = LedTui.handle_event(%Event.Key{code: " ", kind: "press"}, state)
      assert state.led_on == false
    end

    test "q stops the TUI" do
      {:ok, state} = LedTui.mount([])

      assert {:stop, ^state} = LedTui.handle_event(%Event.Key{code: "q", kind: "press"}, state)
    end

    test "other keys are ignored" do
      {:ok, state} = LedTui.mount([])

      {:noreply, new_state} = LedTui.handle_event(%Event.Key{code: "x", kind: "press"}, state)
      assert new_state == state
    end
  end

  describe "render/2" do
    test "shows simulation mode when no hardware" do
      {:ok, state} = LedTui.mount([])
      frame = %ExRatatui.Frame{width: 60, height: 20}

      widgets = LedTui.render(state, frame)

      assert length(widgets) == 3
    end

    test "renders to test terminal with LED OFF" do
      {:ok, pid} = LedTui.start_link(name: nil, test_mode: {60, 20})

      # Let initial render complete
      Process.sleep(50)

      terminal_ref = :sys.get_state(pid).terminal_ref
      content = ExRatatui.get_buffer_content(terminal_ref)

      assert content =~ "Nerves LED Control"
      assert content =~ "simulation"
      assert content =~ "OFF"
      assert content =~ "space: toggle LED"

      GenServer.stop(pid)
    end
  end
end
