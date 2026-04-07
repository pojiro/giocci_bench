defmodule GiocciBench.Samples.MemoryEater do
  @moduledoc """
  メモリ負荷テスト用のベンチマークモジュール。

  実行中に一時的に大量のメモリを確保し、メモリ使用量を増加させます。
  `--os-info` オプションと併用することで、メモリ使用量の変化を計測できます。

  ## 動作

  - 指定されたサイズ（デフォルト: 100 MiB）のメモリをチャンク単位で確保
  - 確保したメモリはリストに保持され、関数終了まで解放されない
  - 外部計測ツールでメモリ使用量の増加を観察可能

  """

  @behaviour GiocciBench.Samples.BenchmarkBehaviour

  @spec run(list()) :: {any(), float()}
  @impl true
  def run([]) do
    start_time = System.os_time()
    result = alloc_memory(100, 10)
    end_time = System.os_time()

    elapsed_ms =
      (end_time - start_time)
      |> System.convert_time_unit(:native, :microsecond)
      |> Kernel./(1000)
      |> Float.round(3)

    {result, elapsed_ms}
  end

  @mib 1024 * 1024

  def alloc_memory(mib \\ 100, chunk_mib \\ 1)
      when is_integer(mib) and mib > 0 and is_integer(chunk_mib) and chunk_mib > 0 do
    target_bytes = mib * @mib
    chunk_bytes = chunk_mib * @mib
    n = div(target_bytes, chunk_bytes)

    _chunks =
      Enum.reduce(1..n, [], fn _i, acc ->
        {_time_us, chunk} = :timer.tc(fn -> :binary.copy(<<0>>, chunk_bytes) end)
        acc = [chunk | acc]
        acc
      end)

    :ok
  end
end
