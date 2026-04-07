defmodule GiocciBench.Visualize do
  @moduledoc false

  alias GiocciBench.Output
  alias NimbleCSV.RFC4180, as: CSV

  @timing_columns ["elapsed_ms", "function_elapsed_ms"]

  @communication_columns [
    "client_to_relay",
    "relay_to_client",
    "relay_to_engine",
    "engine_to_relay",
    "client_to_engine",
    "engine_to_client"
  ]

  @ping_excluded_columns ["run_id", "target", "iteration", "success", "error"]
  @cpu_columns ["user", "nice", "system", "idle", "iowait", "irq", "softirq", "steal"]
  @svg_colors ["#0f766e", "#2563eb", "#d97706", "#dc2626", "#7c3aed", "#0891b2"]

  def generate_report(session_dir, output_path) do
    csv_files =
      session_dir
      |> Path.join("*.csv")
      |> Path.wildcard()
      |> Enum.sort()

    if csv_files == [] do
      {:error, :no_csv_files}
    else
      report_data =
        session_dir
        |> build_report_data(csv_files)
        |> export_chart_csvs(output_path)

      html = render_html(report_data)

      File.mkdir_p!(Path.dirname(output_path))
      File.write!(output_path, html)

      {:ok, output_path}
    end
  end

  def latest_session_dir(out_dir) do
    out_dir
    |> Path.join("session_*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.sort(:desc)
    |> List.first()
    |> case do
      nil -> {:error, :session_not_found}
      path -> {:ok, path}
    end
  end

  defp build_report_data(session_dir, csv_files) do
    metadata = read_session_metadata(session_dir)

    ordered_csv_files = order_csv_files(csv_files)

    sections =
      ordered_csv_files
      |> Enum.map(&build_section/1)
      |> Enum.reject(&is_nil/1)

    %{
      "title" => "Giocci Bench Visualization",
      "session_dir" => Path.basename(session_dir),
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "mfargs" => read_session_mfargs(metadata),
      "sections" => sections
    }
    |> maybe_put_session_title(read_session_title(metadata))
  end

  defp order_csv_files(csv_files) do
    mode = detect_mode(csv_files)

    csv_files
    |> Enum.sort_by(fn path ->
      file = Path.basename(path)
      {file_order_key(mode, file), file}
    end)
  end

  defp detect_mode(csv_files) do
    files = MapSet.new(Enum.map(csv_files, &Path.basename/1))

    cond do
      MapSet.member?(files, "register_client.csv") or MapSet.member?(files, "save_module.csv") or
          MapSet.member?(files, "exec_func.csv") ->
        :single

      MapSet.member?(files, "sequence.csv") ->
        :sequence

      MapSet.member?(files, "local_exec.csv") ->
        :local

      true ->
        :generic
    end
  end

  defp file_order_key(:single, "ping.csv"), do: 0
  defp file_order_key(:single, "register_client.csv"), do: 10
  defp file_order_key(:single, "save_module.csv"), do: 20
  defp file_order_key(:single, "exec_func.csv"), do: 30
  defp file_order_key(:single, "register_client_os_info_proc_stat.csv"), do: 40
  defp file_order_key(:single, "save_module_os_info_proc_stat.csv"), do: 50
  defp file_order_key(:single, "exec_func_os_info_proc_stat.csv"), do: 60
  defp file_order_key(:single, "register_client_os_info_free.csv"), do: 70
  defp file_order_key(:single, "save_module_os_info_free.csv"), do: 80
  defp file_order_key(:single, "exec_func_os_info_free.csv"), do: 90

  defp file_order_key(:sequence, "ping.csv"), do: 0
  defp file_order_key(:sequence, "sequence.csv"), do: 10
  defp file_order_key(:sequence, "sequence_os_info_proc_stat.csv"), do: 20
  defp file_order_key(:sequence, "sequence_os_info_free.csv"), do: 30

  defp file_order_key(:local, "local_exec.csv"), do: 10
  defp file_order_key(:local, "local_exec_os_info_proc_stat.csv"), do: 20
  defp file_order_key(:local, "local_exec_os_info_free.csv"), do: 30

  defp file_order_key(_mode, _file), do: 999

  defp export_chart_csvs(report_data, output_path) do
    report_dir = Path.join(Path.dirname(output_path), "report")
    File.mkdir_p!(report_dir)

    sections =
      report_data
      |> Map.get("sections", [])
      |> Enum.map(fn section ->
        section_id = Map.get(section, "id", "section")

        charts =
          section
          |> Map.get("charts", [])
          |> Enum.with_index(1)
          |> Enum.map(fn {chart, index} ->
            base_name =
              "#{sanitize_slug(section_id)}__#{index}_#{sanitize_slug(Map.get(chart, "title", "chart"))}"

            csv_name = "#{base_name}.csv"
            svg_name = "#{base_name}.svg"
            csv_path = Path.join(report_dir, csv_name)
            svg_path = Path.join(report_dir, svg_name)
            write_chart_csv!(csv_path, chart)
            write_chart_svg!(svg_path, chart)

            chart
            |> Map.put("csv_file", Path.join("report", csv_name))
            |> Map.put("svg_file", Path.join("report", svg_name))
          end)

        Map.put(section, "charts", charts)
      end)

    Map.put(report_data, "sections", sections)
  end

  defp write_chart_csv!(path, chart) do
    series = Map.get(chart, "series", [])

    x_values =
      series
      |> Enum.flat_map(fn s -> Enum.map(Map.get(s, "points", []), &Map.get(&1, "x")) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    if x_values != [] and series != [] do
      header = ["x" | Enum.map(series, &Map.get(&1, "name", "series"))]

      rows =
        Enum.map(x_values, fn x ->
          [x | Enum.map(series, fn s -> y_at_x(Map.get(s, "points", []), x) end)]
        end)

      Output.write_csv!(path, header, rows)
    else
      Output.write_csv!(path, ["x"], [])
    end
  end

  defp write_chart_svg!(path, chart) do
    width = 900
    height = 420
    margin_left = 64
    margin_right = 24
    margin_top = 24
    margin_bottom = 52
    plot_w = width - margin_left - margin_right
    plot_h = height - margin_top - margin_bottom

    series = Map.get(chart, "series", [])

    points =
      series
      |> Enum.flat_map(&Map.get(&1, "points", []))

    {x_min, x_max, y_min, y_max} =
      case points do
        [] ->
          {0.0, 1.0, 0.0, 1.0}

        _ ->
          xs = Enum.map(points, &Map.get(&1, "x", 0.0))
          ys = Enum.map(points, &Map.get(&1, "y", 0.0))
          {Enum.min(xs), Enum.max(xs), Enum.min(ys), Enum.max(ys)}
      end

    x_max = if x_min == x_max, do: x_max + 1.0, else: x_max
    y_max = if y_min == y_max, do: y_max + 1.0, else: y_max

    x_scale = fn x -> margin_left + (x - x_min) / (x_max - x_min) * plot_w end
    y_scale = fn y -> margin_top + (1.0 - (y - y_min) / (y_max - y_min)) * plot_h end

    ticks =
      0..4
      |> Enum.map(fn i ->
        x_tick = x_min + (x_max - x_min) * i / 4
        y_tick = y_min + (y_max - y_min) * (4 - i) / 4
        y_pos = margin_top + plot_h * i / 4
        x_pos = margin_left + plot_w * i / 4

        %{
          x_value: format_axis_value(x_tick, Map.get(chart, "x_label")),
          y_value: format_axis_value(y_tick, Map.get(chart, "y_label")),
          x_pos: x_pos,
          y_pos: y_pos
        }
      end)

    series_svg =
      series
      |> Enum.with_index()
      |> Enum.map(fn {s, idx} ->
        color = Enum.at(@svg_colors, rem(idx, length(@svg_colors)))

        polyline_points =
          s
          |> Map.get("points", [])
          |> Enum.map(fn p ->
            "#{Float.round(x_scale.(Map.get(p, "x", 0.0)), 2)},#{Float.round(y_scale.(Map.get(p, "y", 0.0)), 2)}"
          end)
          |> Enum.join(" ")

        "<polyline fill=\"none\" stroke=\"#{color}\" stroke-width=\"2\" points=\"#{polyline_points}\" />"
      end)
      |> Enum.join("\n")

    tick_labels =
      ticks
      |> Enum.map(fn t ->
        """
        <text x=\"6\" y=\"#{Float.round(t.y_pos + 4, 2)}\" font-size=\"11\" fill=\"#475569\">#{xml_escape(t.y_value)}</text>
        <text x=\"#{Float.round(t.x_pos - 12, 2)}\" y=\"#{height - margin_bottom + 18}\" font-size=\"11\" fill=\"#475569\">#{xml_escape(t.x_value)}</text>
        """
      end)
      |> Enum.join("\n")

    svg =
      """
      <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"#{width}\" height=\"#{height}\" viewBox=\"0 0 #{width} #{height}\">
        <rect x=\"0\" y=\"0\" width=\"#{width}\" height=\"#{height}\" fill=\"#ffffff\" />
        <line x1=\"#{margin_left}\" y1=\"#{margin_top}\" x2=\"#{margin_left}\" y2=\"#{height - margin_bottom}\" stroke=\"#94a3b8\" />
        <line x1=\"#{margin_left}\" y1=\"#{height - margin_bottom}\" x2=\"#{width - margin_right}\" y2=\"#{height - margin_bottom}\" stroke=\"#94a3b8\" />
        #{tick_labels}
        #{series_svg}
        <text x=\"#{margin_left + div(plot_w, 2) - 24}\" y=\"#{height - 8}\" font-size=\"12\" fill=\"#475569\">#{xml_escape(Map.get(chart, "x_label", "x"))}</text>
        <text x=\"#{margin_left}\" y=\"14\" font-size=\"12\" fill=\"#475569\">#{xml_escape(Map.get(chart, "y_label", "y"))}</text>
      </svg>
      """

    File.write!(path, svg)
  end

  defp format_axis_value(value, "iteration"), do: Integer.to_string(round(value))
  defp format_axis_value(value, _axis), do: :erlang.float_to_binary(value, decimals: 3)

  defp xml_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp y_at_x(points, x) do
    case Enum.find(points, fn p -> Map.get(p, "x") == x end) do
      nil -> nil
      point -> Map.get(point, "y")
    end
  end

  defp sanitize_slug(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> "item"
      slug -> slug
    end
  end

  defp read_session_metadata(session_dir) do
    meta_path = Path.join(session_dir, "meta.json")

    with true <- File.exists?(meta_path),
         {:ok, content} <- File.read(meta_path),
         metadata when is_map(metadata) <- :json.decode(content) do
      metadata
    else
      _ -> %{}
    end
  end

  defp read_session_mfargs(metadata) when is_map(metadata) do
    case Map.get(metadata, "cases") do
      cases when is_map(cases) -> cases
      _ -> %{}
    end
  end

  defp maybe_put_session_title(report_data, nil), do: report_data
  defp maybe_put_session_title(report_data, ""), do: report_data
  defp maybe_put_session_title(report_data, "nil"), do: report_data

  defp maybe_put_session_title(report_data, title),
    do: Map.put(report_data, "session_title", title)

  defp read_session_title(metadata) when is_map(metadata) do
    case Map.get(metadata, "title") do
      title when is_binary(title) ->
        String.trim(title)

      _ ->
        nil
    end
  end

  defp build_section(path) do
    filename = Path.basename(path)

    with {:ok, table} <- parse_csv(path) do
      cond do
        filename == "ping.csv" ->
          build_ping_section(filename, table)

        String.ends_with?(filename, "_os_info_free.csv") ->
          build_os_free_section(filename, table)

        String.ends_with?(filename, "_os_info_proc_stat.csv") ->
          build_os_proc_section(filename, table)

        true ->
          build_measurement_section(filename, table)
      end
    else
      {:error, _reason} -> nil
    end
  end

  defp parse_csv(path) do
    case File.read(path) do
      {:ok, content} ->
        rows = CSV.parse_string(content, skip_headers: false)

        case rows do
          [] ->
            {:error, :empty}

          [header | body] ->
            indexed_header =
              header
              |> Enum.with_index()
              |> Enum.reject(fn {key, _} -> String.trim(key) == "" end)

            records =
              Enum.map(body, fn row ->
                Map.new(indexed_header, fn {key, index} ->
                  {key, Enum.at(row, index, "")}
                end)
              end)

            {:ok, %{headers: Enum.map(indexed_header, &elem(&1, 0)), rows: records}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_measurement_section(filename, table) do
    x_key = "iteration"

    timing_series =
      @timing_columns
      |> Enum.filter(fn key -> has_numeric_value?(table.rows, key) end)
      |> Enum.map(&series_from_rows(table.rows, x_key, &1))
      |> Enum.reject(&is_nil/1)

    comm_series =
      @communication_columns
      |> Enum.filter(fn key -> has_numeric_value?(table.rows, key) end)
      |> Enum.map(&series_from_rows(table.rows, x_key, &1))
      |> Enum.reject(&is_nil/1)

    stats =
      numeric_stats(table.rows, ["elapsed_ms", "function_elapsed_ms" | @communication_columns])

    %{
      "id" => filename,
      "kind" => "measurement",
      "title" => filename,
      "stats" => stats,
      "charts" =>
        Enum.reject(
          [
            chart("Timing", "iteration", "ms", timing_series),
            chart("Communication", "iteration", "ms", comm_series)
          ],
          &is_nil/1
        )
    }
  end

  defp build_ping_section(filename, table) do
    grouped = Enum.group_by(table.rows, &Map.get(&1, "target", "unknown"))

    series =
      grouped
      |> Enum.map(fn {target, rows} ->
        points =
          rows
          |> Enum.sort_by(fn row -> parse_float(Map.get(row, "iteration")) || 0 end)
          |> Enum.map(fn row ->
            {parse_float(Map.get(row, "iteration")), parse_float(Map.get(row, "elapsed_ms"))}
          end)
          |> Enum.reject(fn {x, y} -> is_nil(x) or is_nil(y) end)
          |> Enum.map(fn {x, y} -> %{"x" => x, "y" => y} end)

        if points == [] do
          nil
        else
          %{"name" => target, "points" => points}
        end
      end)
      |> Enum.reject(&is_nil/1)

    stats = numeric_stats(table.rows, table.headers -- @ping_excluded_columns)

    %{
      "id" => filename,
      "kind" => "ping",
      "title" => filename,
      "stats" => stats,
      "charts" => [chart("Ping RTT", "iteration", "ms", series)] |> Enum.reject(&is_nil/1)
    }
  end

  defp build_os_free_section(filename, table) do
    time_key = "time[ms]"

    value_keys =
      table.headers
      |> Enum.reject(&(&1 == time_key))
      |> Enum.filter(fn key -> has_numeric_value?(table.rows, key) end)

    series =
      value_keys
      |> Enum.map(&series_from_rows(table.rows, time_key, &1, :seconds_from_start))
      |> Enum.reject(&is_nil/1)

    stats = numeric_stats(table.rows, value_keys)

    %{
      "id" => filename,
      "kind" => "os_free",
      "title" => filename,
      "stats" => stats,
      "charts" => [chart("Memory (free)", "time_s", "KiB", series)] |> Enum.reject(&is_nil/1)
    }
  end

  defp build_os_proc_section(filename, table) do
    usage_series = cpu_usage_series(table.rows)

    %{
      "id" => filename,
      "kind" => "os_proc",
      "title" => filename,
      "stats" =>
        case usage_series do
          [] -> []
          _ -> stats_for_series("cpu_usage_pct", usage_series)
        end,
      "charts" =>
        [
          chart(
            "CPU usage",
            "time_s",
            "pct",
            if(usage_series == [],
              do: [],
              else: [%{"name" => "cpu_usage_pct", "points" => usage_series}]
            )
          )
        ]
        |> Enum.reject(&is_nil/1)
    }
  end

  defp cpu_usage_series(rows) do
    rows
    |> Enum.map(fn row ->
      values =
        Map.new(@cpu_columns, fn key ->
          {key, parse_float(Map.get(row, key))}
        end)

      {parse_float(Map.get(row, "time[ms]")), values}
    end)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [{_t1, v1}, {t2, v2}] ->
      total1 = sum_cpu(v1)
      total2 = sum_cpu(v2)
      idle1 = (v1["idle"] || 0.0) + (v1["iowait"] || 0.0)
      idle2 = (v2["idle"] || 0.0) + (v2["iowait"] || 0.0)

      total_delta = total2 - total1
      idle_delta = idle2 - idle1

      usage =
        if total_delta <= 0 do
          nil
        else
          100.0 * (1.0 - idle_delta / total_delta)
        end

      {t2, usage}
    end)
    |> normalize_time_series()
  end

  defp sum_cpu(values) do
    @cpu_columns
    |> Enum.reduce(0.0, fn key, acc ->
      acc + (values[key] || 0.0)
    end)
  end

  defp normalize_time_series(points) do
    case points do
      [] ->
        []

      _ ->
        base_time = points |> List.first() |> elem(0)

        points
        |> Enum.map(fn {t, y} ->
          if is_nil(t) or is_nil(y) do
            nil
          else
            %{"x" => (t - base_time) / 1000.0, "y" => y}
          end
        end)
        |> Enum.reject(&is_nil/1)
    end
  end

  defp series_from_rows(rows, x_key, y_key, x_mode \\ :raw) do
    points =
      rows
      |> Enum.map(fn row ->
        {parse_float(Map.get(row, x_key)), parse_float(Map.get(row, y_key))}
      end)

    points =
      case x_mode do
        :raw ->
          points

        :seconds_from_start ->
          normalize_x_seconds(points)
      end

    points =
      points
      |> Enum.reject(fn {x, y} -> is_nil(x) or is_nil(y) end)
      |> Enum.map(fn {x, y} -> %{"x" => x, "y" => y} end)

    if points == [] do
      nil
    else
      %{"name" => y_key, "points" => points}
    end
  end

  defp normalize_x_seconds(points) do
    case Enum.find(points, fn {x, _} -> not is_nil(x) end) do
      nil ->
        points

      {base, _} ->
        Enum.map(points, fn {x, y} ->
          if is_nil(x), do: {x, y}, else: {(x - base) / 1000.0, y}
        end)
    end
  end

  defp chart(_title, _x_label, _y_label, []), do: nil

  defp chart(title, x_label, y_label, series) do
    %{
      "title" => title,
      "x_label" => x_label,
      "y_label" => y_label,
      "series" => series
    }
  end

  defp numeric_stats(rows, keys) do
    keys
    |> Enum.uniq()
    |> Enum.map(fn key ->
      values =
        rows
        |> Enum.map(&(Map.get(&1, key) |> parse_float()))
        |> Enum.reject(&is_nil/1)

      if values == [] do
        nil
      else
        stats_for_values(key, values)
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp stats_for_series(name, points) do
    values = points |> Enum.map(& &1["y"])
    [stats_for_values(name, values)]
  end

  defp stats_for_values(key, values) do
    sorted = Enum.sort(values)
    count = length(sorted)
    mean = Enum.sum(sorted) / count
    median = median(sorted)
    min = List.first(sorted)
    max = List.last(sorted)

    variance =
      sorted
      |> Enum.reduce(0.0, fn v, acc ->
        acc + :math.pow(v - mean, 2)
      end)
      |> Kernel./(count)

    stddev = :math.sqrt(variance)

    %{
      "name" => key,
      "count" => count,
      "mean" => round3(mean),
      "median" => round3(median),
      "min" => round3(min),
      "max" => round3(max),
      "stddev" => round3(stddev)
    }
  end

  defp median(sorted) do
    size = length(sorted)
    mid = div(size, 2)

    if rem(size, 2) == 0 do
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    else
      Enum.at(sorted, mid)
    end
  end

  defp round3(value), do: Float.round(value, 3)

  defp has_numeric_value?(rows, key) do
    Enum.any?(rows, fn row ->
      case parse_float(Map.get(row, key)) do
        nil -> false
        _ -> true
      end
    end)
  end

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {num, ""} -> num
      _ -> nil
    end
  end

  defp parse_float(value) when is_number(value), do: value * 1.0
  defp parse_float(_value), do: nil

  defp render_html(data) do
    encoded = data |> :json.format() |> IO.iodata_to_binary()

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Giocci Bench Visualization</title>
        <style>
          :root {
            --bg: #f4f7fb;
            --card: #ffffff;
            --ink: #1f2a44;
            --muted: #5f6b85;
            --line: #d6deed;
          }

          * { box-sizing: border-box; }

          body {
            margin: 0;
            font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            background:
              radial-gradient(circle at top right, #d3f3ee 0, transparent 32%),
              radial-gradient(circle at top left, #d9e8ff 0, transparent 38%),
              var(--bg);
            color: var(--ink);
          }

          main { max-width: 1200px; margin: 0 auto; padding: 24px 16px 56px; }
          header { margin-bottom: 18px; }
          h1 { margin: 0; font-size: 28px; letter-spacing: 0.02em; }
          .report-title { margin-top: 8px; color: var(--muted); font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; }
          .meta { margin-top: 10px; color: var(--muted); font-size: 14px; }
          .mfargs { margin-top: 10px; background: #f8fbff; border: 1px solid var(--line); border-radius: 8px; padding: 10px; font-size: 12px; color: #334155; }
          .mfargs-title { font-weight: 600; margin-bottom: 6px; }
          .mfargs-row { margin-top: 4px; word-break: break-word; }

          section {
            background: var(--card);
            border: 1px solid var(--line);
            border-radius: 12px;
            box-shadow: 0 10px 30px rgba(13, 32, 64, 0.08);
            margin: 16px 0;
            padding: 14px;
          }

          h2 { margin: 0 0 12px; font-size: 18px; }

          .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
            gap: 14px;
          }

          .chart { border: 1px solid var(--line); border-radius: 10px; padding: 10px; }
          .chart h3 { margin: 0 0 4px; font-size: 14px; }
          .chart-subtitle { margin: 0 0 8px; color: var(--muted); font-size: 12px; }
          .chart-tools { margin-top: 8px; font-size: 12px; }
          .chart-tools a { color: #0f4c81; text-decoration: none; }
          .chart-tools a:hover { text-decoration: underline; }

          canvas {
            width: 100%;
            height: 260px;
            display: block;
            border-radius: 8px;
            background: linear-gradient(#ffffff, #f9fbff);
          }

          table { width: 100%; border-collapse: collapse; margin-top: 10px; font-size: 13px; }
          th, td { border-bottom: 1px solid #eef2fb; padding: 7px; text-align: right; }
          th:first-child, td:first-child { text-align: left; }

          .legend { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 8px; font-size: 12px; color: var(--muted); }
          .legend-item { display: flex; align-items: center; gap: 6px; }
          .legend-swatch { width: 12px; height: 12px; border-radius: 3px; }
        </style>
      </head>
      <body>
        <main id="app"></main>
        <script>
          const DATA = #{encoded};
          const COLORS = ["#0f766e", "#2563eb", "#d97706", "#dc2626", "#7c3aed", "#0891b2", "#65a30d", "#be185d", "#ca8a04", "#1d4ed8"];

          function el(tag, attrs, children) {
            const node = document.createElement(tag);
            const a = attrs || {};
            const c = children || [];
            Object.entries(a).forEach(function(entry) { node.setAttribute(entry[0], entry[1]); });
            ([]).concat(c).forEach(function(child) {
              if (typeof child === 'string') {
                node.appendChild(document.createTextNode(child));
              } else if (child) {
                node.appendChild(child);
              }
            });
            return node;
          }

          function format(v) {
            if (typeof v !== 'number') return String(v);
            return v.toFixed(3);
          }

          function formatAxisValue(v, axisLabel) {
            if (axisLabel === 'iteration') {
              return String(Math.round(v));
            }
            return format(v);
          }

          function drawChart(canvas, chart) {
            const ctx = canvas.getContext('2d');
            const rect = canvas.getBoundingClientRect();
            const width = Math.max(Math.floor(rect.width || canvas.clientWidth || (canvas.parentElement && canvas.parentElement.clientWidth) || 640), 320);
            const height = Math.max(Math.floor(rect.height || canvas.clientHeight || 260), 180);

            canvas.width = width * window.devicePixelRatio;
            canvas.height = height * window.devicePixelRatio;
            ctx.scale(window.devicePixelRatio, window.devicePixelRatio);

            const margin = { top: 12, right: 16, bottom: 30, left: 44 };
            const plotW = width - margin.left - margin.right;
            const plotH = height - margin.top - margin.bottom;

            const points = chart.series.reduce(function(acc, s) { return acc.concat(s.points); }, []);
            if (points.length === 0) {
              ctx.fillStyle = '#6b7280';
              ctx.fillText('No data', 16, 26);
              return;
            }

            let xMin = Math.min.apply(null, points.map(function(p) { return p.x; }));
            let xMax = Math.max.apply(null, points.map(function(p) { return p.x; }));
            let yMin = Math.min.apply(null, points.map(function(p) { return p.y; }));
            let yMax = Math.max.apply(null, points.map(function(p) { return p.y; }));

            if (xMin === xMax) xMax = xMin + 1;
            if (yMin === yMax) yMax = yMin + 1;

            function xScale(x) { return margin.left + ((x - xMin) / (xMax - xMin)) * plotW; }
            function yScale(y) { return margin.top + (1 - (y - yMin) / (yMax - yMin)) * plotH; }

            ctx.strokeStyle = '#d7e2f3';
            ctx.lineWidth = 1;
            for (let i = 0; i <= 4; i++) {
              const y = margin.top + (plotH * i) / 4;
              ctx.beginPath();
              ctx.moveTo(margin.left, y);
              ctx.lineTo(width - margin.right, y);
              ctx.stroke();
            }

            ctx.strokeStyle = '#94a3b8';
            ctx.beginPath();
            ctx.moveTo(margin.left, margin.top);
            ctx.lineTo(margin.left, height - margin.bottom);
            ctx.lineTo(width - margin.right, height - margin.bottom);
            ctx.stroke();

            ctx.fillStyle = '#475569';
            ctx.font = '11px ui-sans-serif, system-ui';
            for (let i = 0; i <= 4; i++) {
              const yTick = yMin + ((yMax - yMin) * (4 - i)) / 4;
              const yPos = margin.top + (plotH * i) / 4;
              ctx.fillText(format(yTick), 4, yPos + 4);

              const xTick = xMin + ((xMax - xMin) * i) / 4;
              const xPos = margin.left + (plotW * i) / 4;
              ctx.fillText(formatAxisValue(xTick, chart.x_label), xPos - 12, height - margin.bottom + 16);
            }

            chart.series.forEach(function(series, idx) {
              const color = COLORS[idx % COLORS.length];
              ctx.strokeStyle = color;
              ctx.fillStyle = color;
              ctx.lineWidth = 2;

              ctx.beginPath();
              series.points.forEach(function(p, i) {
                const x = xScale(p.x);
                const y = yScale(p.y);
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
              });
              ctx.stroke();

              series.points.forEach(function(p) {
                const x = xScale(p.x);
                const y = yScale(p.y);
                ctx.beginPath();
                ctx.arc(x, y, 2.4, 0, Math.PI * 2);
                ctx.fill();
              });
            });

            ctx.fillStyle = '#475569';
            ctx.font = '12px ui-sans-serif, system-ui';
            ctx.fillText(chart.x_label, margin.left + plotW / 2 - 20, height - 6);
            ctx.fillText(chart.y_label, margin.left, margin.top - 2);
          }

          function render() {
            const app = document.getElementById('app');
            const pendingCharts = [];

            const mfargRows = Object.entries(DATA.mfargs || {}).map(function(entry) {
              return el('div', { class: 'mfargs-row' }, entry[0] + ': ' + entry[1]);
            });

            const mfargBlock = mfargRows.length > 0
              ? el('div', { class: 'mfargs' }, [el('div', { class: 'mfargs-title' }, 'MFArgs')].concat(mfargRows))
              : null;

            const header = el('header', {}, [
              el('h1', {}, DATA.session_title || DATA.title),
              DATA.session_title ? el('div', { class: 'report-title' }, DATA.title) : null,
              el('div', { class: 'meta' }, 'session: ' + DATA.session_dir + ' | generated_at: ' + DATA.generated_at),
              mfargBlock
            ]);
            app.appendChild(header);

            DATA.sections.forEach(function(sectionData) {
              const section = el('section');
              section.appendChild(el('h2', {}, sectionData.title));

              const chartGrid = el('div', { class: 'grid' });
              sectionData.charts.forEach(function(chartData) {
                const card = el('div', { class: 'chart' });
                card.appendChild(el('h3', {}, chartData.title));
                card.appendChild(el('div', { class: 'chart-subtitle' }, sectionData.title));
                const canvas = el('canvas');
                card.appendChild(canvas);
                pendingCharts.push({ canvas: canvas, chartData: chartData });

                const legend = el('div', { class: 'legend' });
                chartData.series.forEach(function(s, idx) {
                  legend.appendChild(
                    el('div', { class: 'legend-item' }, [
                      el('span', { class: 'legend-swatch', style: 'background:' + COLORS[idx % COLORS.length] }),
                      s.name
                    ])
                  );
                });

                card.appendChild(legend);

                if (chartData.csv_file) {
                  card.appendChild(
                    el('div', { class: 'chart-tools' },
                      el('a', { href: chartData.csv_file, download: '' }, 'Download CSV')
                    )
                  );
                }

                if (chartData.svg_file) {
                  card.appendChild(
                    el('div', { class: 'chart-tools' },
                      el('a', { href: chartData.svg_file, download: '' }, 'Download SVG')
                    )
                  );
                }

                chartGrid.appendChild(card);
              });

              section.appendChild(chartGrid);

              if (sectionData.stats.length > 0) {
                const table = el('table');
                table.appendChild(
                  el('thead', {},
                    el('tr', {}, ['name', 'count', 'mean', 'median', 'min', 'max', 'stddev'].map(function(h) { return el('th', {}, h); }))
                  )
                );

                const tbody = el('tbody');
                sectionData.stats.forEach(function(row) {
                  tbody.appendChild(
                    el('tr', {}, [
                      el('td', {}, row.name),
                      el('td', {}, String(row.count)),
                      el('td', {}, format(row.mean)),
                      el('td', {}, format(row.median)),
                      el('td', {}, format(row.min)),
                      el('td', {}, format(row.max)),
                      el('td', {}, format(row.stddev))
                    ])
                  );
                });

                table.appendChild(tbody);
                section.appendChild(table);
              }

              app.appendChild(section);
            });

            window.requestAnimationFrame(function() {
              pendingCharts.forEach(function(item) {
                drawChart(item.canvas, item.chartData);
              });
            });
          }

          render();
          addEventListener('resize', function() {
            document.getElementById('app').innerHTML = '';
            render();
          });
        </script>
      </body>
    </html>
    """
  end
end
