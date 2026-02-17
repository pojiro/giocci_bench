# GiocciBench

giocci の性能計測を行い、処理時間を CSV で出力するためのベンチマークプロジェクトです。

## 計測仕様

### 目的

giocci の処理にかかる時間を再現性のある形で計測し、後続の集計・可視化ができる CSV を出力します。

### 計測対象

- 通信にかかる時間の基準値として、giocci の計測前に ping 応答時間を計測
  - 宛先: `--ping-targets` オプションで指定（デフォルト: 127.0.0.1）
  - 回数: `--ping-count` オプションで指定（デフォルト: 5回）
  - CSV への記録方法: 別スキーマ
  - RTT が取得できない場合は `success=false`、`elapsed_ms` は空、`error` に詳細を記録
- giocci の主要処理（具体的な入力・処理内容はベンチ実装で定義）
  - TODO: 入力データの固定値・サイズ・seed を定義する
- 処理時間は「呼び出しからリターンを得るまでの実測時間」を計測
- 単体計測
  - `register_client`
  - `save_module`
  - `exec_func` - Giocci 経由でエンジン上で実行
  - `local_exec` - ローカルで直接実行（比較用）
- 複合計測
  - `register_client` と `save_module` を順に呼び出す時間
  - `register_client` → `save_module` → `exec_func` を順に呼び出す時間

### 計測方法

- 計測単位: ミリ秒 ($ms$)
- タイマ: Elixir 標準の `System.monotonic_time/1` を使用
- 1 つのケースにつき複数回実行し、測定値をすべて記録
- ウォームアップを実施して初回実行の影響を除外
- `elapsed_ms`: クライアント側での呼び出しからリターンまでの時間
- `engine_elapsed_ms`: エンジン上での実際の処理時間（`exec_func` と `local_exec` のみ）
  - サンプルモジュールが `GiocciBench.Samples.Benchmark` behaviour を実装し、処理時間を含めて返す
- CPU/メモリ使用率の計測は別ライブラリで実施

### 実行条件

- 各ケースにつき `warmup` 回の実行後に `iterations` 回計測
- 各計測は mix task として呼び出せること
- 単体計測は `mix giocci_bench.single` で実行
- ベンチ実行時点の環境情報はメタデータファイルに記録
  - OS, Elixir バージョン, Erlang/OTP バージョン
  - CPU コア数
- 単体計測実行時に自動で ping 計測も実行（デフォルト）
  - `--no-ping` フラグで無効化可能
  - `--ping-targets` でターゲット指定（カンマ区切り）
  - `--ping-count` で各ターゲットへの ping 回数指定
  - ping 計測は single 計測の前に実行
  - ping 計測結果は同じセッションディレクトリに保存

### 出力ディレクトリ構造

計測セッションごとにディレクトリを作成し、メタデータと計測結果を分離します。

```
giocci_bench_output/
  session_1771220881580/
    meta.json          # 計測セッションのメタデータ
    ping.csv           # ping 計測結果
    single.csv         # 単体計測結果
  session_1771221459080/
    meta.json
    ping.csv
    single.csv
```

- 出力先ディレクトリのデフォルトは `giocci_bench_output`
- `session_<run_id>` ディレクトリ名は実行開始時刻の Unix ミリ秒

### メタデータ仕様 (meta.json)

計測セッション全体の環境情報を JSON で記録します。

```json
{
  "run_id": "1771220881580",
  "started_at": "2026-02-17T10:00:00Z",
  "elixir_version": "1.14.0",
  "otp_version": "24.0",
  "os": "Linux 5.10.0",
  "cpu": "x86_64",
  "cpu_cores": 4
}
```

### CSV 出力仕様

#### 単体計測 (single.csv)

- 1 行 1 計測結果
- UTF-8, 改行は LF
- 環境情報は `meta.json` に記録するため CSV に含めない

##### カラム

| column | type | description |
| --- | --- | --- |
| run_id | string | 計測セッション識別子 (実行開始時刻の Unix ミリ秒) |
| case_id | string | 計測ケース識別子 (`register_client`, `save_module`, `exec_func`, `local_exec`) |
| case_desc | string | 計測ケースの説明 |
| iteration | integer | 計測回数の通し番号 (1..iterations) |
| elapsed_ms | float | クライアント側での処理時間 ($ms$, 小数点以下3桁) |
| engine_elapsed_ms | float | エンジン上での処理時間 ($ms$, 小数点以下3桁、`exec_func`/`local_exec` のみ) |
| warmup | integer | 実行した warmup 回数 |

#### ping 計測 (ping.csv)

ping の計測結果を記録します。`session_<run_id>` ディレクトリ内に保存されます。

##### カラム

| column | type | description |
| --- | --- | --- |
| run_id | string | 計測セッション識別子 (実行開始時刻の Unix ミリ秒) |
| target | string | 宛先 IP アドレス |
| iteration | integer | 計測回数の通し番号 (1..count) |
| elapsed_ms | float | RTT ($ms$, 小数点以下3桁、失敗時は空) |
| success | boolean | 成功フラグ |
| error | string | エラーメッセージ（成功時は空） |
| started_at | string | 実行開始時刻 (ISO 8601) |

### 集計指標 (CSV 外部)

- 各ケースに対して平均・中央値・標準偏差・分散を算出
- 集計結果は別途レポートや図に反映

## 使用例

### 基本的な使い方

```bash
# デフォルト設定で実行（ping: 127.0.0.1 へ 5 回）
mix giocci_bench.single

# ping を無効化
mix giocci_bench.single --no-ping

# ping ターゲットをカスタマイズ
mix giocci_bench.single --ping-targets "127.0.0.1,192.168.0.101,192.168.0.102"

# ping 回数をカスタマイズ
mix giocci_bench.single --ping-count 10

# 複数オプションの組み合わせ
mix giocci_bench.single --ping-targets "127.0.0.1,8.8.8.8" --ping-count 3 --iterations 10

# 特定のケースのみ計測
mix giocci_bench.single --cases "register_client,save_module"
```

### 利用可能なオプション

- `--relay` - Relay 名（デフォルト: GIOCCI_RELAY 環境変数または "giocci_relay"）
- `--warmup` - ケースごとのウォームアップ回数（デフォルト: 1）
- `--iterations` - ケースごとの計測回数（デフォルト: 5）
- `--timeout-ms` - Giocci 呼び出しのタイムアウト (ミリ秒)（デフォルト: 5000）
- `--out-dir` - CSV 出力ディレクトリ（デフォルト: giocci_bench_output）
- `--cases` - 計測するケース（カンマ区切り: register_client, save_module, exec_func, local_exec）
- `--no-ping` - ping 計測を無効化（デフォルト: 有効）
- `--ping-targets` - ping ターゲット（カンマ区切り）（デフォルト: 127.0.0.1）
- `--ping-count` - 各ターゲットへの ping 回数（デフォルト: 5）

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
