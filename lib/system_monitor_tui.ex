defmodule SystemMonitorTui do
  @moduledoc """
  TUI system monitor for BEAM and host metrics.

  Shows host system information, memory usage, CPU load, disk usage,
  scheduler utilization, process counts, and a live table of the top
  processes by memory. Uses tabs to switch between an overview dashboard
  and a detailed process list.

  ## Running

      SystemMonitorTui.run()

  ## Controls

  - `1` / `2` — switch tabs (Overview / Processes)
  - `j` / `down` — scroll down in process table
  - `k` / `up` — scroll up in process table
  - `q` — quit
  """

  use ExRatatui.App

  alias ExRatatui.Event
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph, Table, Tabs}
  alias ExRatatui.Widgets.List, as: WList

  @refresh_ms 1_000
  @top_n 20
  @meminfo_total_re ~r/MemTotal:\s+(\d+)\s+kB/
  @meminfo_available_re ~r/MemAvailable:\s+(\d+)\s+kB/
  @meminfo_cached_re ~r/^Cached:\s+(\d+)\s+kB/m
  @meminfo_free_re ~r/MemFree:\s+(\d+)\s+kB/
  @meminfo_swap_total_re ~r/SwapTotal:\s+(\d+)\s+kB/
  @meminfo_swap_free_re ~r/SwapFree:\s+(\d+)\s+kB/

  # -- Callbacks --

  @impl true
  def mount(_opts) do
    :erlang.system_flag(:scheduler_wall_time, true)
    schedule_refresh()
    host = collect_host_info()
    {:ok, build_state(0, 0, nil, host)}
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: "1", kind: "press"}, state) do
    {:noreply, %{state | tab: 0}}
  end

  def handle_event(%Event.Key{code: "2", kind: "press"}, state) do
    {:noreply, %{state | tab: 1}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state)
      when code in ["j", "Down"] do
    max = length(state.top_procs) - 1
    {:noreply, %{state | selected: min(state.selected + 1, max)}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state)
      when code in ["k", "Up"] do
    {:noreply, %{state | selected: max(state.selected - 1, 0)}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    schedule_refresh()
    {:noreply, build_state(state.tab, state.selected, state.prev_sched_sample, state.host)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header_area, tabs_area, body_area, footer_area] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:length, 3},
        {:min, 0},
        {:length, 1}
      ])

    body_widgets =
      case state.tab do
        0 -> render_overview(state, body_area)
        1 -> render_processes(state, body_area)
      end

    [
      {header_widget(state), header_area},
      {tabs_widget(state.tab), tabs_area},
      {footer_widget(), footer_area}
      | body_widgets
    ]
  end

  # -- Header / Tabs / Footer --

  defp header_widget(state) do
    load = state.cpu_load

    load_text =
      "Load AVG: #{format_load(load.load1)}  #{format_load(load.load5)}  #{format_load(load.load15)}"

    %Paragraph{
      text: "  BEAM System Monitor              #{load_text}",
      style: %Style{fg: :cyan, modifiers: [:bold]},
      block: %Block{
        title: " ExRatatui + Nerves ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }
  end

  defp tabs_widget(selected) do
    %Tabs{
      titles: ["[1] Overview", "[2] Processes"],
      selected: selected,
      style: %Style{fg: :dark_gray},
      highlight_style: %Style{fg: :yellow, modifiers: [:bold]},
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp footer_widget do
    %Paragraph{
      text: " 1/2: tabs | j/k: scroll | q: quit",
      style: %Style{fg: :dark_gray}
    }
  end

  # -- Overview Tab (3x2 grid) --

  defp render_overview(state, area) do
    [top_area, mid_area, bottom_area] =
      Layout.split(area, :vertical, [{:percentage, 30}, {:percentage, 28}, {:percentage, 42}])

    [host_area, beam_area] =
      Layout.split(top_area, :horizontal, [{:percentage, 50}, {:percentage, 50}])

    [mem_area, load_area] =
      Layout.split(mid_area, :horizontal, [{:percentage, 50}, {:percentage, 50}])

    [pools_area, sched_area] =
      Layout.split(bottom_area, :horizontal, [{:percentage, 50}, {:percentage, 50}])

    [
      {host_info_widget(state), host_area},
      {system_info_widget(state), beam_area},
      {memory_detail_widget(state), mem_area},
      {load_and_disk_widget(state), load_area},
      {memory_pools_widget(state), pools_area},
      {scheduler_widget(state), sched_area}
    ]
  end

  defp host_info_widget(state) do
    host = state.host

    {net_name, net_ip} =
      case host.primary_ip do
        {name, ip} -> {name, ip}
        nil -> {"--", "N/A"}
      end

    items = [
      "  OS:       #{host.os}",
      "  Kernel:   #{host.kernel}",
      "  CPU:      #{host.cpu_model} (#{host.cpu_cores})",
      "  Arch:     #{host.arch}",
      "  Uptime:   #{format_uptime_seconds(state.host_uptime)}",
      "  IP:       #{net_ip} (#{net_name})"
    ]

    %WList{
      items: items,
      style: %Style{fg: :white},
      block: %Block{
        title: " #{host.hostname} ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }
  end

  defp system_info_widget(state) do
    items = [
      "  OTP:          #{state.sys.otp_release}",
      "  ERTS:         #{state.sys.erts_version}",
      "  Elixir:       #{state.sys.elixir_version}",
      "  Schedulers:   #{state.sys.schedulers_online}/#{state.sys.schedulers}",
      "  Processes:    #{state.sys.process_count}/#{state.sys.process_limit}",
      "  Ports:        #{state.sys.port_count}/#{state.sys.port_limit}",
      "  Atoms:        #{state.sys.atom_count}/#{state.sys.atom_limit}",
      "  Uptime:       #{format_uptime(state.sys.uptime_ms)}"
    ]

    %WList{
      items: items,
      style: %Style{fg: :white},
      block: %Block{
        title: " System Info ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }
  end

  defp memory_detail_widget(state) do
    mem = state.mem
    used = mem.total - mem.available
    ram_ratio = safe_ratio(used, mem.total)
    swap_ratio = safe_ratio(mem.swap_used, mem.swap_total)

    color = ratio_color(ram_ratio)

    ram_bar = progress_bar(ram_ratio, 18)
    swap_bar = progress_bar(swap_ratio, 18)
    ram_pct = percentage_str(ram_ratio)
    swap_pct = percentage_str(swap_ratio)

    items = [
      "  RAM:  #{ram_bar} #{format_bytes(used)}/#{format_bytes(mem.total)}  #{ram_pct}",
      "  Swap: #{swap_bar} #{format_bytes(mem.swap_used)}/#{format_bytes(mem.swap_total)}  #{swap_pct}",
      "",
      "  Cached: #{format_bytes(mem.cached)}   Free: #{format_bytes(mem.mem_free)}"
    ]

    %WList{
      items: items,
      style: %Style{fg: color},
      block: %Block{
        title: " Memory ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }
  end

  defp load_and_disk_widget(state) do
    load = state.cpu_load
    cores = state.sys.schedulers_online

    l1_ratio = safe_ratio(load.load1, cores)
    l5_ratio = safe_ratio(load.load5, cores)
    l15_ratio = safe_ratio(load.load15, cores)

    load_color = ratio_color(Enum.max([l1_ratio, l5_ratio, l15_ratio]))

    l1_bar = progress_bar(l1_ratio, 15)
    l5_bar = progress_bar(l5_ratio, 15)
    l15_bar = progress_bar(l15_ratio, 15)

    temp_line =
      case state.cpu_temp do
        nil -> "  Temp:     N/A"
        temp -> "  Temp:     #{Float.round(temp, 1)} C#{temp_indicator(temp)}"
      end

    disk = state.disk
    disk_ratio = safe_ratio(disk.used, disk.total)
    disk_bar = progress_bar(disk_ratio, 15)
    disk_pct = percentage_str(disk_ratio)

    items = [
      "  Load 1m:  #{l1_bar}  #{format_load(load.load1)}",
      "  Load 5m:  #{l5_bar}  #{format_load(load.load5)}",
      "  Load 15m: #{l15_bar}  #{format_load(load.load15)}",
      temp_line,
      "  Disk /:   #{disk_bar}  #{format_bytes(disk.used)}/#{format_bytes(disk.total)}  #{disk_pct}"
    ]

    %WList{
      items: items,
      style: %Style{fg: load_color},
      block: %Block{
        title: " CPU & Disk ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }
  end

  defp memory_pools_widget(state) do
    pools = [
      {"Processes", state.mem.processes, state.mem.beam_total},
      {"Binary", state.mem.binary, state.mem.beam_total},
      {"ETS", state.mem.ets, state.mem.beam_total},
      {"Atom", state.mem.atom, state.mem.beam_total},
      {"Code", state.mem.code, state.mem.beam_total}
    ]

    rows =
      Enum.map(pools, fn {name, used, total} ->
        ratio = safe_ratio(used, total)
        pct = Float.round(ratio * 100, 1)
        bar = progress_bar(ratio, 15)
        ["  #{name}", bar, "#{format_bytes(used)}", "#{pct}%"]
      end)

    %Table{
      rows: rows,
      header: ["  Pool", "Usage", "Size", "%"],
      widths: [{:percentage, 25}, {:percentage, 35}, {:percentage, 25}, {:percentage, 15}],
      style: %Style{fg: :white},
      block: %Block{
        title: " Memory Pools ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }
  end

  defp scheduler_widget(state) do
    items =
      state.sys.scheduler_usage
      |> Enum.with_index(1)
      |> Enum.map(fn {usage, idx} ->
        pct = Float.round(usage * 100, 1)
        bar = progress_bar(usage, 20)
        "  Sched #{String.pad_leading(Integer.to_string(idx), 2)}  #{bar}  #{pct}%"
      end)

    %WList{
      items: items,
      style: %Style{fg: :green},
      block: %Block{
        title: " Scheduler Utilization ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }
  end

  # -- Processes Tab --

  defp render_processes(state, area) do
    rows =
      Enum.map(state.top_procs, fn proc ->
        [
          proc.name,
          Integer.to_string(proc.memory),
          format_bytes(proc.memory),
          Integer.to_string(proc.reductions),
          Integer.to_string(proc.message_queue_len)
        ]
      end)

    table = %Table{
      rows: rows,
      header: ["Process", "Mem (bytes)", "Mem", "Reductions", "MsgQ"],
      widths: [
        {:percentage, 30},
        {:percentage, 18},
        {:percentage, 17},
        {:percentage, 20},
        {:percentage, 15}
      ],
      selected: state.selected,
      highlight_style: %Style{fg: :black, bg: :cyan, modifiers: [:bold]},
      highlight_symbol: " > ",
      style: %Style{fg: :white},
      column_spacing: 1,
      block: %Block{
        title: " Top #{@top_n} Processes by Memory ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }

    [{table, area}]
  end

  # -- State builder --

  defp build_state(tab, selected, prev_sched_sample, host) do
    {scheduler_usage, new_sample} = collect_scheduler_usage(prev_sched_sample)

    %{
      tab: tab,
      selected: selected,
      mem: collect_memory(),
      sys: collect_system_info(scheduler_usage),
      host: host,
      host_uptime: read_host_uptime(),
      cpu_load: read_cpu_load(),
      cpu_temp: read_cpu_temp(),
      disk: read_disk(),
      top_procs: collect_top_processes(@top_n),
      prev_sched_sample: new_sample
    }
  end

  # -- Host info (collected once at startup) --

  defp collect_host_info do
    %{
      hostname: read_hostname(),
      os: read_os_name(),
      kernel: read_kernel_version(),
      cpu_model: read_cpu_model(),
      cpu_cores: :erlang.system_info(:logical_processors),
      arch: read_arch(),
      primary_ip: read_primary_ip()
    }
  end

  defp read_hostname, do: parse_hostname_file(File.read("/etc/hostname"))

  @doc false
  def parse_hostname_file({:ok, name}), do: String.trim(name)
  def parse_hostname_file(_), do: to_string(:net_adm.localhost())

  defp read_os_name, do: parse_os_release_file(File.read("/etc/os-release"))

  @doc false
  def parse_os_release_file({:ok, content}) do
    case Regex.run(~r/PRETTY_NAME="([^"]+)"/, content) do
      [_, name] -> name
      _ -> "Linux"
    end
  end

  def parse_os_release_file(_) do
    {family, name} = :os.type()
    "#{family}/#{name}"
  end

  defp read_kernel_version, do: parse_proc_version_file(File.read("/proc/version"))

  @doc false
  def parse_proc_version_file({:ok, content}) do
    case Regex.run(~r/Linux version (\S+)/, content) do
      [_, version] -> version
      _ -> "Linux"
    end
  end

  def parse_proc_version_file(_) do
    to_string(:erlang.system_info(:system_version)) |> String.trim()
  end

  defp read_cpu_model, do: parse_cpuinfo_file(File.read("/proc/cpuinfo"))

  @doc false
  def parse_cpuinfo_file({:ok, content}) do
    cond do
      match = Regex.run(~r/model name\s*:\s*(.+)/i, content) ->
        match |> Enum.at(1) |> String.trim() |> shorten_cpu_name()

      match = Regex.run(~r/Hardware\s*:\s*(.+)/i, content) ->
        Enum.at(match, 1) |> String.trim()

      match = Regex.run(~r/Model\s*:\s*(.+)/i, content) ->
        Enum.at(match, 1) |> String.trim()

      true ->
        "Unknown"
    end
  end

  def parse_cpuinfo_file(_), do: "Unknown"

  @doc false
  def shorten_cpu_name(name) do
    name
    |> String.replace(~r/\(R\)|\(TM\)/i, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp read_arch do
    to_string(:erlang.system_info(:system_architecture))
    |> String.split("-")
    |> List.first("unknown")
  end

  defp read_primary_ip, do: parse_ifaddrs(:inet.getifaddrs())

  @doc false
  def parse_ifaddrs({:ok, addrs}) do
    addrs
    |> Enum.flat_map(fn {name, opts} ->
      name_str = to_string(name)

      if name_str in ["lo", "lo0"] do
        []
      else
        opts
        |> Keyword.get_values(:addr)
        |> Enum.filter(fn addr -> tuple_size(addr) == 4 end)
        |> Enum.map(fn ip -> {name_str, ip_to_string(ip)} end)
      end
    end)
    |> List.first()
  end

  def parse_ifaddrs(_), do: nil

  # -- Dynamic data collection --

  defp collect_memory do
    beam = :erlang.memory()
    build_memory_map(File.read("/proc/meminfo"), beam)
  end

  @doc false
  def build_memory_map({:ok, content}, beam) do
    total_kb = parse_meminfo_kb(content, @meminfo_total_re)
    available_kb = parse_meminfo_kb(content, @meminfo_available_re)
    cached_kb = parse_meminfo_kb(content, @meminfo_cached_re)
    free_kb = parse_meminfo_kb(content, @meminfo_free_re)
    swap_total_kb = parse_meminfo_kb(content, @meminfo_swap_total_re)
    swap_free_kb = parse_meminfo_kb(content, @meminfo_swap_free_re)

    %{
      total: total_kb * 1024,
      available: available_kb * 1024,
      cached: cached_kb * 1024,
      mem_free: free_kb * 1024,
      swap_total: swap_total_kb * 1024,
      swap_used: (swap_total_kb - swap_free_kb) * 1024,
      beam_total: beam[:total],
      processes: beam[:processes],
      binary: beam[:binary],
      ets: beam[:ets],
      atom: beam[:atom],
      code: beam[:code]
    }
  end

  def build_memory_map(_, beam) do
    total = beam[:total]

    %{
      total: total * 2,
      available: total,
      cached: 0,
      mem_free: total,
      swap_total: 0,
      swap_used: 0,
      beam_total: total,
      processes: beam[:processes],
      binary: beam[:binary],
      ets: beam[:ets],
      atom: beam[:atom],
      code: beam[:code]
    }
  end

  @doc false
  def parse_meminfo_kb(content, regex) do
    case Regex.run(regex, content) do
      [_, kb_str] -> String.to_integer(kb_str)
      _ -> 0
    end
  end

  defp collect_system_info(scheduler_usage) do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    %{
      otp_release: to_string(:erlang.system_info(:otp_release)),
      erts_version: to_string(:erlang.system_info(:version)),
      elixir_version: System.version(),
      schedulers: :erlang.system_info(:schedulers),
      schedulers_online: :erlang.system_info(:schedulers_online),
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      port_count: :erlang.system_info(:port_count),
      port_limit: :erlang.system_info(:port_limit),
      atom_count: :erlang.system_info(:atom_count),
      atom_limit: :erlang.system_info(:atom_limit),
      uptime_ms: uptime_ms,
      scheduler_usage: scheduler_usage
    }
  end

  defp read_cpu_load, do: parse_loadavg_file(File.read("/proc/loadavg"))

  @doc false
  def parse_loadavg_file({:ok, content}) do
    case String.split(content) do
      [l1, l5, l15 | _] ->
        %{load1: parse_float(l1), load5: parse_float(l5), load15: parse_float(l15)}

      _ ->
        %{load1: 0.0, load5: 0.0, load15: 0.0}
    end
  end

  def parse_loadavg_file(_), do: %{load1: 0.0, load5: 0.0, load15: 0.0}

  defp read_cpu_temp, do: parse_thermal_file(File.read("/sys/class/thermal/thermal_zone0/temp"))

  @doc false
  def parse_thermal_file({:ok, content}) do
    case content |> String.trim() |> Integer.parse() do
      {millideg, _} -> millideg / 1000.0
      :error -> nil
    end
  end

  def parse_thermal_file(_), do: nil

  defp read_disk do
    output = :os.cmd(~c"df -k / 2>/dev/null") |> to_string()
    parse_df_output(output)
  end

  @doc false
  def parse_df_output(output) do
    case String.split(output, "\n", trim: true) do
      [_header, data_line | _] ->
        case String.split(data_line, ~r/\s+/) do
          [_, total_str, used_str | _] ->
            total = String.to_integer(total_str) * 1024
            used = String.to_integer(used_str) * 1024
            %{total: total, used: used}

          _ ->
            %{total: 0, used: 0}
        end

      _ ->
        %{total: 0, used: 0}
    end
  rescue
    _ -> %{total: 0, used: 0}
  end

  defp read_host_uptime, do: parse_proc_uptime_file(File.read("/proc/uptime"))

  @doc false
  def parse_proc_uptime_file({:ok, content}) do
    case content |> String.split(" ") |> List.first() |> Float.parse() do
      {seconds, _} -> trunc(seconds)
      :error -> 0
    end
  end

  def parse_proc_uptime_file(_) do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end

  defp collect_scheduler_usage(prev_sample) do
    online = :erlang.system_info(:schedulers_online)
    wall_times = :erlang.statistics(:scheduler_wall_time_all)
    compute_scheduler_usage(wall_times, prev_sample, online)
  end

  @doc false
  def compute_scheduler_usage(wall_times, prev_sample, online) when is_list(wall_times) do
    current =
      wall_times
      |> Enum.filter(fn {id, _, _} -> id <= online end)
      |> Enum.sort_by(fn {id, _, _} -> id end)

    usage =
      case prev_sample do
        nil ->
          List.duplicate(0.0, online)

        prev ->
          Enum.zip(prev, current)
          |> Enum.map(fn {{_, prev_active, prev_total}, {_, cur_active, cur_total}} ->
            delta_total = cur_total - prev_total

            if delta_total > 0 do
              (cur_active - prev_active) / delta_total
            else
              0.0
            end
          end)
      end

    {usage, current}
  end

  def compute_scheduler_usage(_, _prev_sample, online) do
    {List.duplicate(0.0, online), nil}
  end

  defp collect_top_processes(n) do
    Process.list()
    |> Enum.map(&process_info/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.memory, :desc)
    |> Enum.take(n)
  end

  @doc false
  def process_info(pid) do
    case Process.info(pid, [:registered_name, :memory, :reductions, :message_queue_len]) do
      nil ->
        nil

      info ->
        name =
          case info[:registered_name] do
            [] -> inspect(pid)
            name -> inspect(name)
          end

        %{
          name: name,
          memory: info[:memory] || 0,
          reductions: info[:reductions] || 0,
          message_queue_len: info[:message_queue_len] || 0
        }
    end
  end

  # -- Helpers --

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_ms)
  end

  @doc false
  def safe_ratio(_num, 0), do: 0.0
  def safe_ratio(num, denom), do: (num / denom) |> max(0.0) |> min(1.0)

  @doc false
  def ratio_color(ratio) do
    cond do
      ratio > 0.85 -> :red
      ratio > 0.65 -> :yellow
      true -> :green
    end
  end

  @doc false
  def temp_indicator(temp) do
    cond do
      temp >= 80 -> " !!!"
      temp >= 70 -> " !!"
      temp >= 55 -> " !"
      true -> ""
    end
  end

  @doc false
  def format_bytes(bytes) when is_number(bytes) and bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  def format_bytes(bytes) when is_number(bytes) and bytes >= 1_048_576,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  def format_bytes(bytes) when is_number(bytes) and bytes >= 1024,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  def format_bytes(bytes) when is_number(bytes), do: "#{bytes} B"
  def format_bytes(_), do: "0 B"

  @doc false
  def format_uptime(ms) do
    format_uptime_seconds(div(ms, 1000))
  end

  @doc false
  def format_uptime_seconds(total_seconds) do
    days = div(total_seconds, 86_400)
    hours = div(rem(total_seconds, 86_400), 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{minutes}m"
      hours > 0 -> "#{hours}h #{minutes}m #{seconds}s"
      true -> "#{minutes}m #{seconds}s"
    end
  end

  @doc false
  def format_load(value) do
    :erlang.float_to_binary(value, decimals: 2)
  end

  @doc false
  def parse_float(str) do
    case Float.parse(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  @doc false
  def percentage_str(ratio) do
    pct = (ratio * 100) |> Float.round(0) |> trunc()
    "#{pct}%"
  end

  @doc false
  def progress_bar(ratio, width) do
    filled = round(ratio * width)
    empty = width - filled
    "[" <> String.duplicate("\u2588", filled) <> String.duplicate("\u2591", empty) <> "]"
  end

  @doc false
  def ip_to_string({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  # -- Entry point --

  @doc """
  Starts the system monitor TUI and blocks until it exits.

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
