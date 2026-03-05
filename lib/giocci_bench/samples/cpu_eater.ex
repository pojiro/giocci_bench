defmodule GiocciBench.Samples.CpuEater do
  @moduledoc """
  CPU 負荷テスト用のベンチマークモジュール。

  全CPUコアでスピンループを実行し、CPU使用率を高めます。
  `--os-info` オプションと併用することで、CPU使用率の変化を計測できます。

  ## 動作

  - システムの論理プロセッサ数を取得
  - 各コアごとにプロセスを生成してスピンループを実行
  - LCG（線形合同法）アルゴリズムでCPUを継続的に使用

  """

  @behaviour GiocciBench.Samples.BenchmarkBehaviour

  @spec run(list()) :: {any(), float()}
  @impl true
  def run([]) do
    start_time = System.monotonic_time()
    result = spin_many(cpu_cores(), 1_000)
    end_time = System.monotonic_time()

    elapsed_ms =
      (end_time - start_time)
      |> System.convert_time_unit(:native, :microsecond)
      |> Kernel./(1000)
      |> Float.round(3)

    {result, elapsed_ms}
  end

  defp cpu_cores do
    case :erlang.system_info(:logical_processors_available) do
      :unknown ->
        case :erlang.system_info(:logical_processors_online) do
          :unknown -> nil
          value -> value
        end

      value ->
        value
    end
  end

  import Bitwise

  def spin(ms \\ 10_000), do: do_spin(ms)

  def spin_many(n, ms \\ 10_000) when n > 0 do
    parent = self()

    refs =
      for _ <- 1..n do
        ref = make_ref()

        spawn(fn ->
          _ = do_spin(ms)
          send(parent, {:done, ref})
        end)

        ref
      end

    wait_all(refs)
  end

  defp do_spin(ms) do
    deadline = System.monotonic_time(:millisecond) + ms
    loop(deadline, 0)
  end

  defp loop(deadline, acc) do
    # Linear Congruential Generator (LCG): x_{n+1} = (a * x_n + c) mod m
    # This generates a sequence of pseudo-random numbers to keep the CPU busy.
    # Parameters: a=1_103_515_245, c=12_345 (from glibc)
    # The &&& 0x7FFFFFFF masks to keep the result as a positive 32-bit integer
    acc = acc * 1_103_515_245 + 12_345 &&& 0x7FFFFFFF
    if System.monotonic_time(:millisecond) < deadline, do: loop(deadline, acc), else: acc
  end

  defp wait_all([]), do: :ok

  defp wait_all(refs) do
    receive do
      {:done, ref} -> wait_all(List.delete(refs, ref))
    end
  end
end
