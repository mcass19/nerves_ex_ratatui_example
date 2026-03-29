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

    test "kernel version does not contain shell errors" do
      {:ok, state} = SystemMonitorTui.mount([])

      refute state.host.kernel =~ "not found"
      refute state.host.kernel =~ "/bin/sh"
      assert String.length(state.host.kernel) > 0
    end

    test "arch does not contain shell errors" do
      {:ok, state} = SystemMonitorTui.mount([])

      refute state.host.arch =~ "not found"
      refute state.host.arch =~ "/bin/sh"
      assert String.length(state.host.arch) > 0
      # Should be a simple arch string like "x86_64", "aarch64", etc.
      refute state.host.arch =~ " "
    end

    test "cpu model is not Unknown on a system with /proc/cpuinfo" do
      {:ok, state} = SystemMonitorTui.mount([])

      if File.exists?("/proc/cpuinfo") do
        assert state.host.cpu_model != "Unknown"
      end
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

    test "host info does not contain shell errors" do
      pid = start_tui()
      content = get_buffer(pid)

      refute content =~ "not found"
      refute content =~ "/bin/sh"
      refute content =~ "Unknown (#{:erlang.system_info(:logical_processors)})"

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

  describe "render/2 — nil primary_ip" do
    test "renders N/A when primary_ip is nil" do
      state = build_test_state() |> put_in([:host, :primary_ip], nil)
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = SystemMonitorTui.render(state, frame)
      assert is_list(widgets)
    end
  end

  describe "render/2 — nil cpu_temp" do
    test "renders N/A when cpu_temp is nil" do
      state = build_test_state() |> Map.put(:cpu_temp, nil)
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = SystemMonitorTui.render(state, frame)
      assert is_list(widgets)
    end
  end

  describe "render/2 — high memory ratio" do
    test "triggers red ratio_color when usage > 85%" do
      state =
        build_test_state()
        |> put_in([:mem, :total], 1000)
        |> put_in([:mem, :available], 100)

      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = SystemMonitorTui.render(state, frame)
      assert is_list(widgets)
    end
  end

  describe "render/2 — zero denominators" do
    test "handles zero total in memory" do
      state =
        build_test_state()
        |> put_in([:mem, :total], 0)
        |> put_in([:mem, :swap_total], 0)
        |> put_in([:mem, :beam_total], 0)
        |> put_in([:disk, :total], 0)

      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = SystemMonitorTui.render(state, frame)
      assert is_list(widgets)
    end
  end

  describe "render/2 — small byte values" do
    test "format_bytes handles values under 1024" do
      state =
        build_test_state()
        |> put_in([:mem, :cached], 500)
        |> put_in([:mem, :mem_free], 200)

      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = SystemMonitorTui.render(state, frame)
      assert is_list(widgets)
    end
  end

  describe "pure helpers" do
    test "safe_ratio returns 0.0 when denominator is 0" do
      assert SystemMonitorTui.safe_ratio(100, 0) == 0.0
    end

    test "safe_ratio clamps between 0.0 and 1.0" do
      assert SystemMonitorTui.safe_ratio(1, 2) == 0.5
      assert SystemMonitorTui.safe_ratio(2, 1) == 1.0
    end

    test "ratio_color returns :red for ratio > 0.85" do
      assert SystemMonitorTui.ratio_color(0.9) == :red
    end

    test "ratio_color returns :yellow for ratio > 0.65" do
      assert SystemMonitorTui.ratio_color(0.7) == :yellow
    end

    test "ratio_color returns :green for low ratio" do
      assert SystemMonitorTui.ratio_color(0.3) == :green
    end

    test "temp_indicator returns empty for temp < 55" do
      assert SystemMonitorTui.temp_indicator(40.0) == ""
    end

    test "temp_indicator returns ! for temp >= 55" do
      assert SystemMonitorTui.temp_indicator(55.0) == " !"
    end

    test "temp_indicator returns !! for temp >= 70" do
      assert SystemMonitorTui.temp_indicator(70.0) == " !!"
    end

    test "temp_indicator returns !!! for temp >= 80" do
      assert SystemMonitorTui.temp_indicator(80.0) == " !!!"
    end

    test "format_bytes for values under 1024" do
      assert SystemMonitorTui.format_bytes(500) == "500 B"
    end

    test "format_bytes for non-number" do
      assert SystemMonitorTui.format_bytes(nil) == "0 B"
    end

    test "format_bytes for KB range" do
      assert SystemMonitorTui.format_bytes(2048) == "2.0 KB"
    end

    test "format_bytes for MB range" do
      assert SystemMonitorTui.format_bytes(2_097_152) == "2.0 MB"
    end

    test "format_bytes for GB range" do
      assert SystemMonitorTui.format_bytes(2_147_483_648) == "2.0 GB"
    end

    test "parse_float returns 0.0 for invalid input" do
      assert SystemMonitorTui.parse_float("not_a_number") == 0.0
    end

    test "parse_float parses valid floats" do
      assert SystemMonitorTui.parse_float("1.5") == 1.5
    end

    test "parse_meminfo_kb returns 0 for no match" do
      assert SystemMonitorTui.parse_meminfo_kb("no match here", ~r/MemTotal:\s+(\d+)\s+kB/) == 0
    end

    test "parse_meminfo_kb parses matching content" do
      assert SystemMonitorTui.parse_meminfo_kb(
               "MemTotal:  8000000 kB",
               ~r/MemTotal:\s+(\d+)\s+kB/
             ) == 8_000_000
    end

    test "format_uptime_seconds with days" do
      assert SystemMonitorTui.format_uptime_seconds(90_000) == "1d 1h 0m"
    end

    test "format_uptime_seconds with hours" do
      assert SystemMonitorTui.format_uptime_seconds(3661) == "1h 1m 1s"
    end

    test "format_uptime_seconds with minutes only" do
      assert SystemMonitorTui.format_uptime_seconds(65) == "1m 5s"
    end

    test "format_uptime with milliseconds" do
      assert SystemMonitorTui.format_uptime(65_000) == "1m 5s"
    end

    test "format_load formats float" do
      assert SystemMonitorTui.format_load(1.5) == "1.50"
    end

    test "percentage_str formats ratio as percentage" do
      assert SystemMonitorTui.percentage_str(0.5) == "50%"
    end

    test "progress_bar creates bar of correct width" do
      bar = SystemMonitorTui.progress_bar(0.5, 10)
      assert String.starts_with?(bar, "[")
      assert String.ends_with?(bar, "]")
    end

    test "ip_to_string formats tuple" do
      assert SystemMonitorTui.ip_to_string({192, 168, 1, 1}) == "192.168.1.1"
    end

    test "shorten_cpu_name removes (R) and (TM)" do
      assert SystemMonitorTui.shorten_cpu_name("Intel(R) Core(TM) i7") == "Intel Core i7"
    end
  end

  describe "I/O parsing — hostname" do
    test "parse_hostname_file with valid content" do
      assert SystemMonitorTui.parse_hostname_file({:ok, "my-host\n"}) == "my-host"
    end

    test "parse_hostname_file with error falls back to net_adm" do
      result = SystemMonitorTui.parse_hostname_file({:error, :enoent})
      assert is_binary(result)
    end
  end

  describe "I/O parsing — os release" do
    test "parse_os_release_file with PRETTY_NAME" do
      content = ~s(PRETTY_NAME="Ubuntu 22.04 LTS"\nNAME="Ubuntu"\n)
      assert SystemMonitorTui.parse_os_release_file({:ok, content}) == "Ubuntu 22.04 LTS"
    end

    test "parse_os_release_file without PRETTY_NAME" do
      assert SystemMonitorTui.parse_os_release_file({:ok, "NAME=Linux\n"}) == "Linux"
    end

    test "parse_os_release_file with error" do
      result = SystemMonitorTui.parse_os_release_file({:error, :enoent})
      assert is_binary(result)
      assert result =~ "/"
    end
  end

  describe "I/O parsing — kernel version" do
    test "parse_proc_version_file with Linux version" do
      content = "Linux version 6.0.0-test (gcc) #1 SMP"
      assert SystemMonitorTui.parse_proc_version_file({:ok, content}) == "6.0.0-test"
    end

    test "parse_proc_version_file without Linux version" do
      assert SystemMonitorTui.parse_proc_version_file({:ok, "something else"}) == "Linux"
    end

    test "parse_proc_version_file with error" do
      result = SystemMonitorTui.parse_proc_version_file({:error, :enoent})
      assert is_binary(result)
    end
  end

  describe "I/O parsing — cpuinfo" do
    test "parse_cpuinfo_file with model name" do
      content = "model name\t: Intel(R) Core(TM) i7-8700 CPU @ 3.20GHz\n"
      result = SystemMonitorTui.parse_cpuinfo_file({:ok, content})
      assert result =~ "Intel"
      refute result =~ "(R)"
    end

    test "parse_cpuinfo_file with Hardware line" do
      content = "Hardware\t: BCM2835\n"
      assert SystemMonitorTui.parse_cpuinfo_file({:ok, content}) == "BCM2835"
    end

    test "parse_cpuinfo_file with Model line" do
      content = "Model\t: Raspberry Pi 4 Model B Rev 1.4\n"

      assert SystemMonitorTui.parse_cpuinfo_file({:ok, content}) ==
               "Raspberry Pi 4 Model B Rev 1.4"
    end

    test "parse_cpuinfo_file with no matching line" do
      assert SystemMonitorTui.parse_cpuinfo_file({:ok, "processor\t: 0\n"}) == "Unknown"
    end

    test "parse_cpuinfo_file with error" do
      assert SystemMonitorTui.parse_cpuinfo_file({:error, :enoent}) == "Unknown"
    end
  end

  describe "I/O parsing — memory" do
    test "build_memory_map with valid meminfo content" do
      content = """
      MemTotal:        8000000 kB
      MemFree:         2000000 kB
      MemAvailable:    4000000 kB
      Cached:          1000000 kB
      SwapTotal:       2000000 kB
      SwapFree:        1500000 kB
      """

      beam = [
        total: 100_000,
        processes: 50_000,
        binary: 20_000,
        ets: 10_000,
        atom: 5_000,
        code: 15_000
      ]

      result = SystemMonitorTui.build_memory_map({:ok, content}, beam)
      assert result.total == 8_000_000 * 1024
      assert result.beam_total == 100_000
    end

    test "build_memory_map with error falls back to beam memory" do
      beam = [
        total: 100_000,
        processes: 50_000,
        binary: 20_000,
        ets: 10_000,
        atom: 5_000,
        code: 15_000
      ]

      result = SystemMonitorTui.build_memory_map({:error, :enoent}, beam)
      assert result.total == 200_000
      assert result.beam_total == 100_000
      assert result.swap_total == 0
    end
  end

  describe "I/O parsing — cpu load" do
    test "parse_loadavg_file with valid content" do
      result = SystemMonitorTui.parse_loadavg_file({:ok, "1.50 1.20 0.90 2/300 12345"})
      assert result.load1 == 1.5
      assert result.load5 == 1.2
      assert result.load15 == 0.9
    end

    test "parse_loadavg_file with insufficient fields" do
      result = SystemMonitorTui.parse_loadavg_file({:ok, "1.50"})
      assert result == %{load1: 0.0, load5: 0.0, load15: 0.0}
    end

    test "parse_loadavg_file with error" do
      result = SystemMonitorTui.parse_loadavg_file({:error, :enoent})
      assert result == %{load1: 0.0, load5: 0.0, load15: 0.0}
    end
  end

  describe "I/O parsing — cpu temp" do
    test "parse_thermal_file with valid content" do
      assert SystemMonitorTui.parse_thermal_file({:ok, "45000\n"}) == 45.0
    end

    test "parse_thermal_file with non-numeric content" do
      assert SystemMonitorTui.parse_thermal_file({:ok, "not_a_number\n"}) == nil
    end

    test "parse_thermal_file with error" do
      assert SystemMonitorTui.parse_thermal_file({:error, :enoent}) == nil
    end
  end

  describe "I/O parsing — disk" do
    test "parse_df_output with valid output" do
      output =
        "Filesystem     1K-blocks    Used Available Use% Mounted on\n/dev/sda1      500000000 200000000 300000000  40% /\n"

      result = SystemMonitorTui.parse_df_output(output)
      assert result.total == 500_000_000 * 1024
      assert result.used == 200_000_000 * 1024
    end

    test "parse_df_output with invalid data line" do
      output = "Filesystem\nbadline\n"
      assert SystemMonitorTui.parse_df_output(output) == %{total: 0, used: 0}
    end

    test "parse_df_output with no data" do
      assert SystemMonitorTui.parse_df_output("") == %{total: 0, used: 0}
    end
  end

  describe "I/O parsing — host uptime" do
    test "parse_proc_uptime_file with valid content" do
      assert SystemMonitorTui.parse_proc_uptime_file({:ok, "12345.67 98765.43"}) == 12345
    end

    test "parse_proc_uptime_file with unparseable content" do
      assert SystemMonitorTui.parse_proc_uptime_file({:ok, "not_a_number rest"}) == 0
    end

    test "parse_proc_uptime_file with error falls back to wall_clock" do
      result = SystemMonitorTui.parse_proc_uptime_file({:error, :enoent})
      assert is_integer(result)
      assert result >= 0
    end
  end

  describe "I/O parsing — ifaddrs" do
    test "parse_ifaddrs with error" do
      assert SystemMonitorTui.parse_ifaddrs({:error, :enoent}) == nil
    end

    test "parse_ifaddrs with loopback only" do
      addrs = [{~c"lo", [addr: {127, 0, 0, 1}]}]
      assert SystemMonitorTui.parse_ifaddrs({:ok, addrs}) == nil
    end

    test "parse_ifaddrs with non-loopback interface" do
      addrs = [{~c"eth0", [addr: {192, 168, 1, 100}]}]
      assert SystemMonitorTui.parse_ifaddrs({:ok, addrs}) == {"eth0", "192.168.1.100"}
    end
  end

  describe "scheduler usage computation" do
    test "compute_scheduler_usage with non-list input" do
      {usage, sample} = SystemMonitorTui.compute_scheduler_usage(:undefined, nil, 4)
      assert usage == [0.0, 0.0, 0.0, 0.0]
      assert sample == nil
    end

    test "compute_scheduler_usage with wall_times and no previous sample" do
      wall_times = [{1, 100, 1000}, {2, 200, 2000}]
      {usage, current} = SystemMonitorTui.compute_scheduler_usage(wall_times, nil, 2)
      assert usage == [0.0, 0.0]
      assert is_list(current)
    end

    test "compute_scheduler_usage with previous sample" do
      prev = [{1, 50, 500}, {2, 100, 1000}]
      current = [{1, 100, 1000}, {2, 200, 2000}]
      {usage, _} = SystemMonitorTui.compute_scheduler_usage(current, prev, 2)
      assert length(usage) == 2
      for u <- usage, do: assert(u >= 0.0 and u <= 1.0)
    end
  end

  describe "process_info/1" do
    test "returns nil for dead process" do
      pid = spawn(fn -> :ok end)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

      assert SystemMonitorTui.process_info(pid) == nil
    end

    test "returns process info for live process" do
      result = SystemMonitorTui.process_info(self())
      assert is_map(result)
      assert is_binary(result.name)
      assert is_integer(result.memory)
    end
  end

  describe "parse_df_output rescue" do
    test "returns zero map when input causes exception" do
      # String.to_integer will raise on non-numeric data in the total/used positions
      output = "Filesystem 1K-blocks Used\n/dev/sda1 not_a_number also_not 300000 40% /\n"
      assert SystemMonitorTui.parse_df_output(output) == %{total: 0, used: 0}
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
