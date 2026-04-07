defmodule GiocciBench.VisualizeCompare do
  @moduledoc false

  alias GiocciBench.Output
  alias NimbleCSV.RFC4180, as: CSV

  @comparable_columns ["elapsed_ms", "function_elapsed_ms"]
  @cpu_columns ["user", "nice", "system", "idle", "iowait", "irq", "softirq", "steal"]
  @single_runtime_files ["register_client.csv", "save_module.csv", "exec_func.csv"]
  @single_runtime_columns [
    "elapsed_ms",
    "function_elapsed_ms",
    "client_to_relay",
    "relay_to_client",
    "relay_to_engine",
    "engine_to_relay",
    "client_to_engine",
    "engine_to_client"
  ]
  @single_runtime_order ["register_client", "save_module", "exec_func"]

  def generate_report(session_dirs, output_path) when is_list(session_dirs) do
    with :ok <- validate_session_count(session_dirs),
         {:ok, sessions} <- load_sessions(session_dirs),
         :ok <- validate_same_mode(sessions),
         :ok <- validate_os_info_presence(sessions) do
      report_data =
        sessions
        |> build_report_data(output_path)
        |> export_chart_files(output_path)

      html = render_html(report_data)
      File.mkdir_p!(Path.dirname(output_path))
      File.write!(output_path, html)

      {:ok, output_path}
    end
  end

  def default_output_path(out_dir) do
    run_id = DateTime.utc_now() |> Calendar.strftime("%Y%m%d-%H%M%S")
    Path.join([out_dir, "comparison_#{run_id}", "report.html"])
  end

  defp validate_session_count(session_dirs) do
    if length(session_dirs) >= 2, do: :ok, else: {:error, :too_few_sessions}
  end

  defp load_sessions(session_dirs) do
    sessions =
      session_dirs
      |> Enum.with_index()
      |> Enum.map(fn {dir, index} ->
        with :ok <- ensure_dir_exists(dir),
             {:ok, mode} <- detect_session_mode(dir),
             {:ok, data_files} <- load_session_data_files(dir),
             metadata <- read_session_metadata(dir) do
          {:ok,
           %{
             dir: dir,
             name: Path.basename(dir),
             mode: mode,
             label: session_label(metadata, index),
             data_files: data_files
           }}
        end
      end)

    collect_results(sessions)
  end

  defp ensure_dir_exists(dir) do
    if File.dir?(dir), do: :ok, else: {:error, {:session_not_found, dir}}
  end

  defp detect_session_mode(session_dir) do
    files =
      session_dir
      |> Path.join("*.csv")
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)
      |> MapSet.new()

    cond do
      MapSet.member?(files, "register_client.csv") or MapSet.member?(files, "save_module.csv") or
          MapSet.member?(files, "exec_func.csv") ->
        {:ok, :single}

      MapSet.member?(files, "sequence.csv") ->
        {:ok, :sequence}

      MapSet.member?(files, "local_exec.csv") ->
        {:ok, :local}

      true ->
        {:error, {:unknown_session_type, session_dir}}
    end
  end

  defp load_session_data_files(session_dir) do
    csv_paths =
      session_dir
      |> Path.join("*.csv")
      |> Path.wildcard()
      |> Enum.reject(fn path ->
        file = Path.basename(path)
        file == "ping.csv"
      end)
      |> Enum.sort()

    if csv_paths == [] do
      {:error, {:no_comparable_csv, session_dir}}
    else
      data_files =
        csv_paths
        |> Enum.map(fn path ->
          file = Path.basename(path)

          with {:ok, table} <- parse_csv(path) do
            metrics = build_metrics(file, table.rows)

            {:ok, {file, metrics}}
          end
        end)

      with {:ok, pairs} <- collect_results(data_files) do
        {:ok, Map.new(pairs)}
      end
    end
  end

  defp parse_csv(path) do
    case File.read(path) do
      {:ok, content} ->
        rows = CSV.parse_string(content, skip_headers: false)

        case rows do
          [] ->
            {:error, {:empty_csv, path}}

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

            {:ok, %{rows: records}}
        end

      {:error, reason} ->
        {:error, {:csv_read_failed, path, reason}}
    end
  end

  defp validate_same_mode(sessions) do
    modes = sessions |> Enum.map(& &1.mode) |> Enum.uniq()

    if length(modes) == 1 do
      :ok
    else
      {:error, {:mixed_session_types, modes}}
    end
  end

  defp validate_os_info_presence(sessions) do
    os_file_sets =
      sessions
      |> Enum.map(fn session ->
        files =
          session.data_files
          |> Map.keys()
          |> Enum.filter(&os_info_file?/1)
          |> MapSet.new()

        {session, files}
      end)

    expected_os_files =
      os_file_sets
      |> Enum.reduce(MapSet.new(), fn {_session, files}, acc -> MapSet.union(acc, files) end)

    if MapSet.size(expected_os_files) == 0 do
      {:error, {:missing_os_info_data, Enum.map(sessions, &{&1.name, []})}}
    else
      missing =
        os_file_sets
        |> Enum.flat_map(fn {session, files} ->
          missing_files =
            expected_os_files
            |> MapSet.difference(files)
            |> MapSet.to_list()
            |> Enum.sort()

          if missing_files == [] do
            []
          else
            [{session.name, missing_files}]
          end
        end)

      if missing == [] do
        :ok
      else
        {:error, {:missing_os_info_data, missing}}
      end
    end
  end

  defp build_metrics(file, rows) do
    if String.ends_with?(file, "_os_info_proc_stat.csv") do
      values = cpu_usage_values(rows)
      if values == [], do: %{}, else: %{"cpu_usage_pct" => values}
    else
      metric_columns(file, rows)
      |> Enum.flat_map(fn column ->
        values =
          rows
          |> Enum.map(&(Map.get(&1, column) |> parse_float()))
          |> Enum.reject(&is_nil/1)

        if values == [] do
          []
        else
          [{column, values}]
        end
      end)
      |> Map.new()
    end
  end

  defp cpu_usage_values(rows) do
    rows
    |> Enum.map(fn row ->
      values =
        Map.new(@cpu_columns, fn key ->
          {key, parse_float(Map.get(row, key))}
        end)

      {parse_float(Map.get(row, "time[ms]")), values}
    end)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [{_t1, v1}, {_t2, v2}] ->
      total1 = sum_cpu(v1)
      total2 = sum_cpu(v2)
      idle1 = (v1["idle"] || 0.0) + (v1["iowait"] || 0.0)
      idle2 = (v2["idle"] || 0.0) + (v2["iowait"] || 0.0)

      total_delta = total2 - total1
      idle_delta = idle2 - idle1

      if total_delta <= 0 do
        nil
      else
        100.0 * (1.0 - idle_delta / total_delta)
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp sum_cpu(values) do
    @cpu_columns
    |> Enum.reduce(0.0, fn key, acc ->
      acc + (values[key] || 0.0)
    end)
  end

  defp metric_columns(file, rows) do
    sample = List.first(rows) || %{}
    columns = Map.keys(sample)

    cond do
      String.ends_with?(file, "_os_info_free.csv") ->
        columns
        |> Enum.reject(&(&1 == "time[ms]"))

      String.ends_with?(file, "_os_info_proc_stat.csv") ->
        columns
        |> Enum.reject(&(&1 == "time[ms]"))

      file in @single_runtime_files ->
        @single_runtime_columns |> Enum.filter(&(&1 in columns))

      true ->
        @comparable_columns
    end
  end

  defp os_info_file?(file) do
    String.ends_with?(file, "_os_info_free.csv") or
      String.ends_with?(file, "_os_info_proc_stat.csv")
  end

  defp build_report_data(sessions, _output_path) do
    first = hd(sessions)

    charts = build_charts(sessions)

    %{
      "title" => "Giocci Bench Comparison",
      "mode" => Atom.to_string(first.mode),
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "session_names" => Enum.map(sessions, & &1.name),
      "chart_count" => length(charts),
      "charts" => charts
    }
  end

  defp build_charts(sessions) do
    files =
      sessions
      |> Enum.flat_map(fn session -> Map.keys(session.data_files) end)
      |> Enum.uniq()
      |> Enum.sort_by(fn file -> {row_order(file_row_kind(file)), sub_row_order(file), file} end)

    for file <- files,
        metric <- metric_candidates(sessions, file),
        boxes = build_boxes(sessions, file, metric),
        boxes != [] do
      row_kind = file_row_kind(file)

      %{
        "id" => "#{file}__#{metric}",
        "title" => metric,
        "subtitle" => file,
        "row_kind" => row_kind,
        "row_title" => row_title(row_kind),
        "sub_row_key" => sub_row_key(file),
        "y_label" => metric_y_label(file, metric),
        "boxes" => boxes
      }
    end
  end

  defp metric_candidates(sessions, file) do
    available_metrics =
      sessions
      |> Enum.flat_map(fn session ->
        get_in(session, [:data_files, file])
        |> case do
          map when is_map(map) -> Map.keys(map)
          _ -> []
        end
      end)
      |> Enum.uniq()

    cond do
      file in @single_runtime_files ->
        Enum.filter(@single_runtime_columns, &(&1 in available_metrics))

      file_row_kind(file) == "runtime" ->
        Enum.filter(@comparable_columns, &(&1 in available_metrics))

      true ->
        Enum.sort(available_metrics)
    end
  end

  defp file_row_kind(file) do
    cond do
      String.ends_with?(file, "_os_info_proc_stat.csv") -> "cpu"
      String.ends_with?(file, "_os_info_free.csv") -> "memory"
      true -> "runtime"
    end
  end

  defp row_order("runtime"), do: 0
  defp row_order("cpu"), do: 1
  defp row_order("memory"), do: 2
  defp row_order(_), do: 9

  defp row_title("runtime"), do: "Execution Time"
  defp row_title("cpu"), do: "CPU Usage"
  defp row_title("memory"), do: "Memory"
  defp row_title(_), do: "Other"

  defp sub_row_key(file) do
    if file in @single_runtime_files do
      Path.basename(file, ".csv")
    else
      nil
    end
  end

  defp sub_row_order(file) do
    case Enum.find_index(@single_runtime_order, fn stem -> "#{stem}.csv" == file end) do
      nil -> 99
      index -> index
    end
  end

  defp metric_y_label(file, metric) do
    cond do
      String.ends_with?(file, "_os_info_free.csv") ->
        extract_unit(metric) || "value"

      String.ends_with?(file, "_os_info_proc_stat.csv") ->
        "pct"

      true ->
        "ms"
    end
  end

  defp extract_unit(metric) do
    case Regex.run(~r/\[([^\]]+)\]/, metric, capture: :all_but_first) do
      [unit] -> unit
      _ -> nil
    end
  end

  defp build_boxes(sessions, file, metric) do
    sessions
    |> Enum.flat_map(fn session ->
      values = get_in(session, [:data_files, file, metric]) || []

      if values == [] do
        []
      else
        [box_stats(session.label, values)]
      end
    end)
  end

  defp box_stats(label, values) do
    sorted = Enum.sort(values)

    %{
      "label" => label,
      "count" => length(sorted),
      "min" => round3(List.first(sorted)),
      "q1" => round3(percentile(sorted, 0.25)),
      "median" => round3(percentile(sorted, 0.5)),
      "q3" => round3(percentile(sorted, 0.75)),
      "max" => round3(List.last(sorted))
    }
  end

  defp percentile(sorted, p) do
    last_index = length(sorted) - 1

    if last_index <= 0 do
      hd(sorted)
    else
      pos = p * last_index
      low = floor(pos)
      high = ceil(pos)

      if low == high do
        Enum.at(sorted, low)
      else
        low_v = Enum.at(sorted, low)
        high_v = Enum.at(sorted, high)
        low_v + (high_v - low_v) * (pos - low)
      end
    end
  end

  defp export_chart_files(report_data, output_path) do
    report_dir = Path.join(Path.dirname(output_path), "report")
    File.mkdir_p!(report_dir)

    charts =
      report_data
      |> Map.get("charts", [])
      |> Enum.with_index(1)
      |> Enum.map(fn {chart, index} ->
        base = "#{index}_#{sanitize_slug(chart["id"])}"
        csv_name = "#{base}.csv"
        svg_name = "#{base}.svg"
        csv_path = Path.join(report_dir, csv_name)
        svg_path = Path.join(report_dir, svg_name)

        write_boxplot_csv!(csv_path, chart)
        write_boxplot_svg!(svg_path, chart)

        chart
        |> Map.put("csv_file", Path.join("report", csv_name))
        |> Map.put("svg_file", Path.join("report", svg_name))
      end)

    Map.put(report_data, "charts", charts)
  end

  defp write_boxplot_csv!(path, chart) do
    header = ["label", "count", "min", "q1", "median", "q3", "max"]

    rows =
      chart
      |> Map.get("boxes", [])
      |> Enum.map(fn box ->
        [
          box["label"],
          box["count"],
          box["min"],
          box["q1"],
          box["median"],
          box["q3"],
          box["max"]
        ]
      end)

    Output.write_csv!(path, header, rows)
  end

  defp write_boxplot_svg!(path, chart) do
    width = 900
    height = 380
    margin_left = 64
    margin_right = 24
    margin_top = 24
    margin_bottom = 58
    plot_w = width - margin_left - margin_right
    plot_h = height - margin_top - margin_bottom

    boxes = Map.get(chart, "boxes", [])

    {y_min, y_max} =
      case boxes do
        [] ->
          {0.0, 1.0}

        _ ->
          mins = Enum.map(boxes, & &1["min"])
          maxs = Enum.map(boxes, & &1["max"])
          {Enum.min(mins), Enum.max(maxs)}
      end

    y_max = if y_min == y_max, do: y_max + 1.0, else: y_max

    y_scale = fn value -> margin_top + (1.0 - (value - y_min) / (y_max - y_min)) * plot_h end

    step = if boxes == [], do: plot_w, else: plot_w / length(boxes)

    box_svg =
      boxes
      |> Enum.with_index()
      |> Enum.map(fn {box, idx} ->
        center_x = margin_left + step * idx + step / 2
        box_w = min(42.0, step * 0.5)

        y_min_px = y_scale.(box["min"])
        y_q1_px = y_scale.(box["q1"])
        y_med_px = y_scale.(box["median"])
        y_q3_px = y_scale.(box["q3"])
        y_max_px = y_scale.(box["max"])

        """
        <line x1=\"#{center_x}\" y1=\"#{y_max_px}\" x2=\"#{center_x}\" y2=\"#{y_q3_px}\" stroke=\"#0f4c81\" />
        <line x1=\"#{center_x}\" y1=\"#{y_q1_px}\" x2=\"#{center_x}\" y2=\"#{y_min_px}\" stroke=\"#0f4c81\" />
        <line x1=\"#{center_x - box_w / 2}\" y1=\"#{y_max_px}\" x2=\"#{center_x + box_w / 2}\" y2=\"#{y_max_px}\" stroke=\"#0f4c81\" />
        <line x1=\"#{center_x - box_w / 2}\" y1=\"#{y_min_px}\" x2=\"#{center_x + box_w / 2}\" y2=\"#{y_min_px}\" stroke=\"#0f4c81\" />
        <rect x=\"#{center_x - box_w / 2}\" y=\"#{y_q3_px}\" width=\"#{box_w}\" height=\"#{max(y_q1_px - y_q3_px, 1.0)}\" fill=\"#dbeafe\" stroke=\"#0f4c81\" />
        <line x1=\"#{center_x - box_w / 2}\" y1=\"#{y_med_px}\" x2=\"#{center_x + box_w / 2}\" y2=\"#{y_med_px}\" stroke=\"#dc2626\" />
        <text x=\"#{center_x - 16}\" y=\"#{height - margin_bottom + 16}\" font-size=\"11\" fill=\"#475569\">#{xml_escape(box["label"])}</text>
        """
      end)
      |> Enum.join("\n")

    ticks =
      0..4
      |> Enum.map(fn i ->
        value = y_min + (y_max - y_min) * (4 - i) / 4
        y = margin_top + plot_h * i / 4

        """
        <line x1=\"#{margin_left}\" y1=\"#{y}\" x2=\"#{width - margin_right}\" y2=\"#{y}\" stroke=\"#e2e8f0\" />
        <text x=\"8\" y=\"#{y + 4}\" font-size=\"11\" fill=\"#475569\">#{format_float(value)}</text>
        """
      end)
      |> Enum.join("\n")

    svg =
      """
      <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"#{width}\" height=\"#{height}\" viewBox=\"0 0 #{width} #{height}\">
        <rect x=\"0\" y=\"0\" width=\"#{width}\" height=\"#{height}\" fill=\"#ffffff\" />
        #{ticks}
        <line x1=\"#{margin_left}\" y1=\"#{margin_top}\" x2=\"#{margin_left}\" y2=\"#{height - margin_bottom}\" stroke=\"#94a3b8\" />
        <line x1=\"#{margin_left}\" y1=\"#{height - margin_bottom}\" x2=\"#{width - margin_right}\" y2=\"#{height - margin_bottom}\" stroke=\"#94a3b8\" />
        #{box_svg}
        <text x=\"#{margin_left}\" y=\"14\" font-size=\"12\" fill=\"#475569\">#{xml_escape(chart["y_label"] || "value")}</text>
      </svg>
      """

    File.write!(path, svg)
  end

  defp render_html(data) do
    encoded = data |> :json.format() |> IO.iodata_to_binary()

    """
    <!doctype html>
    <html lang=\"en\">
      <head>
        <meta charset=\"utf-8\" />
        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
        <title>Giocci Bench Comparison</title>
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
            font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif;
            background:
              radial-gradient(circle at top right, #d3f3ee 0, transparent 32%),
              radial-gradient(circle at top left, #d9e8ff 0, transparent 38%),
              var(--bg);
            color: var(--ink);
          }

          main { max-width: 1180px; margin: 0 auto; padding: 24px 16px 56px; }
          h1 { margin: 0; font-size: 28px; letter-spacing: 0.02em; }
          .meta { margin-top: 10px; color: var(--muted); font-size: 14px; }

          .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(360px, 1fr));
            gap: 14px;
            margin-top: 18px;
          }

          .row-block { margin-top: 20px; }
          .row-title {
            margin: 0 0 10px;
            font-size: 15px;
            color: var(--muted);
            letter-spacing: 0.02em;
            text-transform: uppercase;
          }

          .sub-row-title {
            margin: 14px 0 6px;
            font-size: 13px;
            color: var(--ink);
            font-weight: 600;
          }

          .card {
            background: var(--card);
            border: 1px solid var(--line);
            border-radius: 12px;
            box-shadow: 0 10px 30px rgba(13, 32, 64, 0.08);
            padding: 12px;
          }

          .card h2 { margin: 0; font-size: 16px; }
          .subtitle { margin-top: 4px; font-size: 12px; color: var(--muted); }
          .tools { margin-top: 8px; font-size: 12px; }
          .tools a { color: #0f4c81; text-decoration: none; margin-right: 8px; }
          .tools a:hover { text-decoration: underline; }

          canvas {
            width: 100%;
            height: 260px;
            display: block;
            margin-top: 8px;
            border-radius: 8px;
            background: linear-gradient(#ffffff, #f9fbff);
          }
        </style>
      </head>
      <body>
        <main id=\"app\"></main>
        <script>
          const DATA = #{String.replace(encoded, "</", "<\\/")};

          function el(tag, attrs, children) {
            const node = document.createElement(tag);
            const a = attrs || {};
            const c = children || [];
            Object.entries(a).forEach(function(entry) { node.setAttribute(entry[0], entry[1]); });
            ([]).concat(c).forEach(function(child) {
              if (typeof child === 'string') node.appendChild(document.createTextNode(child));
              else if (child) node.appendChild(child);
            });
            return node;
          }

          function fmt(v) {
            if (typeof v !== 'number') return String(v);
            return v.toFixed(3);
          }

          function drawBoxPlot(canvas, chart) {
            const ctx = canvas.getContext('2d');
            const rect = canvas.getBoundingClientRect();
            const width = Math.max(Math.floor(rect.width || 640), 320);
            const height = Math.max(Math.floor(rect.height || 260), 180);

            canvas.width = width * window.devicePixelRatio;
            canvas.height = height * window.devicePixelRatio;
            ctx.scale(window.devicePixelRatio, window.devicePixelRatio);

            const margin = { top: 12, right: 16, bottom: 34, left: 46 };
            const plotW = width - margin.left - margin.right;
            const plotH = height - margin.top - margin.bottom;

            const boxes = chart.boxes || [];
            if (boxes.length === 0) {
              ctx.fillStyle = '#6b7280';
              ctx.fillText('No data', 16, 26);
              return;
            }

            const yMin = Math.min.apply(null, boxes.map(function(b) { return b.min; }));
            let yMax = Math.max.apply(null, boxes.map(function(b) { return b.max; }));
            if (yMin === yMax) yMax = yMin + 1;

            function yScale(v) { return margin.top + (1 - (v - yMin) / (yMax - yMin)) * plotH; }
            const step = plotW / boxes.length;

            ctx.strokeStyle = '#d7e2f3';
            ctx.lineWidth = 1;
            for (let i = 0; i <= 4; i++) {
              const y = margin.top + (plotH * i) / 4;
              ctx.beginPath();
              ctx.moveTo(margin.left, y);
              ctx.lineTo(width - margin.right, y);
              ctx.stroke();

              const tick = yMin + ((yMax - yMin) * (4 - i)) / 4;
              ctx.fillStyle = '#475569';
              ctx.font = '11px ui-sans-serif, system-ui';
              ctx.fillText(fmt(tick), 4, y + 4);
            }

            ctx.strokeStyle = '#94a3b8';
            ctx.beginPath();
            ctx.moveTo(margin.left, margin.top);
            ctx.lineTo(margin.left, height - margin.bottom);
            ctx.lineTo(width - margin.right, height - margin.bottom);
            ctx.stroke();

            boxes.forEach(function(box, idx) {
              const x = margin.left + step * idx + step / 2;
              const boxW = Math.min(42, step * 0.5);

              const yMinV = yScale(box.min);
              const yQ1 = yScale(box.q1);
              const yMed = yScale(box.median);
              const yQ3 = yScale(box.q3);
              const yMaxV = yScale(box.max);

              ctx.strokeStyle = '#0f4c81';
              ctx.fillStyle = '#dbeafe';

              ctx.beginPath();
              ctx.moveTo(x, yMaxV);
              ctx.lineTo(x, yQ3);
              ctx.moveTo(x, yQ1);
              ctx.lineTo(x, yMinV);
              ctx.stroke();

              ctx.beginPath();
              ctx.moveTo(x - boxW / 2, yMaxV);
              ctx.lineTo(x + boxW / 2, yMaxV);
              ctx.moveTo(x - boxW / 2, yMinV);
              ctx.lineTo(x + boxW / 2, yMinV);
              ctx.stroke();

              ctx.fillRect(x - boxW / 2, yQ3, boxW, Math.max(yQ1 - yQ3, 1));
              ctx.strokeRect(x - boxW / 2, yQ3, boxW, Math.max(yQ1 - yQ3, 1));

              ctx.strokeStyle = '#dc2626';
              ctx.beginPath();
              ctx.moveTo(x - boxW / 2, yMed);
              ctx.lineTo(x + boxW / 2, yMed);
              ctx.stroke();

              ctx.fillStyle = '#475569';
              ctx.font = '11px ui-sans-serif, system-ui';
              ctx.fillText(box.label, x - 12, height - margin.bottom + 16);
            });
          }

          function render() {
            const app = document.getElementById('app');
            const pending = [];

            app.appendChild(el('h1', {}, DATA.title));
            app.appendChild(el('div', { class: 'meta' },
              'mode: ' + DATA.mode + ' | sessions: ' + DATA.session_names.join(', ') + ' | generated_at: ' + DATA.generated_at
            ));

            function makeCard(chart) {
              const card = el('div', { class: 'card' });
              card.appendChild(el('h2', {}, chart.title));
              card.appendChild(el('div', { class: 'subtitle' }, chart.subtitle));
              const canvas = el('canvas');
              card.appendChild(canvas);
              pending.push({ canvas: canvas, chart: chart });
              const tools = el('div', { class: 'tools' });
              if (chart.csv_file) tools.appendChild(el('a', { href: chart.csv_file, download: '' }, 'Download CSV'));
              if (chart.svg_file) tools.appendChild(el('a', { href: chart.svg_file, download: '' }, 'Download SVG'));
              card.appendChild(tools);
              return card;
            }

            const rowKinds = ['runtime', 'cpu', 'memory'];

            rowKinds.forEach(function(kind) {
              const rowCharts = DATA.charts.filter(function(chart) { return chart.row_kind === kind; });
              if (rowCharts.length === 0) return;

              const block = el('section', { class: 'row-block' });
              block.appendChild(el('h2', { class: 'row-title' }, rowCharts[0].row_title || kind));

              if (kind === 'runtime' && DATA.mode === 'single') {
                var subKeys = ['register_client', 'save_module', 'exec_func'];
                subKeys.forEach(function(subKey) {
                  var subCharts = rowCharts.filter(function(c) { return c.sub_row_key === subKey; });
                  if (subCharts.length === 0) return;
                  block.appendChild(el('h3', { class: 'sub-row-title' }, subKey));
                  var grid = el('div', { class: 'grid' });
                  subCharts.forEach(function(chart) { grid.appendChild(makeCard(chart)); });
                  block.appendChild(grid);
                });
              } else {
                const grid = el('div', { class: 'grid' });
                rowCharts.forEach(function(chart) { grid.appendChild(makeCard(chart)); });
                block.appendChild(grid);
              }

              app.appendChild(block);
            });

            window.requestAnimationFrame(function() {
              pending.forEach(function(item) {
                drawBoxPlot(item.canvas, item.chart);
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

  defp session_label(metadata, index) do
    case read_session_title(metadata) do
      nil -> fallback_label(index)
      "" -> fallback_label(index)
      "nil" -> fallback_label(index)
      title -> title
    end
  end

  defp fallback_label(index) do
    number = index + 1

    if number <= 26 do
      <<?A + number - 1>>
    else
      "S#{number}"
    end
  end

  defp read_session_metadata(session_dir) do
    meta_path = Path.join(session_dir, "meta.json")

    with true <- File.exists?(meta_path),
         {:ok, content} <- File.read(meta_path) do
      decode_json_map(content)
    else
      _ -> %{}
    end
  end

  defp decode_json_map(content) do
    try do
      case :json.decode(content) do
        metadata when is_map(metadata) -> normalize_map_keys(metadata)
        _ -> %{}
      end
    rescue
      _ -> %{}
    end
  end

  defp normalize_map_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {normalize_key(key), normalize_value(value)}
    end)
  end

  defp normalize_value(value) when is_map(value), do: normalize_map_keys(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value

  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)

  defp normalize_key(key) when is_list(key) do
    List.to_string(key)
  rescue
    _ -> inspect(key)
  end

  defp normalize_key(key), do: inspect(key)

  defp read_session_title(metadata) when is_map(metadata) do
    case Map.get(metadata, "title") do
      title when is_binary(title) -> String.trim(title)
      _ -> nil
    end
  end

  defp xml_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp format_float(value), do: :erlang.float_to_binary(value * 1.0, decimals: 3)

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

  defp round3(value), do: Float.round(value, 3)

  defp collect_results(results) do
    Enum.reduce_while(results, {:ok, []}, fn result, {:ok, acc} ->
      case result do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end
end
