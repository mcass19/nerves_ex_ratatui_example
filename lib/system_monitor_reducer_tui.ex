defmodule SystemMonitorReducerTui do
  @moduledoc """
  TUI system monitor using the **reducer runtime**.

  This module is functionally equivalent to `SystemMonitorTui` but uses
  `ExRatatui.App`'s reducer runtime (`init/1`, `update/2`, `subscriptions/1`)
  instead of the callback runtime (`mount/1`, `handle_event/2`, `handle_info/2`).

  The key differences:

    * A single `update/2` handles both terminal events (`{:event, e}`) and
      mailbox messages (`{:info, msg}`).
    * Periodic refresh is declared via `subscriptions/1` — the runtime
      manages the timer automatically.
    * Heavy `/proc` reads run in the background via `Command.async/2`, so
      the server process never blocks on file I/O.

  ## Running

      SystemMonitorReducerTui.run()

  ## Controls

  - `1` / `2` — switch tabs (Overview / Processes)
  - `j` / `Down` — scroll down in process table
  - `k` / `Up` — scroll up in process table
  - `q` — quit
  """

  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.{Command, Event, Layout, Layout.Rect, Style, Subscription}
  alias ExRatatui.Widgets.{Block, Paragraph, Table, Tabs}
  alias ExRatatui.Widgets.List, as: WList

  @refresh_ms 1_000
  @top_n 20

  # -- Reducer callbacks --

  @impl true
  def init(_opts) do
    :erlang.system_flag(:scheduler_wall_time, true)
    host = collect_host_info()
    metrics = collect_metrics(nil)

    state = %{
      tab: 0,
      selected: 0,
      host: host,
      metrics: metrics,
      prev_sched_sample: metrics.sched_sample
    }

    {:ok, state}
  end

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

  @impl true
  def update({:event, %Event.Key{code: "q", kind: "press"}}, state) do
    {:stop, state}
  end

  def update({:event, %Event.Key{code: "1", kind: "press"}}, state) do
    {:noreply, %{state | tab: 0}}
  end

  def update({:event, %Event.Key{code: "2", kind: "press"}}, state) do
    {:noreply, %{state | tab: 1}}
  end

  def update({:event, %Event.Key{code: code, kind: "press"}}, state)
      when code in ["j", "Down"] do
    max = length(state.metrics.top_procs) - 1
    {:noreply, %{state | selected: min(state.selected + 1, max)}}
  end

  def update({:event, %Event.Key{code: code, kind: "press"}}, state)
      when code in ["k", "Up"] do
    {:noreply, %{state | selected: max(state.selected - 1, 0)}}
  end

  def update({:info, :refresh}, state) do
    # Kick off an async command so the /proc reads happen off the
    # server process. The result flows back through update/2 as
    # {:info, {:metrics_collected, metrics}}.
    cmd =
      Command.async(
        fn -> collect_metrics(state.prev_sched_sample) end,
        fn metrics -> {:metrics_collected, metrics} end
      )

    {:noreply, state, commands: [cmd], render?: false}
  end

  def update({:info, {:metrics_collected, metrics}}, state) do
    {:noreply, %{state | metrics: metrics, prev_sched_sample: metrics.sched_sample}}
  end

  def update(_msg, state), do: {:noreply, state}

  @impl true
  def subscriptions(_state) do
    [Subscription.interval(:refresh, @refresh_ms, :refresh)]
  end

  # -- Header / Tabs / Footer --

  defp header_widget(state) do
    load = state.metrics.cpu_load

    load_text =
      "Load AVG: #{format_load(load.load1)}  #{format_load(load.load5)}  #{format_load(load.load15)}"

    %Paragraph{
      text: "  BEAM System Monitor (Reducer)     #{load_text}",
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

  # -- Overview Tab --

  defp render_overview(state, area) do
    [top_area, bottom_area] =
      Layout.split(area, :vertical, [{:percentage, 50}, {:percentage, 50}])

    [host_area, beam_area] =
      Layout.split(top_area, :horizontal, [{:percentage, 50}, {:percentage, 50}])

    [mem_area, sched_area] =
      Layout.split(bottom_area, :horizontal, [{:percentage, 50}, {:percentage, 50}])

    [
      {host_info_widget(state), host_area},
      {system_info_widget(state), beam_area},
      {memory_widget(state), mem_area},
      {scheduler_widget(state), sched_area}
    ]
  end

  defp host_info_widget(state) do
    host = state.host
    m = state.metrics

    {net_name, net_ip} =
      case host.primary_ip do
        {name, ip} -> {name, ip}
        nil -> {"--", "N/A"}
      end

    items = [
      "  OS:       #{host.os}",
      "  Kernel:   #{host.kernel}",
      "  CPU:      #{host.cpu_model} (#{host.cpu_cores})",
      "  Uptime:   #{format_uptime_seconds(m.host_uptime)}",
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
    sys = state.metrics.sys

    items = [
      "  OTP:          #{sys.otp_release}",
      "  ERTS:         #{sys.erts_version}",
      "  Elixir:       #{sys.elixir_version}",
      "  Schedulers:   #{sys.schedulers_online}/#{sys.schedulers}",
      "  Processes:    #{sys.process_count}/#{sys.process_limit}",
      "  Ports:        #{sys.port_count}/#{sys.port_limit}",
      "  Atoms:        #{sys.atom_count}/#{sys.atom_limit}",
      "  Uptime:       #{format_uptime(sys.uptime_ms)}"
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

  defp memory_widget(state) do
    mem = state.metrics.mem
    beam = mem.beam_total
    used = mem.total - mem.available
    ram_ratio = safe_ratio(used, mem.total)
    color = ratio_color(ram_ratio)

    ram_bar = progress_bar(ram_ratio, 18)
    ram_pct = percentage_str(ram_ratio)

    pools = [
      {"Processes", mem.processes, beam},
      {"Binary", mem.binary, beam},
      {"ETS", mem.ets, beam},
      {"Code", mem.code, beam}
    ]

    pool_lines =
      Enum.map(pools, fn {name, val, total} ->
        ratio = safe_ratio(val, total)
        "  #{String.pad_trailing(name, 11)} #{progress_bar(ratio, 12)} #{format_bytes(val)}"
      end)

    items =
      [
        "  RAM: #{ram_bar} #{format_bytes(used)}/#{format_bytes(mem.total)} #{ram_pct}",
        ""
      ] ++ pool_lines

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

  defp scheduler_widget(state) do
    items =
      state.metrics.sys.scheduler_usage
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
      Enum.map(state.metrics.top_procs, fn proc ->
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

  # -- Metrics collection (runs in Command.async) --

  @doc false
  def collect_metrics(prev_sched_sample) do
    {scheduler_usage, new_sample} = collect_scheduler_usage(prev_sched_sample)
    beam = :erlang.memory()

    %{
      mem: build_memory_map(File.read("/proc/meminfo"), beam),
      sys: collect_system_info(scheduler_usage),
      host_uptime: read_host_uptime(),
      cpu_load: read_cpu_load(),
      top_procs: collect_top_processes(@top_n),
      sched_sample: new_sample
    }
  end

  # -- Host info (collected once at init) --

  defp collect_host_info do
    %{
      hostname: read_hostname(),
      os: read_os_name(),
      kernel: read_kernel_version(),
      cpu_model: read_cpu_model(),
      cpu_cores: :erlang.system_info(:logical_processors),
      primary_ip: read_primary_ip()
    }
  end

  defp read_hostname do
    case File.read("/etc/hostname") do
      {:ok, name} -> String.trim(name)
      _ -> to_string(:net_adm.localhost())
    end
  end

  defp read_os_name do
    case File.read("/etc/os-release") do
      {:ok, content} ->
        case Regex.run(~r/PRETTY_NAME="([^"]+)"/, content) do
          [_, name] -> name
          _ -> "Linux"
        end

      _ ->
        {family, name} = :os.type()
        "#{family}/#{name}"
    end
  end

  defp read_kernel_version do
    case File.read("/proc/version") do
      {:ok, content} ->
        case Regex.run(~r/Linux version (\S+)/, content) do
          [_, version] -> version
          _ -> "Linux"
        end

      _ ->
        to_string(:erlang.system_info(:system_version)) |> String.trim()
    end
  end

  defp read_cpu_model do
    case File.read("/proc/cpuinfo") do
      {:ok, content} ->
        cond do
          match = Regex.run(~r/model name\s*:\s*(.+)/i, content) ->
            Enum.at(match, 1) |> String.trim() |> shorten_cpu_name()

          match = Regex.run(~r/Hardware\s*:\s*(.+)/i, content) ->
            Enum.at(match, 1) |> String.trim()

          true ->
            "Unknown"
        end

      _ ->
        "Unknown"
    end
  end

  defp shorten_cpu_name(name) do
    name
    |> String.replace(~r/\(R\)|\(TM\)/i, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp read_primary_ip do
    case :inet.getifaddrs() do
      {:ok, addrs} ->
        addrs
        |> Enum.flat_map(fn {name, opts} ->
          name_str = to_string(name)

          if name_str in ["lo", "lo0"] do
            []
          else
            opts
            |> Keyword.get_values(:addr)
            |> Enum.filter(fn addr -> tuple_size(addr) == 4 end)
            |> Enum.map(fn {a, b, c, d} -> {name_str, "#{a}.#{b}.#{c}.#{d}"} end)
          end
        end)
        |> List.first()

      _ ->
        nil
    end
  end

  # -- Dynamic data collection --

  @doc false
  def build_memory_map({:ok, content}, beam) do
    total_kb = parse_meminfo_kb(content, ~r/MemTotal:\s+(\d+)\s+kB/)
    available_kb = parse_meminfo_kb(content, ~r/MemAvailable:\s+(\d+)\s+kB/)

    %{
      total: total_kb * 1024,
      available: available_kb * 1024,
      beam_total: beam[:total],
      processes: beam[:processes],
      binary: beam[:binary],
      ets: beam[:ets],
      code: beam[:code]
    }
  end

  def build_memory_map(_, beam) do
    total = beam[:total]

    %{
      total: total * 2,
      available: total,
      beam_total: total,
      processes: beam[:processes],
      binary: beam[:binary],
      ets: beam[:ets],
      code: beam[:code]
    }
  end

  defp parse_meminfo_kb(content, regex) do
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

  defp read_cpu_load do
    case File.read("/proc/loadavg") do
      {:ok, content} ->
        case String.split(content) do
          [l1, l5, l15 | _] ->
            %{load1: parse_float(l1), load5: parse_float(l5), load15: parse_float(l15)}

          _ ->
            %{load1: 0.0, load5: 0.0, load15: 0.0}
        end

      _ ->
        %{load1: 0.0, load5: 0.0, load15: 0.0}
    end
  end

  defp read_host_uptime do
    case File.read("/proc/uptime") do
      {:ok, content} ->
        case content |> String.split(" ") |> List.first() |> Float.parse() do
          {seconds, _} -> trunc(seconds)
          :error -> 0
        end

      _ ->
        {uptime_ms, _} = :erlang.statistics(:wall_clock)
        div(uptime_ms, 1000)
    end
  end

  defp collect_scheduler_usage(prev_sample) do
    online = :erlang.system_info(:schedulers_online)
    wall_times = :erlang.statistics(:scheduler_wall_time_all)

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
  rescue
    _ -> {List.duplicate(0.0, :erlang.system_info(:schedulers_online)), nil}
  end

  defp collect_top_processes(n) do
    Process.list()
    |> Enum.map(&process_info/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.memory, :desc)
    |> Enum.take(n)
  end

  defp process_info(pid) do
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

  # -- Formatting helpers --

  @doc false
  def safe_ratio(_num, 0), do: 0.0
  def safe_ratio(num, denom), do: (num / denom) |> max(0.0) |> min(1.0)

  defp ratio_color(ratio) do
    cond do
      ratio > 0.85 -> :red
      ratio > 0.65 -> :yellow
      true -> :green
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
  def format_uptime(ms), do: format_uptime_seconds(div(ms, 1000))

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

  defp parse_float(str) do
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

  # -- Entry point --

  @doc """
  Starts the system monitor TUI (reducer runtime) and blocks until it exits.

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
