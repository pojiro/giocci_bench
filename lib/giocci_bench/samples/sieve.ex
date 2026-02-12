defmodule GiocciBench.Samples.Sieve do
  @moduledoc "Sieve of Eratosthenes (CPU-intensive benchmark)"

  # Sieve of Eratosthenes: CPU 負荷のかかった計算処理
  # 指定された上限までの素数をふるいで求める
  def sieve(limit) when is_integer(limit) and limit >= 2 do
    2..limit
    |> Enum.reduce(
      %{},
      fn num, acc ->
        if Map.has_key?(acc, num) do
          acc
        else
          # num が素数なら、num の倍数をすべてマークする
          num * num..limit//num
          |> Enum.reduce(acc, fn multiple, a -> Map.put(a, multiple, true) end)
          |> Map.put(num, false)  # num 自身は素数
        end
      end
    )
    |> Enum.filter(fn {_k, v} -> v == false end)
    |> Enum.count()
  end

  def sieve(limit) when limit < 2, do: 0
end
