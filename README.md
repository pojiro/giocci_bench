# GiocciBench

giocci の性能計測を行い、処理時間を CSV で出力するためのベンチマークプロジェクトです。

## 計測仕様

### 目的

giocci の処理にかかる時間を再現性のある形で計測し、後続の集計・可視化ができる CSV を出力します。

### 計測対象

- 通信にかかる時間の基準値として、giocci の計測前に ping 応答時間を計測
  - 宛先: localhost / engine / relay
  - TODO: 回数・タイムアウト・失敗時の扱いを決める
  - CSV への記録方法: 別スキーマ
  - RTT が取得できない場合は `success=false`、`elapsed_ms` は空、`error` に詳細を記録
- giocci の主要処理（具体的な入力・処理内容はベンチ実装で定義）
  - TODO: 入力データの固定値・サイズ・seed を定義する
- 処理時間は「呼び出しからリターンを得るまでの実測時間」を計測
- 単体計測
  - `register_client`
  - `save_module`
  - `exec_func`
- 複合計測
  - `register_client` と `save_module` を順に呼び出す時間
  - `register_client` → `save_module` → `exec_func` を順に呼び出す時間

### 計測方法

- 計測単位: ミリ秒 ($ms$)
- タイマ: Elixir 標準の `System.monotonic_time/1` を使用
- 1 つのケースにつき複数回実行し、測定値をすべて記録
- ウォームアップを実施して初回実行の影響を除外
- CPU 使用率とメモリ使用率を計測し、各計測結果に紐付ける
  - システム全体で計測する
  - TODO: 瞬時値か平均値か、サンプリング間隔を決める
  - TODO: `elapsed_ms` の丸め方法 (整数 / 小数) を決める

### 実行条件

- 各ケースにつき `warmup` 回の実行後に `iterations` 回計測
- 各計測は mix task として呼び出せること
- ベンチ実行時点の環境情報を CSV に含める
  - OS, Elixir バージョン, Erlang/OTP バージョン
  - CPU モデル名, コア数, メモリ量

### CSV 出力仕様

- 1 行 1 計測結果
- UTF-8, 改行は LF
- 出力ファイル名は実行時のタイムスタンプを含める

#### カラム

| column | type | description |
| --- | --- | --- |
| run_id | string | 1 回の実行を識別する ID (実行開始時刻の Unix ミリ秒) |
| case_id | string | 計測ケース識別子 |
| case_desc | string | 計測ケースの説明 |
| iteration | integer | 計測回数の通し番号 (1..iterations) |
| elapsed_ms | float | 処理時間 ($ms$, 小数) |
| cpu_usage_pct | float | CPU 使用率 (%) |
| memory_usage_pct | float | メモリ使用率 (%) |
| input_size | integer | 入力サイズ (任意, 無い場合は 0) |
| warmup | boolean | ウォームアップかどうか (TODO: ウォームアップ行も出力するか決める) |
| elixir_version | string | Elixir バージョン |
| otp_version | string | Erlang/OTP バージョン |
| os | string | OS 名 |
| cpu | string | CPU モデル名 |
| cpu_cores | integer | CPU コア数 |
| memory_gb | float | 物理メモリ (GB) |
| started_at | string | 実行開始時刻 (ISO 8601) |

### 集計指標 (CSV 外部)

- 各ケースに対して平均・中央値・標準偏差・分散を算出
- 集計結果は別途レポートや図に反映

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `giocci_bench` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:giocci_bench, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/giocci_bench>.

