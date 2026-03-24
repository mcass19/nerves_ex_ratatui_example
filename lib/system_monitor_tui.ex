defmodule SystemMonitorTui do
  @moduledoc """
  TUI system monitor for BEAM and host metrics.

  Shows memory usage, scheduler utilization, process counts, and a live
  table of the top processes by memory. Uses tabs to switch between an
  overview dashboard and a detailed process list.

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
  alias ExRatatui.Widgets.{Block, Gauge, Paragraph, Table, Tabs}
  alias ExRatatui.Widgets.List, as: WList

  @refresh_ms 1_000
  @top_n 20
  @meminfo_total_re ~r/MemTotal:\s+(\d+)\s+kB/
  @meminfo_available_re ~r/MemAvailable:\s+(\d+)\s+kB/

  # -- Callbacks --

  @impl true
  def mount(_opts) do
    :erlang.system_flag(:scheduler_wall_time, true)
    schedule_refresh()
    {:ok, build_state(0, 0, nil)}
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
    {:noreply, build_state(state.tab, state.selected, state.prev_sched_sample)}
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
      {header_widget(), header_area},
      {tabs_widget(state.tab), tabs_area},
      {footer_widget(), footer_area}
      | body_widgets
    ]
  end

  # -- Header / Tabs / Footer --

  defp header_widget do
    %Paragraph{
      text: "  BEAM System Monitor",
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

    [mem_area, info_area] =
      Layout.split(top_area, :horizontal, [{:percentage, 50}, {:percentage, 50}])

    [pools_area, sched_area] =
      Layout.split(bottom_area, :horizontal, [{:percentage, 50}, {:percentage, 50}])

    [
      {memory_gauge(state), mem_area},
      {system_info_widget(state), info_area},
      {memory_pools_widget(state), pools_area},
      {scheduler_widget(state), sched_area}
    ]
  end

  defp memory_gauge(state) do
    used = state.mem.total - state.mem.free
    ratio = safe_ratio(used, state.mem.total)
    label = "#{format_bytes(used)} / #{format_bytes(state.mem.total)}"

    color =
      cond do
        ratio > 0.85 -> :red
        ratio > 0.65 -> :yellow
        true -> :green
      end

    %Gauge{
      ratio: ratio,
      label: label,
      gauge_style: %Style{fg: color},
      block: %Block{
        title: " Memory Usage ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
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

  defp build_state(tab, selected, prev_sched_sample) do
    {scheduler_usage, new_sample} = collect_scheduler_usage(prev_sched_sample)

    %{
      tab: tab,
      selected: selected,
      mem: collect_memory(),
      sys: collect_system_info(scheduler_usage),
      top_procs: collect_top_processes(@top_n),
      prev_sched_sample: new_sample
    }
  end

  defp collect_memory do
    beam = :erlang.memory()
    {sys_total, sys_available} = read_system_memory()

    %{
      total: sys_total,
      free: sys_available,
      beam_total: beam[:total],
      processes: beam[:processes],
      binary: beam[:binary],
      ets: beam[:ets],
      atom: beam[:atom],
      code: beam[:code]
    }
  end

  defp read_system_memory do
    case File.read("/proc/meminfo") do
      {:ok, content} ->
        total_kb = parse_meminfo_kb(content, @meminfo_total_re)
        available_kb = parse_meminfo_kb(content, @meminfo_available_re)

        if total_kb > 0 and available_kb > 0 do
          {total_kb * 1024, available_kb * 1024}
        else
          fallback_memory()
        end

      {:error, _} ->
        fallback_memory()
    end
  end

  defp fallback_memory do
    total = :erlang.memory(:total)
    {total * 2, total}
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

  defp collect_scheduler_usage(prev_sample) do
    online = :erlang.system_info(:schedulers_online)

    case :erlang.statistics(:scheduler_wall_time_all) do
      wall_times when is_list(wall_times) ->
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

      _ ->
        {List.duplicate(0.0, online), nil}
    end
  end

  defp collect_top_processes(n) do
    Process.list()
    |> Enum.map(fn pid ->
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
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.memory, :desc)
    |> Enum.take(n)
  end

  # -- Helpers --

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_ms)
  end

  defp safe_ratio(_num, 0), do: 0.0
  defp safe_ratio(num, denom), do: (num / denom) |> max(0.0) |> min(1.0)

  defp format_bytes(bytes) when bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp format_bytes(bytes) when bytes >= 1_048_576,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_bytes(bytes) when bytes >= 1024,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes), do: "#{bytes} B"

  defp format_uptime(ms) do
    total_seconds = div(ms, 1000)
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

  defp progress_bar(ratio, width) do
    filled = round(ratio * width)
    empty = width - filled
    "[" <> String.duplicate("█", filled) <> String.duplicate("░", empty) <> "]"
  end

  # -- Entry point --

  @doc """
  Starts the system monitor TUI and blocks until it exits.
  """
  def run do
    {:ok, pid} = start_link([])
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end
  end
end
