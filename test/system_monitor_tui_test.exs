defmodule SystemMonitorTuiTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event

  describe "mount/1" do
    test "returns initial state with all expected keys" do
      {:ok, state} = SystemMonitorTui.mount([])

      assert state.tab == 0
      assert state.selected == 0
      assert is_map(state.mem)
      assert is_map(state.sys)
      assert is_map(state.host)
      assert is_map(state.cpu_load)
      assert is_map(state.disk)
      assert is_integer(state.host_uptime)
      assert is_list(state.top_procs)
      assert state.prev_sched_sample == nil or is_list(state.prev_sched_sample)
    end

    test "host info has expected keys" do
      {:ok, state} = SystemMonitorTui.mount([])

      assert is_binary(state.host.hostname)
      assert is_binary(state.host.os)
      assert is_binary(state.host.kernel)
      assert is_binary(state.host.cpu_model)
      assert is_integer(state.host.cpu_cores)
      assert state.host.cpu_cores > 0
      assert is_binary(state.host.arch)
    end

    test "cpu load and disk have expected keys" do
      {:ok, state} = SystemMonitorTui.mount([])

      assert is_float(state.cpu_load.load1)
      assert is_float(state.cpu_load.load5)
      assert is_float(state.cpu_load.load15)
      assert is_integer(state.disk.total)
      assert is_integer(state.disk.used)
      assert state.disk.total > 0
    end

    test "memory data has expected keys" do
      {:ok, state} = SystemMonitorTui.mount([])

      assert is_integer(state.mem.total)
      assert is_integer(state.mem.available)
      assert is_integer(state.mem.cached)
      assert is_integer(state.mem.mem_free)
      assert is_integer(state.mem.swap_total)
      assert is_integer(state.mem.swap_used)
      assert is_integer(state.mem.beam_total)
      assert is_integer(state.mem.processes)
      assert is_integer(state.mem.binary)
      assert is_integer(state.mem.ets)
      assert is_integer(state.mem.atom)
      assert is_integer(state.mem.code)
      assert state.mem.total > 0
      assert state.mem.beam_total > 0
    end

    test "system info has expected keys" do
      {:ok, state} = SystemMonitorTui.mount([])

      assert is_binary(state.sys.otp_release)
      assert is_binary(state.sys.erts_version)
      assert is_binary(state.sys.elixir_version)
      assert state.sys.schedulers > 0
      assert state.sys.schedulers_online > 0
      assert state.sys.process_count > 0
      assert state.sys.process_limit > state.sys.process_count
      assert is_integer(state.sys.port_count)
      assert state.sys.port_limit > 0
      assert state.sys.atom_count > 0
      assert state.sys.atom_limit > state.sys.atom_count
      assert is_integer(state.sys.uptime_ms)
      assert is_list(state.sys.scheduler_usage)
    end

    test "scheduler usage list matches online count" do
      {:ok, state} = SystemMonitorTui.mount([])

      assert length(state.sys.scheduler_usage) == state.sys.schedulers_online
    end

    test "initial scheduler usage is all zeros (no previous sample)" do
      {:ok, state} = SystemMonitorTui.mount([])

      assert Enum.all?(state.sys.scheduler_usage, &(&1 == 0.0))
    end

    test "top processes are sorted by memory descending" do
      {:ok, state} = SystemMonitorTui.mount([])

      memories = Enum.map(state.top_procs, & &1.memory)
      assert memories == Enum.sort(memories, :desc)
    end

    test "top processes have expected keys" do
      {:ok, state} = SystemMonitorTui.mount([])

      for proc <- state.top_procs do
        assert is_binary(proc.name)
        assert is_integer(proc.memory)
        assert is_integer(proc.reductions)
        assert is_integer(proc.message_queue_len)
      end
    end

    test "schedules a refresh message" do
      {:ok, _state} = SystemMonitorTui.mount([])

      assert_receive :refresh, 2_000
    end
  end

  describe "handle_event/2 — quit" do
    test "q stops the TUI" do
      state = build_test_state()

      assert {:stop, ^state} = SystemMonitorTui.handle_event(key("q"), state)
    end
  end

  describe "handle_event/2 — tab switching" do
    test "1 switches to overview tab" do
      state = build_test_state(tab: 1)

      {:noreply, state} = SystemMonitorTui.handle_event(key("1"), state)
      assert state.tab == 0
    end

    test "2 switches to processes tab" do
      state = build_test_state(tab: 0)

      {:noreply, state} = SystemMonitorTui.handle_event(key("2"), state)
      assert state.tab == 1
    end

    test "pressing current tab is a no-op on tab value" do
      state = build_test_state(tab: 0)

      {:noreply, state} = SystemMonitorTui.handle_event(key("1"), state)
      assert state.tab == 0
    end
  end

  describe "handle_event/2 — scrolling" do
    test "j scrolls down" do
      state = build_test_state(selected: 0)

      {:noreply, state} = SystemMonitorTui.handle_event(key("j"), state)
      assert state.selected == 1
    end

    test "Down arrow scrolls down" do
      state = build_test_state(selected: 0)

      {:noreply, state} = SystemMonitorTui.handle_event(key("Down"), state)
      assert state.selected == 1
    end

    test "k scrolls up" do
      state = build_test_state(selected: 3)

      {:noreply, state} = SystemMonitorTui.handle_event(key("k"), state)
      assert state.selected == 2
    end

    test "Up arrow scrolls up" do
      state = build_test_state(selected: 3)

      {:noreply, state} = SystemMonitorTui.handle_event(key("Up"), state)
      assert state.selected == 2
    end

    test "cannot scroll below 0" do
      state = build_test_state(selected: 0)

      {:noreply, state} = SystemMonitorTui.handle_event(key("k"), state)
      assert state.selected == 0
    end

    test "cannot scroll past last process" do
      proc_count = 5
      state = build_test_state(selected: proc_count - 1, proc_count: proc_count)

      {:noreply, state} = SystemMonitorTui.handle_event(key("j"), state)
      assert state.selected == proc_count - 1
    end
  end

  describe "handle_event/2 — unknown events" do
    test "unknown key is ignored" do
      state = build_test_state()

      {:noreply, new_state} = SystemMonitorTui.handle_event(key("z"), state)
      assert new_state == state
    end

    test "mouse event is ignored" do
      state = build_test_state()
      event = %Event.Mouse{kind: "down", button: "left", x: 0, y: 0}

      {:noreply, new_state} = SystemMonitorTui.handle_event(event, state)
      assert new_state == state
    end
  end

  describe "handle_info/2" do
    test "refresh rebuilds state and reschedules" do
      {:ok, initial_state} = SystemMonitorTui.mount([])
      # Drain the refresh from mount
      assert_receive :refresh, 2_000

      {:noreply, new_state} = SystemMonitorTui.handle_info(:refresh, initial_state)

      # State was rebuilt with fresh data
      assert is_map(new_state.mem)
      assert is_map(new_state.sys)
      assert is_list(new_state.top_procs)

      # A new refresh is scheduled
      assert_receive :refresh, 2_000
    end

    test "refresh preserves tab and selected" do
      state = build_test_state(tab: 1, selected: 5)

      {:noreply, new_state} = SystemMonitorTui.handle_info(:refresh, state)

      assert new_state.tab == 1
      assert new_state.selected == 5
    end

    test "unknown messages are ignored" do
      state = build_test_state()

      {:noreply, new_state} = SystemMonitorTui.handle_info(:unknown, state)
      assert new_state == state
    end
  end

  describe "render/2 — overview tab" do
    test "returns 9 widget-area pairs (header + tabs + footer + 6 body)" do
      {:ok, state} = SystemMonitorTui.mount([])
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = SystemMonitorTui.render(state, frame)

      # header + tabs + footer + host_info + system_info + memory + cpu_disk + memory_pools + scheduler
      assert length(widgets) == 9
    end

    test "all pairs are {widget_struct, rect}" do
      {:ok, state} = SystemMonitorTui.mount([])
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = SystemMonitorTui.render(state, frame)

      for {widget, rect} <- widgets do
        assert is_struct(widget)
        assert %ExRatatui.Layout.Rect{} = rect
      end
    end
  end

  describe "render/2 — processes tab" do
    test "returns 4 widget-area pairs (header + tabs + footer + table)" do
      {:ok, state} = SystemMonitorTui.mount([])
      state = %{state | tab: 1}
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = SystemMonitorTui.render(state, frame)

      # header + tabs + footer + process_table
      assert length(widgets) == 4
    end
  end

  describe "integration: test terminal — overview" do
    test "renders BEAM System Monitor header" do
      pid = start_tui()
      content = get_buffer(pid)

      assert content =~ "BEAM System Monitor"
      assert content =~ "ExRatatui + Nerves"

      stop_tui(pid)
    end

    test "renders tab bar with Overview selected" do
      pid = start_tui()
      content = get_buffer(pid)

      assert content =~ "Overview"
      assert content =~ "Processes"

      stop_tui(pid)
    end

    test "renders host info section" do
      pid = start_tui()
      content = get_buffer(pid)

      assert content =~ "OS:"
      assert content =~ "Kernel:"
      assert content =~ "CPU:"
      assert content =~ "Arch:"
      assert content =~ "Uptime:"
      assert content =~ "IP:"

      stop_tui(pid)
    end

    test "renders memory section with RAM and swap" do
      pid = start_tui()
      content = get_buffer(pid)

      assert content =~ "Memory"
      assert content =~ "RAM:"
      assert content =~ "Swap:"
      assert content =~ "Cached:"

      stop_tui(pid)
    end

    test "renders CPU and disk section" do
      pid = start_tui()
      content = get_buffer(pid)

      assert content =~ "CPU & Disk"
      assert content =~ "Load 1m:"
      assert content =~ "Load 5m:"
      assert content =~ "Load 15m:"
      assert content =~ "Disk /:"

      stop_tui(pid)
    end

    test "renders system info section" do
      pid = start_tui()
      content = get_buffer(pid)

      assert content =~ "System Info"
      assert content =~ "OTP"
      assert content =~ "Schedulers"
      assert content =~ "Processes"

      stop_tui(pid)
    end

    test "renders memory pools section" do
      pid = start_tui()
      content = get_buffer(pid)

      assert content =~ "Memory Pools"

      stop_tui(pid)
    end

    test "renders scheduler utilization section" do
      pid = start_tui()
      content = get_buffer(pid)

      assert content =~ "Scheduler Utilization"
      assert content =~ "Sched"

      stop_tui(pid)
    end

    test "renders footer with keybindings" do
      pid = start_tui()
      content = get_buffer(pid)

      assert content =~ "1/2: tabs"
      assert content =~ "j/k: scroll"
      assert content =~ "q: quit"

      stop_tui(pid)
    end
  end

  describe "integration: test terminal — processes tab" do
    test "switching to processes tab shows process table" do
      pid = start_tui()

      # Switch tab via :sys.replace_state (updates user_state inside server)
      :sys.replace_state(pid, fn server_state ->
        %{server_state | user_state: %{server_state.user_state | tab: 1}}
      end)

      # Trigger a re-render via a refresh
      send(pid, :refresh)
      _ = :sys.get_state(pid)

      content = get_buffer(pid)
      assert content =~ "Top"
      assert content =~ "by Memory"

      stop_tui(pid)
    end
  end

  describe "integration: scheduler delta sampling" do
    test "mount stores initial scheduler sample" do
      {:ok, state} = SystemMonitorTui.mount([])

      assert is_list(state.prev_sched_sample)
      assert length(state.prev_sched_sample) > 0
    end

    test "scheduler usage values are between 0.0 and 1.0 after refresh" do
      {:ok, state} = SystemMonitorTui.mount([])
      assert_receive :refresh, 2_000

      # Second sample gives delta-based usage
      {:noreply, state} = SystemMonitorTui.handle_info(:refresh, state)

      for usage <- state.sys.scheduler_usage do
        assert usage >= 0.0
        assert usage <= 1.0
      end
    end
  end

  describe "integration: lifecycle" do
    test "stops cleanly via GenServer.stop" do
      pid = start_tui()
      ref = Process.monitor(pid)

      GenServer.stop(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end

  # -- Helpers --

  defp key(code), do: %Event.Key{code: code, kind: "press"}

  defp build_test_state(overrides \\ []) do
    tab = Keyword.get(overrides, :tab, 0)
    selected = Keyword.get(overrides, :selected, 0)
    proc_count = Keyword.get(overrides, :proc_count, 20)

    top_procs =
      for i <- 1..proc_count do
        %{
          name: "proc_#{i}",
          memory: (proc_count - i + 1) * 1000,
          reductions: i * 100,
          message_queue_len: 0
        }
      end

    %{
      tab: tab,
      selected: selected,
      mem: %{
        total: 4_294_967_296,
        available: 2_147_483_648,
        cached: 1_073_741_824,
        mem_free: 1_073_741_824,
        swap_total: 2_147_483_648,
        swap_used: 536_870_912,
        beam_total: 100_000_000,
        processes: 45_000_000,
        binary: 22_000_000,
        ets: 8_000_000,
        atom: 1_500_000,
        code: 15_000_000
      },
      sys: %{
        otp_release: "27",
        erts_version: "15.0",
        elixir_version: "1.18.0",
        schedulers: 8,
        schedulers_online: 8,
        process_count: 312,
        process_limit: 262_144,
        port_count: 12,
        port_limit: 65_536,
        atom_count: 25_000,
        atom_limit: 1_048_576,
        uptime_ms: 8_130_000,
        scheduler_usage: List.duplicate(0.0, 8)
      },
      host: %{
        hostname: "test-host",
        os: "Linux Test",
        kernel: "6.0.0-test",
        cpu_model: "Test CPU",
        cpu_cores: 8,
        arch: "x86_64",
        primary_ip: {"eth0", "192.168.1.1"}
      },
      host_uptime: 86_400,
      cpu_load: %{load1: 1.5, load5: 1.2, load15: 0.9},
      cpu_temp: 45.0,
      disk: %{total: 500_000_000_000, used: 200_000_000_000},
      top_procs: top_procs,
      prev_sched_sample: nil
    }
  end

  defp start_tui do
    {:ok, pid} = SystemMonitorTui.start_link(name: nil, test_mode: {120, 40})
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
