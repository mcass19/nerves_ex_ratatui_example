defmodule SystemMonitorTuiTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event

  describe "init/1" do
    test "returns initial state with expected keys" do
      {:ok, state} = SystemMonitorTui.init([])

      assert state.tab == 0
      assert state.selected == 0
      assert is_map(state.host)
      assert is_map(state.metrics)
      assert state.prev_sched_sample == nil or is_list(state.prev_sched_sample)
    end

    test "initial state seeds history ring buffers" do
      {:ok, state} = SystemMonitorTui.init([])

      assert is_list(state.ram_history)
      assert is_list(state.load_history)
      assert is_list(state.sched_history)
      assert length(state.ram_history) == length(state.sched_history)
      assert length(state.ram_history) == length(state.load_history)
    end

    test "metrics contains expected data" do
      {:ok, state} = SystemMonitorTui.init([])
      m = state.metrics

      assert is_map(m.mem)
      assert is_map(m.sys)
      assert is_map(m.cpu_load)
      assert is_list(m.top_procs)
      assert is_integer(m.host_uptime)
    end

    test "host info has expected keys" do
      {:ok, state} = SystemMonitorTui.init([])

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
      {:ok, state} = SystemMonitorTui.init([])
      %{state: state}
    end

    test "q stops the TUI", %{state: state} do
      assert {:stop, ^state} = SystemMonitorTui.update({:event, key("q")}, state)
    end

    test "1 switches to overview tab", %{state: state} do
      state = %{state | tab: 2}
      {:noreply, next} = SystemMonitorTui.update({:event, key("1")}, state)
      assert next.tab == 0
    end

    test "2 switches to processes tab", %{state: state} do
      {:noreply, next} = SystemMonitorTui.update({:event, key("2")}, state)
      assert next.tab == 1
    end

    test "3 switches to graphs tab", %{state: state} do
      {:noreply, next} = SystemMonitorTui.update({:event, key("3")}, state)
      assert next.tab == 2
    end

    test "j/Down scrolls down in process table", %{state: state} do
      state = %{state | tab: 1}
      {:noreply, next} = SystemMonitorTui.update({:event, key("j")}, state)
      assert next.selected == 1

      {:noreply, next} = SystemMonitorTui.update({:event, key("Down")}, state)
      assert next.selected == 1
    end

    test "k/Up scrolls up in process table", %{state: state} do
      state = %{state | selected: 2}
      {:noreply, next} = SystemMonitorTui.update({:event, key("k")}, state)
      assert next.selected == 1

      {:noreply, next} = SystemMonitorTui.update({:event, key("Up")}, state)
      assert next.selected == 1
    end

    test "k/Up doesn't scroll below zero", %{state: state} do
      {:noreply, next} = SystemMonitorTui.update({:event, key("k")}, state)
      assert next.selected == 0
    end

    test "unknown events are ignored", %{state: state} do
      assert {:noreply, ^state} =
               SystemMonitorTui.update({:event, key("x")}, state)
    end
  end

  describe "update/2 — info messages" do
    setup do
      {:ok, state} = SystemMonitorTui.init([])
      %{state: state}
    end

    test ":refresh returns async command and skips render", %{state: state} do
      {:noreply, ^state, opts} = SystemMonitorTui.update({:info, :refresh}, state)

      assert opts[:render?] == false
      assert [%ExRatatui.Command{kind: :async}] = opts[:commands]
    end

    test ":refresh command fun collects metrics and mapper wraps them", %{state: state} do
      {:noreply, _, opts} = SystemMonitorTui.update({:info, :refresh}, state)
      [%ExRatatui.Command{kind: :async, fun: fun, mapper: mapper}] = opts[:commands]

      metrics = fun.()
      assert is_map(metrics.mem)
      assert is_map(metrics.sys)
      assert {:metrics_collected, ^metrics} = mapper.(metrics)
    end

    test "{:metrics_collected, metrics} updates state and rotates history", %{state: state} do
      metrics = SystemMonitorTui.collect_metrics(nil)

      {:noreply, next} =
        SystemMonitorTui.update({:info, {:metrics_collected, metrics}}, state)

      assert next.metrics == metrics
      assert next.prev_sched_sample == metrics.sched_sample

      # History rings rotate in place — length never grows.
      assert length(next.ram_history) == length(state.ram_history)
      assert length(next.load_history) == length(state.load_history)
      assert length(next.sched_history) == length(state.sched_history)
    end
  end

  describe "subscriptions/1" do
    test "declares a 1-second refresh interval" do
      {:ok, state} = SystemMonitorTui.init([])
      subs = SystemMonitorTui.subscriptions(state)

      assert [%ExRatatui.Subscription{id: :refresh, kind: :interval, interval_ms: 1_000}] = subs
    end
  end

  describe "render/2" do
    test "overview tab returns header + tabs + footer + 4 panels + 2 memory gauges" do
      {:ok, state} = SystemMonitorTui.init([])
      frame = %ExRatatui.Frame{width: 140, height: 40}

      widgets = SystemMonitorTui.render(state, frame)

      # header + tabs + footer + host + beam + pools + sched + ram gauge + beam gauge = 9
      assert length(widgets) == 9

      for {widget, rect} <- widgets do
        assert is_struct(widget)
        assert %ExRatatui.Layout.Rect{} = rect
      end
    end

    test "processes tab returns header + tabs + footer + 1 table" do
      {:ok, state} = SystemMonitorTui.init([])
      state = %{state | tab: 1}
      frame = %ExRatatui.Frame{width: 140, height: 40}

      widgets = SystemMonitorTui.render(state, frame)

      assert length(widgets) == 4
    end

    test "graphs tab returns header + tabs + footer + 3 graphs" do
      {:ok, state} = SystemMonitorTui.init([])
      state = %{state | tab: 2}
      frame = %ExRatatui.Frame{width: 140, height: 40}

      widgets = SystemMonitorTui.render(state, frame)

      assert length(widgets) == 6
    end

    test "overview renders high-load red badge and nil primary_ip fallback" do
      {:ok, state} = SystemMonitorTui.init([])
      frame = %ExRatatui.Frame{width: 140, height: 40}

      cores = state.host.cpu_cores

      crushed = %{
        state.metrics
        | cpu_load: %{load1: cores * 2.0, load5: cores * 1.0, load15: 0.1}
      }

      state = %{state | host: %{state.host | primary_ip: nil}, metrics: crushed}

      widgets = SystemMonitorTui.render(state, frame)
      assert length(widgets) == 9
    end

    test "processes tab renders all memory/msgq color bands" do
      {:ok, state} = SystemMonitorTui.init([])
      frame = %ExRatatui.Frame{width: 140, height: 40}

      top = [
        %{name: "huge", memory: 80 * 1_048_576, reductions: 1, message_queue_len: 0},
        %{name: "big", memory: 10 * 1_048_576, reductions: 2, message_queue_len: 50},
        %{name: "flood", memory: 1024, reductions: 3, message_queue_len: 500}
      ]

      state = %{state | tab: 1, metrics: %{state.metrics | top_procs: top}}

      widgets = SystemMonitorTui.render(state, frame)
      assert length(widgets) == 4
    end

    test "sched_avg_percent falls back to 0 when scheduler_usage is empty" do
      {:ok, state} = SystemMonitorTui.init([])
      metrics = %{state.metrics | sys: %{state.metrics.sys | scheduler_usage: []}}

      {:noreply, next} =
        SystemMonitorTui.update({:info, {:metrics_collected, metrics}}, state)

      assert List.last(next.sched_history) == 0
    end

    test "BEAM pools title surfaces current proc/bin/ets/code readouts" do
      {:ok, state} = SystemMonitorTui.init([])

      mem = %{
        state.metrics.mem
        | processes: 45 * 1_048_576,
          binary: 8 * 1_048_576,
          ets: 2 * 1_048_576,
          code: 21 * 1_048_576
      }

      state = %{state | metrics: %{state.metrics | mem: mem}}
      title_text = overview_title(state, "BEAM pools")

      assert title_text =~ "BEAM pools"
      assert title_text =~ "now"
      assert title_text =~ "proc 45.0 MB"
      assert title_text =~ "bin 8.0 MB"
      assert title_text =~ "ets 2.0 MB"
      assert title_text =~ "code 21.0 MB"
    end

    test "BEAM pools title tints each readout with the bar color" do
      {:ok, state} = SystemMonitorTui.init([])
      mb = 1_048_576

      mem = %{
        state.metrics.mem
        | processes: 45 * mb,
          binary: 8 * mb,
          ets: 2 * mb,
          code: 21 * mb
      }

      state = %{state | metrics: %{state.metrics | mem: mem}}
      bar_chart = overview_widget(state, "BEAM pools")
      spans = bar_chart.block.title.spans

      assert Enum.any?(spans, fn s -> s.content == "45.0 MB" and s.style.fg == :cyan end)
      assert Enum.any?(spans, fn s -> s.content == "8.0 MB" and s.style.fg == :magenta end)
      assert Enum.any?(spans, fn s -> s.content == "2.0 MB" and s.style.fg == :yellow end)
      assert Enum.any?(spans, fn s -> s.content == "21.0 MB" and s.style.fg == :green end)
    end

    test "Scheduler utilization title surfaces avg and peak percentages" do
      {:ok, state} = SystemMonitorTui.init([])
      sys = %{state.metrics.sys | scheduler_usage: [0.1, 0.2, 0.9, 0.4]}
      state = %{state | metrics: %{state.metrics | sys: sys}}

      title_text = overview_title(state, "Scheduler utilization")

      assert title_text =~ "Scheduler utilization"
      assert title_text =~ "avg 40%"
      assert title_text =~ "peak 90%"
    end

    test "Scheduler utilization title handles empty usage list" do
      {:ok, state} = SystemMonitorTui.init([])
      sys = %{state.metrics.sys | scheduler_usage: []}
      state = %{state | metrics: %{state.metrics | sys: sys}}

      title_text = overview_title(state, "Scheduler utilization")

      assert title_text =~ "avg 0%"
      assert title_text =~ "peak 0%"
    end

    test "Scheduler utilization clamps out-of-range samples before rendering" do
      {:ok, state} = SystemMonitorTui.init([])
      # Negative and >1.0 samples should be clamped into 0..100 before the
      # title renders them, so no "-10%" or "200%" ever reaches the user.
      sys = %{state.metrics.sys | scheduler_usage: [-0.1, 1.5, 0.5]}
      state = %{state | metrics: %{state.metrics | sys: sys}}

      title_text = overview_title(state, "Scheduler utilization")

      refute title_text =~ "-"
      assert title_text =~ "peak 100%"
    end
  end

  describe "integration: test terminal" do
    test "boots, renders the overview, and quits cleanly" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: SystemMonitorTui,
          name: nil,
          test_mode: {140, 40}
        )

      try do
        _ = :sys.get_state(pid)
        %{terminal_ref: terminal_ref} = :sys.get_state(pid)

        content = ExRatatui.get_buffer_content(terminal_ref)

        assert content =~ "BEAM Monitor"
        assert content =~ "Overview"
        assert content =~ "Processes"
        assert content =~ "Graphs"

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
          mod: SystemMonitorTui,
          name: nil,
          test_mode: {140, 40}
        )

      try do
        _ = :sys.get_state(pid)

        :ok = ExRatatui.Runtime.inject_event(pid, key("2"))
        %{user_state: state} = :sys.get_state(pid)
        assert state.tab == 1

        :ok = ExRatatui.Runtime.inject_event(pid, key("3"))
        %{user_state: state} = :sys.get_state(pid)
        assert state.tab == 2

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
      assert SystemMonitorTui.format_uptime_seconds(30) == "0m 30s"
      assert SystemMonitorTui.format_uptime_seconds(3661) == "1h 1m 1s"
      assert SystemMonitorTui.format_uptime_seconds(86_461) == "1d 0h 1m"
    end

    test "format_bytes/1" do
      assert SystemMonitorTui.format_bytes(512) == "512 B"
      assert SystemMonitorTui.format_bytes(1_048_576) == "1.0 MB"
      assert SystemMonitorTui.format_bytes(1_073_741_824) == "1.0 GB"
    end

    test "safe_ratio/2 handles zero denominator" do
      assert SystemMonitorTui.safe_ratio(100, 0) == 0.0
    end

    test "percentage_str/1 formats ratios as 0..100%" do
      assert SystemMonitorTui.percentage_str(0.0) == "0%"
      assert SystemMonitorTui.percentage_str(0.5) == "50%"
      assert SystemMonitorTui.percentage_str(1.0) == "100%"
    end

    test "format_load/1 keeps two decimals" do
      assert SystemMonitorTui.format_load(0.5) == "0.50"
      assert SystemMonitorTui.format_load(1.234) == "1.23"
    end

    test "format_bytes/1 handles non-numeric input" do
      assert SystemMonitorTui.format_bytes(nil) == "0 B"
      assert SystemMonitorTui.format_bytes("oops") == "0 B"
    end

    test "format_bytes/1 covers KB and sub-KB ranges" do
      assert SystemMonitorTui.format_bytes(2048) == "2.0 KB"
      assert SystemMonitorTui.format_bytes(0) == "0 B"
    end

    test "format_uptime/1 converts milliseconds" do
      assert SystemMonitorTui.format_uptime(90_000) == "1m 30s"
    end

    test "build_memory_map/2 falls back when /proc/meminfo is unavailable" do
      beam = :erlang.memory()
      mem = SystemMonitorTui.build_memory_map({:error, :enoent}, beam)

      assert mem.total == beam[:total] * 2
      assert mem.available == beam[:total]
      assert mem.beam_total == beam[:total]
    end

    test "build_memory_map/2 parses /proc/meminfo content" do
      beam = :erlang.memory()
      content = "MemTotal:       16000000 kB\nMemAvailable:    8000000 kB\n"
      mem = SystemMonitorTui.build_memory_map({:ok, content}, beam)

      assert mem.total == 16_000_000 * 1024
      assert mem.available == 8_000_000 * 1024
    end
  end

  describe "run/1" do
    test "starts and stops cleanly in test mode" do
      task =
        Task.async(fn ->
          SystemMonitorTui.run(name: :test_sysmon_run, test_mode: {80, 24})
        end)

      Process.sleep(100)
      pid = Process.whereis(:test_sysmon_run)
      GenServer.stop(pid)
      assert Task.await(task, 1000) == :ok
    end
  end

  # -- Helpers --

  defp key(code), do: %Event.Key{code: code, kind: "press"}

  defp overview_widget(state, title_prefix) do
    frame = %ExRatatui.Frame{width: 140, height: 40}

    state
    |> SystemMonitorTui.render(frame)
    |> Enum.find_value(fn {widget, _rect} ->
      if match?(%ExRatatui.Widgets.BarChart{}, widget) and
           widget_title_text(widget) =~ title_prefix,
         do: widget
    end)
  end

  defp overview_title(state, title_prefix) do
    state |> overview_widget(title_prefix) |> widget_title_text()
  end

  defp widget_title_text(%{block: %{title: %{spans: spans}}}) do
    Enum.map_join(spans, "", & &1.content)
  end
end
