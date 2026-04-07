defmodule GiocciBench.Samples.BigBeam do
  @moduledoc """
  Giocci によるモジュール転送時の通信量を増やすためのベンチマークモジュール。

  モジュール属性として 1MB の大きなバイナリを保持することで、
  BEAMファイル自体のサイズを大きくし、`save_module` の通信負荷をテストします。

  ## 用途

  - Giocci の大きなモジュール転送性能の計測
  - ネットワーク帯域幅の影響を観察
  - 転送時間と実行時間の比較
  """

  @big_binary :binary.copy(<<0>>, 1024 * 1024 * 1)

  @behaviour GiocciBench.Samples.BenchmarkBehaviour

  @spec run(list()) :: {any(), float()}
  @impl true
  def run([]) do
    start_time = System.os_time()
    result = File.write!("/dev/null", @big_binary)
    end_time = System.os_time()

    elapsed_ms =
      (end_time - start_time)
      |> System.convert_time_unit(:native, :microsecond)
      |> Kernel./(1000)
      |> Float.round(3)

    {result, elapsed_ms}
  end
end
