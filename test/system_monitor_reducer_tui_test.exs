defmodule SystemMonitorReducerTuiTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event

  describe "init/1" do
    test "returns initial state with expected keys" do
      {:ok, state} = SystemMonitorReducerTui.init([])

      assert state.tab == 0
      assert state.selected == 0
      assert is_map(state.host)
      assert is_map(state.metrics)
      assert state.prev_sched_sample == nil or is_list(state.prev_sched_sample)
    end

    test "metrics contains expected data" do
      {:ok, state} = SystemMonitorReducerTui.init([])
      m = state.metrics

      assert is_map(m.mem)
      assert is_map(m.sys)
      assert is_map(m.cpu_load)
      assert is_list(m.top_procs)
      assert is_integer(m.host_uptime)
    end

    test "host info has expected keys" do
      {:ok, state} = SystemMonitorReducerTui.init([])

      assert is_binary(state.host.hostname)
      assert is_binary(state.host.os)
      assert is_binary(state.host.kernel)
      assert is_binary(state.host.cpu_model)
      assert is_integer(state.host.cpu_cores)
      assert state.host.cpu_cores > 0
    end
  end

  describe "update/2 — events" do
    setup do
      {:ok, state} = SystemMonitorReducerTui.init([])
      %{state: state}
    end

    test "q stops the TUI", %{state: state} do
      assert {:stop, ^state} =
               SystemMonitorReducerTui.update({:event, key("q")}, state)
    end

    test "1 switches to overview tab", %{state: state} do
      state = %{state | tab: 1}
      {:noreply, next} = SystemMonitorReducerTui.update({:event, key("1")}, state)
      assert next.tab == 0
    end

    test "2 switches to processes tab", %{state: state} do
      {:noreply, next} = SystemMonitorReducerTui.update({:event, key("2")}, state)
      assert next.tab == 1
    end

    test "j/Down scrolls down in process table", %{state: state} do
      state = %{state | tab: 1}
      {:noreply, next} = SystemMonitorReducerTui.update({:event, key("j")}, state)
      assert next.selected == 1

      {:noreply, next} = SystemMonitorReducerTui.update({:event, key("Down")}, state)
      assert next.selected == 1
    end

    test "k/Up scrolls up in process table", %{state: state} do
      state = %{state | selected: 2}
      {:noreply, next} = SystemMonitorReducerTui.update({:event, key("k")}, state)
      assert next.selected == 1

      {:noreply, next} = SystemMonitorReducerTui.update({:event, key("Up")}, state)
      assert next.selected == 1
    end

    test "k/Up doesn't scroll below zero", %{state: state} do
      {:noreply, next} = SystemMonitorReducerTui.update({:event, key("k")}, state)
      assert next.selected == 0
    end

    test "unknown events are ignored", %{state: state} do
      assert {:noreply, ^state} =
               SystemMonitorReducerTui.update({:event, key("x")}, state)
    end
  end

  describe "update/2 — info messages" do
    setup do
      {:ok, state} = SystemMonitorReducerTui.init([])
      %{state: state}
    end

    test ":refresh returns async command and skips render", %{state: state} do
      {:noreply, ^state, opts} =
        SystemMonitorReducerTui.update({:info, :refresh}, state)

      assert opts[:render?] == false
      assert [%ExRatatui.Command{kind: :async}] = opts[:commands]
    end

    test "{:metrics_collected, metrics} updates state", %{state: state} do
      metrics = SystemMonitorReducerTui.collect_metrics(nil)

      {:noreply, next} =
        SystemMonitorReducerTui.update({:info, {:metrics_collected, metrics}}, state)

      assert next.metrics == metrics
      assert next.prev_sched_sample == metrics.sched_sample
    end
  end

  describe "subscriptions/1" do
    test "declares a 1-second refresh interval" do
      {:ok, state} = SystemMonitorReducerTui.init([])
      subs = SystemMonitorReducerTui.subscriptions(state)

      assert [%ExRatatui.Subscription{id: :refresh, kind: :interval, interval_ms: 1_000}] = subs
    end
  end

  describe "render/2" do
    test "overview tab returns header + tabs + footer + 4 body widgets" do
      {:ok, state} = SystemMonitorReducerTui.init([])
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = SystemMonitorReducerTui.render(state, frame)

      # header + tabs + footer + 4 overview panels
      assert length(widgets) == 7

      for {widget, rect} <- widgets do
        assert is_struct(widget)
        assert %ExRatatui.Layout.Rect{} = rect
      end
    end

    test "processes tab returns header + tabs + footer + 1 table" do
      {:ok, state} = SystemMonitorReducerTui.init([])
      state = %{state | tab: 1}
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = SystemMonitorReducerTui.render(state, frame)

      # header + tabs + footer + 1 table
      assert length(widgets) == 4
    end
  end

  describe "integration: test terminal" do
    test "boots, renders the overview, and quits cleanly" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: SystemMonitorReducerTui,
          name: nil,
          test_mode: {120, 40}
        )

      try do
        _ = :sys.get_state(pid)
        %{terminal_ref: terminal_ref} = :sys.get_state(pid)

        content = ExRatatui.get_buffer_content(terminal_ref)

        assert content =~ "BEAM System Monitor (Reducer)"
        assert content =~ "Overview"
        assert content =~ "Processes"

        # Verify runtime snapshot shows reducer mode
        snapshot = ExRatatui.Runtime.snapshot(pid)
        assert snapshot.mode == :reducer
        assert snapshot.render_count >= 1
      after
        ref = Process.monitor(pid)
        GenServer.stop(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
      end
    end

    test "inject_event switches tabs" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: SystemMonitorReducerTui,
          name: nil,
          test_mode: {120, 40}
        )

      try do
        _ = :sys.get_state(pid)

        # Switch to processes tab
        :ok = ExRatatui.Runtime.inject_event(pid, key("2"))
        %{user_state: state} = :sys.get_state(pid)
        assert state.tab == 1

        # Switch back
        :ok = ExRatatui.Runtime.inject_event(pid, key("1"))
        %{user_state: state} = :sys.get_state(pid)
        assert state.tab == 0
      after
        ref = Process.monitor(pid)
        GenServer.stop(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
      end
    end
  end

  describe "formatting helpers" do
    test "format_uptime_seconds/1" do
      assert SystemMonitorReducerTui.format_uptime_seconds(30) == "0m 30s"
      assert SystemMonitorReducerTui.format_uptime_seconds(3661) == "1h 1m 1s"
      assert SystemMonitorReducerTui.format_uptime_seconds(86_461) == "1d 0h 1m"
    end

    test "format_bytes/1" do
      assert SystemMonitorReducerTui.format_bytes(512) == "512 B"
      assert SystemMonitorReducerTui.format_bytes(1_048_576) == "1.0 MB"
      assert SystemMonitorReducerTui.format_bytes(1_073_741_824) == "1.0 GB"
    end

    test "safe_ratio/2 handles zero denominator" do
      assert SystemMonitorReducerTui.safe_ratio(100, 0) == 0.0
    end

    test "progress_bar/2 returns a bar string" do
      bar = SystemMonitorReducerTui.progress_bar(0.5, 10)
      assert String.starts_with?(bar, "[")
      assert String.ends_with?(bar, "]")
    end
  end

  describe "run/1" do
    test "starts and stops cleanly in test mode" do
      task =
        Task.async(fn ->
          SystemMonitorReducerTui.run(name: :test_reducer_run, test_mode: {80, 24})
        end)

      Process.sleep(100)
      pid = Process.whereis(:test_reducer_run)
      GenServer.stop(pid)
      assert Task.await(task, 1000) == :ok
    end
  end

  # -- Helpers --

  defp key(code), do: %Event.Key{code: code, kind: "press"}
end
