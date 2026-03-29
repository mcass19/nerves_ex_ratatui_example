defmodule LedTuiTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event

  describe "mount/1" do
    test "starts with LED off in simulation mode" do
      {:ok, state} = LedTui.mount([])

      assert state.led_on == false
      assert state.hardware == false
    end

    test "uses default LED path when none provided" do
      {:ok, state} = LedTui.mount([])

      assert state.led_path == "/sys/class/leds/ACT"
    end

    @tag :tmp_dir
    test "detects hardware when sysfs path exists", %{tmp_dir: tmp_dir} do
      led_path = Path.join(tmp_dir, "ACT")
      File.mkdir_p!(led_path)
      File.write!(Path.join(led_path, "trigger"), "mmc0")
      File.write!(Path.join(led_path, "brightness"), "0")

      {:ok, state} = LedTui.mount(led_path: led_path)

      assert state.hardware == true
      assert state.led_path == led_path
      assert File.read!(Path.join(led_path, "trigger")) == "none"
    end
  end

  describe "handle_event/2" do
    setup do
      {:ok, state} = LedTui.mount([])
      %{state: state}
    end

    test "space toggles LED on", %{state: state} do
      {:noreply, state} = LedTui.handle_event(key(" "), state)
      assert state.led_on == true
    end

    test "space toggles LED off again", %{state: state} do
      {:noreply, state} = LedTui.handle_event(key(" "), state)
      {:noreply, state} = LedTui.handle_event(key(" "), state)
      assert state.led_on == false
    end

    test "q stops the TUI", %{state: state} do
      assert {:stop, ^state} = LedTui.handle_event(key("q"), state)
    end

    test "other keys are ignored", %{state: state} do
      {:noreply, new_state} = LedTui.handle_event(key("x"), state)
      assert new_state == state
    end

    test "release events are ignored", %{state: state} do
      event = %Event.Key{code: " ", kind: "release"}
      {:noreply, new_state} = LedTui.handle_event(event, state)
      assert new_state == state
    end
  end

  describe "handle_event/2 with hardware" do
    @tag :tmp_dir
    test "space writes brightness to sysfs", %{tmp_dir: tmp_dir} do
      led_path = Path.join(tmp_dir, "ACT")
      File.mkdir_p!(led_path)
      File.write!(Path.join(led_path, "trigger"), "mmc0")
      File.write!(Path.join(led_path, "brightness"), "0")

      {:ok, state} = LedTui.mount(led_path: led_path)

      {:noreply, state} = LedTui.handle_event(key(" "), state)
      assert File.read!(Path.join(led_path, "brightness")) == "1"

      {:noreply, _state} = LedTui.handle_event(key(" "), state)
      assert File.read!(Path.join(led_path, "brightness")) == "0"
    end
  end

  describe "terminate/2" do
    test "is a no-op in simulation mode" do
      {:ok, state} = LedTui.mount([])
      assert LedTui.terminate(:normal, state) == :ok
    end

    @tag :tmp_dir
    test "turns LED off on shutdown", %{tmp_dir: tmp_dir} do
      led_path = Path.join(tmp_dir, "ACT")
      File.mkdir_p!(led_path)
      File.write!(Path.join(led_path, "trigger"), "mmc0")
      File.write!(Path.join(led_path, "brightness"), "0")

      {:ok, state} = LedTui.mount(led_path: led_path)
      {:noreply, state} = LedTui.handle_event(key(" "), state)
      assert File.read!(Path.join(led_path, "brightness")) == "1"

      LedTui.terminate(:normal, state)
      assert File.read!(Path.join(led_path, "brightness")) == "0"
    end
  end

  describe "render/2" do
    test "returns 3 widget-area pairs" do
      {:ok, state} = LedTui.mount([])
      frame = %ExRatatui.Frame{width: 60, height: 20}

      widgets = LedTui.render(state, frame)

      assert length(widgets) == 3
    end

    test "all pairs contain {widget, rect}" do
      {:ok, state} = LedTui.mount([])
      frame = %ExRatatui.Frame{width: 60, height: 20}

      widgets = LedTui.render(state, frame)

      for {widget, rect} <- widgets do
        assert is_struct(widget)
        assert %ExRatatui.Layout.Rect{} = rect
      end
    end
  end

  describe "integration: test terminal" do
    test "renders LED OFF state" do
      pid = start_tui()
      content = get_buffer(pid)

      assert content =~ "Nerves LED Control"
      assert content =~ "simulation"
      assert content =~ "OFF"
      assert content =~ "space: toggle LED"

      stop_tui(pid)
    end

    @tag :tmp_dir
    test "renders without simulation label when hardware present", %{tmp_dir: tmp_dir} do
      led_path = Path.join(tmp_dir, "ACT")
      File.mkdir_p!(led_path)
      File.write!(Path.join(led_path, "trigger"), "mmc0")
      File.write!(Path.join(led_path, "brightness"), "0")

      pid = start_tui(led_path: led_path)
      content = get_buffer(pid)

      assert content =~ "Nerves LED Control"
      refute content =~ "simulation"

      stop_tui(pid)
    end
  end

  describe "run/1" do
    test "starts and stops cleanly in test mode" do
      task =
        Task.async(fn ->
          LedTui.run(name: :test_led_run, test_mode: {60, 20})
        end)

      Process.sleep(100)
      pid = Process.whereis(:test_led_run)
      GenServer.stop(pid)
      assert Task.await(task, 1000) == :ok
    end
  end

  # -- Helpers --

  defp key(code), do: %Event.Key{code: code, kind: "press"}

  defp start_tui(extra_opts \\ []) do
    opts = [name: nil, test_mode: {60, 20}] ++ extra_opts
    {:ok, pid} = LedTui.start_link(opts)
    _ = :sys.get_state(pid)
    pid
  end

  defp get_buffer(pid) do
    terminal_ref = :sys.get_state(pid).terminal_ref
    ExRatatui.get_buffer_content(terminal_ref)
  end

  defp stop_tui(pid) do
    ref = Process.monitor(pid)
    GenServer.stop(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
  end
end
