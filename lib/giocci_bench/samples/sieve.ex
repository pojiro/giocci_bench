defmodule GiocciBench.Samples.Sieve do
  @moduledoc "Sieve of Eratosthenes (CPU-intensive benchmark)"

  @behaviour GiocciBench.Samples.BenchmarkBehaviour

  # Sieve of Eratosthenes: CPU 負荷のかかった計算処理
  # 指定された上限までの素数をふるいで求める
  defp sieve_impl(limit) when is_integer(limit) and limit >= 2 do
    2..limit
    |> Enum.reduce(
      %{},
      fn num, acc ->
        if Map.has_key?(acc, num) do
          acc
        else
          # num が素数なら、num の倍数をすべてマークする
          (num * num)..limit//num
          |> Enum.reduce(acc, fn multiple, a -> Map.put(a, multiple, true) end)
          # num 自身は素数
          |> Map.put(num, false)
        end
      end
    )
    |> Enum.filter(fn {_k, v} -> v == false end)
    |> Enum.count()
  end

  defp sieve_impl(limit) when limit < 2, do: 0

  @spec run(list()) :: {integer(), float()}
  @impl true
  def run([limit]) do
    start_time = System.monotonic_time()
    result = sieve_impl(limit)

    elapsed_ms =
      System.monotonic_time()
      |> Kernel.-(start_time)
      |> System.convert_time_unit(:native, :microsecond)
      |> Kernel./(1000)
      |> Float.round(3)

    {result, elapsed_ms}
  end
end
