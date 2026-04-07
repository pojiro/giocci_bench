defmodule Mix.Tasks.GiocciBench.Visualize.CompareTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.GiocciBench.Visualize.Compare, as: CompareTask

  setup do
    Mix.shell(Mix.Shell.Process)
    Mix.Task.clear()

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
      Mix.Task.clear()
    end)

    :ok
  end

  @tag :tmp_dir
  test "creates comparison report with title legend and fallback", %{tmp_dir: tmp_dir} do
    out_dir = Path.join(tmp_dir, "giocci_bench_output")
    s1 = Path.join(out_dir, "session_20260407-100000-sequence-nightly")
    s2 = Path.join(out_dir, "session_20260407-100100-sequence")
    File.mkdir_p!(s1)
    File.mkdir_p!(s2)

    csv_header = "run_id,case_id,iteration,elapsed_ms,function_elapsed_ms,warmup,error\n"

    csv1 =
      csv_header <>
        "1,sequence,1,100.0,80.0,1,\n1,sequence,2,120.0,90.0,1,\n1,sequence,3,130.0,95.0,1,\n"

    csv2 =
      csv_header <>
        "2,sequence,1,210.0,170.0,1,\n2,sequence,2,220.0,180.0,1,\n2,sequence,3,240.0,190.0,1,\n"

    File.write!(Path.join(s1, "sequence.csv"), csv1)
    File.write!(Path.join(s2, "sequence.csv"), csv2)

    os_info_free = "time[ms],total[KiB],used[KiB]\n1000,100000,42000\n1100,100010,42100\n"
    os_info_proc = "time[ms],user,system,idle\n1000,10,3,90\n1100,11,4,91\n"

    File.write!(Path.join(s1, "sequence_os_info_free.csv"), os_info_free)
    File.write!(Path.join(s2, "sequence_os_info_free.csv"), os_info_free)
    File.write!(Path.join(s1, "sequence_os_info_proc_stat.csv"), os_info_proc)
    File.write!(Path.join(s2, "sequence_os_info_proc_stat.csv"), os_info_proc)

    File.write!(Path.join(s1, "meta.json"), ~s({"title":"nightly"}))
    File.write!(Path.join(s2, "meta.json"), ~s({"run_id":"x"}))

    output = Path.join(tmp_dir, "comparison/report.html")
    CompareTask.run(["--session-dir", s1, "--session-dir", s2, "--output", output])

    assert File.exists?(output)

    report = File.read!(output)
    assert report =~ "\"label\": \"nightly\""
    assert report =~ "\"label\": \"B\""
    assert report =~ "\"subtitle\": \"sequence.csv\""
    assert report =~ "\"subtitle\": \"sequence_os_info_free.csv\""
    assert report =~ "\"subtitle\": \"sequence_os_info_proc_stat.csv\""
    assert report =~ "\"title\": \"cpu_usage_pct\""
    refute report =~ "\"title\": \"user\""

    assert order_in_text(report, [
             "\"row_kind\": \"runtime\"",
             "\"row_kind\": \"cpu\"",
             "\"row_kind\": \"memory\""
           ])

    exported_csvs = Path.wildcard(Path.join(Path.dirname(output), "report/*.csv"))
    assert exported_csvs != []

    exported_svgs = Path.wildcard(Path.join(Path.dirname(output), "report/*.svg"))
    assert exported_svgs != []

    assert_receive {:mix_shell, :info, [message]}
    assert message =~ "comparison report created:"
  end

  @tag :tmp_dir
  test "expands wildcard in --session-dir", %{tmp_dir: tmp_dir} do
    out_dir = Path.join(tmp_dir, "giocci_bench_output")
    s1 = Path.join(out_dir, "session_20260407-130000-local-a")
    s2 = Path.join(out_dir, "session_20260407-130100-local-b")
    File.mkdir_p!(s1)
    File.mkdir_p!(s2)

    data_csv =
      "run_id,case_id,iteration,elapsed_ms,function_elapsed_ms,warmup\n" <>
        "1,local_exec,1,10.0,8.0,1\n" <>
        "1,local_exec,2,12.0,9.0,1\n"

    os_info_free = "time[ms],total[KiB]\n1000,1000\n1100,1001\n"
    os_info_proc = "time[ms],user,system,idle\n1000,10,3,90\n1100,11,4,91\n"

    File.write!(Path.join(s1, "local_exec.csv"), data_csv)
    File.write!(Path.join(s2, "local_exec.csv"), data_csv)
    File.write!(Path.join(s1, "local_exec_os_info_free.csv"), os_info_free)
    File.write!(Path.join(s2, "local_exec_os_info_free.csv"), os_info_free)
    File.write!(Path.join(s1, "local_exec_os_info_proc_stat.csv"), os_info_proc)
    File.write!(Path.join(s2, "local_exec_os_info_proc_stat.csv"), os_info_proc)

    output = Path.join(tmp_dir, "comparison_glob/report.html")

    CompareTask.run([
      "--session-dir",
      Path.join(out_dir, "session_20260407-130*-local-*"),
      "--output",
      output
    ])

    assert File.exists?(output)
    report = File.read!(output)
    assert report =~ "\"mode\": \"local\""
  end

  @tag :tmp_dir
  test "creates comparison report for single mode with sub-rows and all columns", %{
    tmp_dir: tmp_dir
  } do
    out_dir = Path.join(tmp_dir, "giocci_bench_output")
    s1 = Path.join(out_dir, "session_20260407-150000-single-a")
    s2 = Path.join(out_dir, "session_20260407-150100-single-b")
    File.mkdir_p!(s1)
    File.mkdir_p!(s2)

    csv_header =
      "run_id,case_id,iteration,elapsed_ms,function_elapsed_ms,warmup,client_to_relay,relay_to_client,relay_to_engine,engine_to_relay,client_to_engine,engine_to_client\n"

    register_client_csv =
      csv_header <>
        "1,register_client,1,31.0,,1,14.0,16.0,,,,\n" <>
        "1,register_client,2,28.0,,1,17.0,10.0,,,,\n"

    save_module_csv =
      csv_header <>
        "1,save_module,1,54.0,,1,22.0,23.0,1.1,0.7,,\n" <>
        "1,save_module,2,38.0,,1,22.0,6.0,1.2,1.8,,\n"

    exec_func_csv =
      csv_header <>
        "1,exec_func,1,2294.0,2239.0,1,17.0,7.0,,,22.0,7.0\n" <>
        "1,exec_func,2,2293.0,2210.0,1,17.0,24.0,,,20.0,21.0\n"

    os_info_free = "time[ms],total[KiB],used[KiB]\n1000,100000,42000\n1100,100010,42100\n"
    os_info_proc = "time[ms],user,system,idle\n1000,10,3,90\n1100,11,4,91\n"

    for session <- [s1, s2] do
      File.write!(Path.join(session, "register_client.csv"), register_client_csv)
      File.write!(Path.join(session, "save_module.csv"), save_module_csv)
      File.write!(Path.join(session, "exec_func.csv"), exec_func_csv)

      for stem <- ["register_client", "save_module", "exec_func"] do
        File.write!(Path.join(session, "#{stem}_os_info_free.csv"), os_info_free)
        File.write!(Path.join(session, "#{stem}_os_info_proc_stat.csv"), os_info_proc)
      end
    end

    output = Path.join(tmp_dir, "comparison_single/report.html")
    CompareTask.run(["--session-dir", s1, "--session-dir", s2, "--output", output])

    assert File.exists?(output)
    report = File.read!(output)

    assert report =~ "\"mode\": \"single\""

    # sub-row keys present for all three files
    assert report =~ "\"sub_row_key\": \"register_client\""
    assert report =~ "\"sub_row_key\": \"save_module\""
    assert report =~ "\"sub_row_key\": \"exec_func\""

    # columns beyond elapsed_ms/function_elapsed_ms are present
    assert report =~ "\"title\": \"client_to_relay\""
    assert report =~ "\"title\": \"relay_to_client\""

    # sub-rows appear in order: register_client → save_module → exec_func
    assert order_in_text(report, [
             "\"sub_row_key\": \"register_client\"",
             "\"sub_row_key\": \"save_module\"",
             "\"sub_row_key\": \"exec_func\""
           ])

    assert_receive {:mix_shell, :info, [message]}
    assert message =~ "comparison report created:"
  end

  @tag :tmp_dir
  test "raises when mixed benchmark session types are given", %{tmp_dir: tmp_dir} do
    out_dir = Path.join(tmp_dir, "giocci_bench_output")
    sequence_session = Path.join(out_dir, "session_20260407-110000-sequence")
    local_session = Path.join(out_dir, "session_20260407-110100-local")
    File.mkdir_p!(sequence_session)
    File.mkdir_p!(local_session)

    File.write!(
      Path.join(sequence_session, "sequence.csv"),
      "run_id,case_id,iteration,elapsed_ms\n1,sequence,1,10.0\n"
    )

    File.write!(
      Path.join(local_session, "local_exec.csv"),
      "run_id,case_id,iteration,elapsed_ms\n1,local_exec,1,10.0\n"
    )

    assert_raise Mix.Error, ~r/sessions must be generated by the same Mix task/, fn ->
      CompareTask.run(["--session-dir", sequence_session, "--session-dir", local_session])
    end
  end

  @tag :tmp_dir
  test "raises when any specified session is missing os-info data", %{tmp_dir: tmp_dir} do
    out_dir = Path.join(tmp_dir, "giocci_bench_output")
    s1 = Path.join(out_dir, "session_20260407-120000-local-a")
    s2 = Path.join(out_dir, "session_20260407-120100-local-b")
    File.mkdir_p!(s1)
    File.mkdir_p!(s2)

    data_csv =
      "run_id,case_id,iteration,elapsed_ms,function_elapsed_ms,warmup\n" <>
        "1,local_exec,1,10.0,8.0,1\n"

    File.write!(Path.join(s1, "local_exec.csv"), data_csv)
    File.write!(Path.join(s2, "local_exec.csv"), data_csv)

    File.write!(Path.join(s1, "local_exec_os_info_free.csv"), "time[ms],total[KiB]\n1000,1000\n")

    File.write!(
      Path.join(s1, "local_exec_os_info_proc_stat.csv"),
      "time[ms],user,idle\n1000,10,90\n"
    )

    assert_raise Mix.Error,
                 ~r/all specified sessions must include --os-info measurement data/,
                 fn ->
                   CompareTask.run(["--session-dir", s1, "--session-dir", s2])
                 end
  end

  defp order_in_text(text, patterns) do
    case Enum.reduce_while(patterns, {:ok, -1}, fn pattern, {:ok, last_index} ->
           case :binary.match(text, pattern) do
             {index, _length} when index > last_index ->
               {:cont, {:ok, index}}

             _ ->
               {:halt, {:error, {pattern, last_index}}}
           end
         end) do
      {:ok, _last} -> true
      {:error, _reason} -> false
    end
  end
end
