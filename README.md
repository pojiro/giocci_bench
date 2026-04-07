# GiocciBench

giocci の性能計測を行い、処理時間を CSV で出力するためのベンチマークプロジェクトです。

## 計測仕様

### 計測対象

#### ping 計測

通信にかかる時間の基準値として、giocci の計測前に ping 応答時間を計測します。

- 宛先: `--ping-targets` オプションで指定（デフォルト: 127.0.0.1）
- 回数: `--ping-count` オプションで指定（デフォルト: 5回）
- CSV への記録方法: 別スキーマ
- RTT が取得できない場合は `success=false`、`elapsed_ms` は空、`error` に詳細を記録

#### 単体計測

giocci の主要処理として、`lib/giocci_bench/samples/` 配下のベンチマーク用モジュールを転送して計測します。

- デフォルトは `GiocciBench.Samples.Add` モジュール（引数: `[1, 2]`）
- 処理時間は「呼び出しからリターンを得るまでの実測時間」を計測
- 計測は `mix giocci_bench.single` として呼び出せる
- ベンチ実行時点の環境情報はメタデータファイルに記録
  - OS, Elixir バージョン, Erlang/OTP バージョン
  - CPU コア数

**実行フロー：**

1. **ping 計測** - 通信にかかる時間の基準値を取得（`--no-ping` で無効化可能）
2. **prepare** - 計測対象に応じて事前に必要な giocci 関数を実行
3. **ウォームアップ** - 初回実行の影響を除外するため指定回数実行
4. **イテレーション計測** - 指定回数の計測を実行し、各実行時間を記録

**計測項目：**

- `register_client`
- `save_module`
  - 計測前に `register_client` を事前実行
- `exec_func`
  - 計測前に `register_client` と `save_module` を事前実行

#### ローカル比較計測

比較用に、同一のサンプルモジュールをローカルで直接実行する `local_exec` を計測できます。

- 計測は `mix giocci_bench.local` として呼び出せる
- ローカル比較計測では ping 計測を行わない

#### シーケンス計測

giocci の連続処理として、`register_client` → `save_module` → `exec_func` を順に実行し、
シナリオ全体の処理時間を計測します。

- 計測は `mix giocci_bench.sequence` として呼び出せる
- `register_client` の呼び出し開始から `exec_func` の返却取得までを計測
- 計測対象の mfargs は `exec_func` のみを meta.json に記録

### 出力ディレクトリ構造

計測セッションごとにディレクトリを作成し、メタデータと計測結果を分離します。

単体計測（`mix giocci_bench.single`）の例:

```
giocci_bench_output/
  session_20260309-140530-single/
    meta.json                  # 計測セッションのメタデータ
    ping.csv                   # ping 計測結果
    register_client.csv        # 単体計測結果（ケースごとに分割）
    register_client_os_info_free.csv      # OS情報（--os-info 指定時のみ）
    register_client_os_info_proc_stat.csv # OS情報（--os-info 指定時のみ）
    save_module.csv
    exec_func.csv
```

ローカル比較計測（`mix giocci_bench.local`）の例:

```
giocci_bench_output/
  session_20260309-140530-local/
    meta.json
    local_exec.csv
```

シーケンス計測（`mix giocci_bench.sequence`）の例:

```
giocci_bench_output/
  session_20260310-101530-sequence/
    meta.json
    ping.csv
    sequence.csv               # シーケンス計測結果
```

- 出力先ディレクトリのデフォルトは `giocci_bench_output`
- ディレクトリの命名規則は `session_<run_id>-<task>[-<title>]`
  - `run_id` は実行開始時刻（UTC）の `YYYYMMDD-HHMMSS` 形式
  - `task` は実行したMixタスク名
    - 単体計測のディレクトリ名は `session_<run_id>-single`
    - シーケンス計測のディレクトリ名は `session_<run_id>-sequence`
    - ローカル比較計測のディレクトリ名は `session_<run_id>-local`
  - `--title` 指定時は `session_<run_id>-<task>-<title>` 形式になり、`/` と `\` は `_` に置換
- 単体計測結果は `case_id` ごとに別ファイルに分割（例: `register_client.csv`, `save_module.csv`）
- シーケンス計測結果は `sequence.csv` に出力
- ローカル比較計測結果は `local_exec.csv` に出力
- `--os-info` 指定時は実行モードに応じた OS 情報 CSV（`*_os_info_free.csv`, `*_os_info_proc_stat.csv`）を同じディレクトリに保存

### メタデータ仕様 (meta.json)

計測セッション全体の環境情報と、計測ケース説明を JSON で記録します。

- `cases` には各ケースの実行時の `{module, function, args}` を `inspect/1` で文字列化した値が記録されます。
- `measure_mfargs` には設定/実行時に使った計測対象 mfargs（`config/config.exs` の `measure_mfargs` など）が `inspect/1` で記録されます。
- giocci のケースは引数末尾のオプション（`timeout` と `measure_to`）も含まれます。
- 単体計測では `measure_to` は meta.json では `nil` で記録されますが、実行時には計測用 PID が注入されます。
- `measure_mfargs` には計測対象として設定された mfargs が `inspect/1` で文字列化されて記録されます（`cases` 内の個別ケースの mfargs とは異なります）。
- `--title` 指定時は `title` フィールドが meta.json に追加されます。

```json
{
  "run_id": "20260309-140530",
  "started_at": "2026-02-17T10:00:00Z",
  "elixir_version": "1.14.0",
  "otp_version": "24.0",
  "os_type": "unix-linux",
  "system_arch": "x86_64-pc-linux-gnu",
  "cpu_cores": 4,
  "measure_mfargs": "{GiocciBench.Samples.Sieve, :run, [[1000000]]}",
  "cases": {
    "register_client": "{Giocci, :register_client, [\"giocci_relay\", [timeout: 5000, measure_to: nil]]}",
    "save_module": "{Giocci, :save_module, [\"giocci_relay\", GiocciBench.Samples.Sieve, [timeout: 5000, measure_to: nil]]}",
    "exec_func": "{Giocci, :exec_func, [\"giocci_relay\", {GiocciBench.Samples.Sieve, :run, [[1000000]]}, [timeout: 5000, measure_to: nil]]}"
  }
}
```

ローカル比較計測では `cases` に `local_exec` の mfargs を 1 件だけ記録します。

```json
{
  "measure_mfargs": "{GiocciBench.Samples.Sieve, :run, [[1000000]]}",
  "cases": {
    "local_exec": "{GiocciBench.Samples.Sieve, :run, [[1000000]]}"
  }
}
```

シーケンス計測では `cases` に `exec_func` の mfargs を 1 件だけ記録します。
シーケンス計測は通信内訳の計測を行わないため、`measure_to` は利用しません。

```json
{
  "measure_mfargs": "{GiocciBench.Samples.Sieve, :run, [[1000000]]}",
  "cases": {
    "sequence": "{Giocci, :exec_func, [\"giocci_relay\", {GiocciBench.Samples.Sieve, :run, [[1000000]]}, [timeout: 5000]]}"
  }
}
```

### CSV 出力仕様

#### ping 計測 (ping.csv)

ping の計測結果を記録します。`session_<run_id>-ping` ディレクトリ内に保存されます。

##### カラム

| column | type | description |
| --- | --- | --- |
| run_id | string | 計測セッション識別子 (実行開始時刻（UTC）の `YYYYMMDD-HHMMSS`) |
| target | string | 宛先 IP アドレス |
| iteration | integer | 計測回数の通し番号 (1..count) |
| elapsed_ms | float | RTT ($ms$, 小数点以下3桁、失敗時は空) |
| success | boolean | 成功フラグ |
| error | string | エラーメッセージ（成功時は空） |

#### 単体計測 (register_client.csv, save_module.csv, exec_func.csv)

- 計測結果は `case_id` ごとに別ファイルに分割
- ファイル名は計測ケースの `case_id` と同じ
- 1 行 1 計測結果
- UTF-8, 改行は LF
- 環境情報は `meta.json` に記録するため CSV に含めない
- 実行時の mfargs は `meta.json` の `cases` マップに記録
- 計算済み通信時間はデフォルトで出力
- 計算元タイムスタンプは `--include-timestamps` 指定時のみ出力（デフォルト: 非出力）

##### カラム

| column | type | description |
| --- | --- | --- |
| run_id | string | 計測セッション識別子 (実行開始時刻（UTC）の `YYYYMMDD-HHMMSS`) |
| case_id | string | 計測ケース識別子 (`register_client`, `save_module`, `exec_func`) |
| iteration | integer | 計測回数の通し番号 (1..iterations) |
| elapsed_ms | float | クライアント側での呼び出しからリターンまでの時間 ($ms$, 小数点以下3桁) |
| function_elapsed_ms | float | 関数の処理時間 ($ms$, 小数点以下3桁、`exec_func` のみ、サンプルモジュールが `GiocciBench.Samples.BenchmarkBehaviour` behaviour を実装して返す) |
| warmup | integer | 実行した warmup 回数 |
| client_to_relay | float | クライアント→リレー通信時間 ($ms$) |
| relay_to_client | float | リレー→クライアント通信時間 ($ms$) |
| relay_to_engine | float | リレー→エンジン通信時間 ($ms$) |
| engine_to_relay | float | エンジン→リレー通信時間 ($ms$) |
| client_to_engine | float | クライアント→エンジン通信時間 ($ms$) |
| engine_to_client | float | エンジン→クライアント通信時間 ($ms$) |

計測には Elixir 標準の `System.os_time/1` を使用します。

`--include-timestamps` 指定時は、以下の計算元タイムスタンプ列（$ms$）も追加で出力されます。

- `client_send_timestamp_to_relay`
- `relay_recv_timestamp_from_client`
- `relay_send_timestamp_to_client`
- `client_recv_timestamp_from_relay`
- `relay_send_timestamp_to_engine`
- `engine_recv_timestamp_from_relay`
- `engine_send_timestamp_to_relay`
- `relay_recv_timestamp_from_engine`
- `client_send_timestamp_to_engine`
- `engine_recv_timestamp_from_client`
- `engine_send_timestamp_to_client`
- `client_recv_timestamp_from_engine`

#### ローカル比較計測 (local_exec.csv)

- 計測結果は `local_exec.csv` に出力
- `case_id` は常に `local_exec`
- 1 行 1 計測結果
- UTF-8, 改行は LF

##### カラム

| column | type | description |
| --- | --- | --- |
| run_id | string | 計測セッション識別子 (実行開始時刻（UTC）の `YYYYMMDD-HHMMSS`) |
| case_id | string | 固定値 `local_exec` |
| iteration | integer | 計測回数の通し番号 (1..iterations) |
| elapsed_ms | float | ローカル呼び出しからリターンまでの時間 ($ms$, 小数点以下3桁) |
| function_elapsed_ms | float | 関数の処理時間 ($ms$, 小数点以下3桁、サンプルモジュールが `GiocciBench.Samples.BenchmarkBehaviour` behaviour を実装して返す) |
| warmup | integer | 実行した warmup 回数 |
| client_to_relay | float | 空 |
| relay_to_client | float | 空 |
| relay_to_engine | float | 空 |
| engine_to_relay | float | 空 |
| client_to_engine | float | 空 |
| engine_to_client | float | 空 |

#### シーケンス計測 (sequence.csv)

- 計測結果は `sequence.csv` に出力
- `case_id` は常に `sequence`
- 1 行 1 計測結果
- UTF-8, 改行は LF
- 環境情報は `meta.json` に記録するため CSV に含めない
- 実行時の mfargs は `meta.json` の `cases` に `exec_func` のみを記録

##### カラム

| column | type | description |
| --- | --- | --- |
| run_id | string | 計測セッション識別子 (実行開始時刻（UTC）の `YYYYMMDD-HHMMSS`) |
| case_id | string | 固定値 `sequence` |
| iteration | integer | 計測回数の通し番号 (1..iterations) |
| elapsed_ms | float | シナリオ全体の処理時間 ($ms$, 小数点以下3桁) |
| function_elapsed_ms | float | 関数の処理時間 ($ms$, 小数点以下3桁、`exec_func` の返却値から取得) |
| warmup | integer | 実行した warmup 回数 |
| error | string | 失敗時は `{:error, reason}` の `reason` を `inspect/1` した値（成功時は空） |

### 集計指標 (CSV 外部)

- 各ケースに対して平均・中央値・標準偏差・分散を算出
- 集計結果は別途レポートや図に反映

### 設定 (`config :giocci_bench`)

計測対象の `mfargs` は `config/config.exs` の `config :giocci_bench` で設定できます。

```elixir
config :giocci_bench,
  # {module, func, args}
  # IMPORTANT: args is a list passed to apply/3.
  # If run/1 expects a list argument, wrap it as [[...]].
  measure_mfargs: {GiocciBench.Samples.Sieve, :run, [[1_000_000]]}
```

#### 設定キー

- `measure_mfargs` - 単体計測 / ローカル比較計測 / シーケンス計測で共通して使う mfargs

#### 解決順序（優先順位）

- 実行時オプション `:mfargs`（内部APIから `run/1` を直接呼ぶ場合）
- `measure_mfargs`
- デフォルト値: `{GiocciBench.Samples.Add, :run, [[1, 2]]}`

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

# セッションタイトルを付けて実行（出力ディレクトリ名と meta.json に反映）
mix giocci_bench.single --title "nightly"

# ローカル比較計測（local_exec のみ）
mix giocci_bench.local

# 計算元タイムスタンプ列も出力
mix giocci_bench.single --include-timestamps

# OS情報（CPU/メモリ）も取得（100ms周期、warmup後〜計測完了まで）
mix giocci_bench.single --os-info

# シーケンス計測を実行
mix giocci_bench.sequence

# シーケンス計測で ping を無効化
mix giocci_bench.sequence --no-ping

# シーケンス計測で反復回数を変更
mix giocci_bench.sequence --iterations 10
```

### 利用可能なオプション

#### ping 計測

- `--no-ping` - ping 計測を無効化（デフォルト: 有効）
- `--ping-targets` - ping ターゲット（カンマ区切り）（デフォルト: 127.0.0.1）
- `--ping-count` - 各ターゲットへの ping 回数（デフォルト: 5）

#### 単体計測

- `--relay` - Relay 名（デフォルト: GIOCCI_RELAY 環境変数または "giocci_relay"）
- `--warmup` - ケースごとのウォームアップ回数（デフォルト: 1）
- `--iterations` - ケースごとの計測回数（デフォルト: 5）
- `--timeout-ms` - Giocci 呼び出しのタイムアウト (ミリ秒)（デフォルト: 5000）
- `--out-dir` - CSV 出力ディレクトリ（デフォルト: giocci_bench_output）
- `--title` - セッションタイトル（出力ディレクトリ名末尾と meta.json の `title` に反映）
- `--cases` - 計測するケース（カンマ区切り: register_client, save_module, exec_func）
- `--no-ping` - ping 計測を無効化（デフォルト: 有効）
- `--ping-targets` - ping ターゲット（カンマ区切り）（デフォルト: 127.0.0.1）
- `--ping-count` - 各ターゲットへの ping 回数（デフォルト: 5）
- `--include-timestamps` - 計算元タイムスタンプ列をCSVに含める（デフォルト: 無効）
- `--os-info` - OS情報計測を有効化（100ms周期、warmup後〜計測完了まで、デフォルト: 無効）

#### ローカル比較計測

- `--warmup` - ケースごとのウォームアップ回数（デフォルト: 1）
- `--iterations` - ケースごとの計測回数（デフォルト: 5）
- `--out-dir` - CSV 出力ディレクトリ（デフォルト: giocci_bench_output）
- `--title` - セッションタイトル（出力ディレクトリ名末尾と meta.json の `title` に反映）
- `--include-timestamps` - 計算元タイムスタンプ列をCSVに含める（デフォルト: 無効）
- `--os-info` - OS情報計測を有効化（100ms周期、warmup後〜計測完了まで、デフォルト: 無効）

#### シーケンス計測

- `--relay` - Relay 名（デフォルト: GIOCCI_RELAY 環境変数または "giocci_relay"）
- `--warmup` - シナリオのウォームアップ回数（デフォルト: 1）
- `--iterations` - シナリオの計測回数（デフォルト: 5）
- `--timeout-ms` - Giocci 呼び出しのタイムアウト (ミリ秒)（デフォルト: 5000）
- `--out-dir` - CSV 出力ディレクトリ（デフォルト: giocci_bench_output）
- `--title` - セッションタイトル（出力ディレクトリ名末尾と meta.json の `title` に反映）
- `--no-ping` - ping 計測を無効化（デフォルト: 有効）
- `--ping-targets` - ping ターゲット（カンマ区切り）（デフォルト: 127.0.0.1）
- `--ping-count` - 各ターゲットへの ping 回数（デフォルト: 5）
- `--os-info` - OS情報計測を有効化（100ms周期、warmup後〜計測完了まで、デフォルト: 無効）

## 可視化

本機能はGitHub Copilotで実装されています（？？

### 単体セッションの可視化

```bash
# 最新セッションの CSV をグラフ化して report.html を生成
mix giocci_bench.visualize

# セッションを指定してグラフ化
mix giocci_bench.visualize --session-dir giocci_bench_output/session_20260406-103137

# ワイルドカードでセッション指定（パターンに一致するセッション全てを一括処理）
mix giocci_bench.visualize --session-dir "giocci_bench_output/session_20260406-10*"

# 出力先を指定（単体セッション или ワイルドカードが1つのみマッチの場合に有効）
mix giocci_bench.visualize --session-dir giocci_bench_output/session_20260406-103137 --output tmp/bench_report.html

# report.html を生成してブラウザで開く
mix giocci_bench.visualize --open
```

- `--out-dir` - `session_*` を含む出力ディレクトリ（デフォルト: giocci_bench_output）
- `--session-dir` - 可視化対象のセッションディレクトリを明示指定（ワイルドカード: `*`, `?`, `[...]` に対応；マッチした全セッションを一括処理）
- `--output` - 生成する HTML レポートの出力パス（デフォルト: `<session_dir>/report.html`；複数セッション一括処理時は各セッションディレクトリ配下に自動生成）
- `--open` - 生成後に既定ブラウザで HTML を開く（複数セッション時は全て開く）

`mix giocci_bench.visualize` はセッション内の以下の CSV を自動検出して可視化します。

- 単体/シーケンス計測 CSV（`register_client.csv`, `save_module.csv`, `exec_func.csv`, `local_exec.csv`, `sequence.csv`）
- ping 計測 CSV（`ping.csv`）
- OS 情報 CSV（`*_os_info_free.csv`, `*_os_info_proc_stat.csv`）
  - `*_os_info_proc_stat.csv` は列ごとの生値ではなく、差分から算出した `cpu_usage_pct`（%）を表示
  - 計算式: `100 * (1 - idle_delta / total_delta)`

レポートには折れ線グラフと、各列の基本統計（count, mean, median, min, max, stddev）が含まれます。

ヘッダには以下の情報が表示されます。

- セッションタイトル（`meta.json` の `session_title` がある場合はそれを表示し、未指定時は固定タイトル `Giocci Bench Visualization` を表示）
- セッションディレクトリ名とレポート生成時刻
- 計測対象の MFArgs（`meta.json` の `cases`）

### 複数セッションの比較

```bash
# 同一タスクで実行した複数セッションを箱ひげ図で比較
mix giocci_bench.visualize.compare \
  --session-dir giocci_bench_output/session_20260407-100000-sequence-nightly \
  --session-dir giocci_bench_output/session_20260407-101000-sequence-baseline

# 出力先を指定（未指定時は giocci_bench_output/comparison_<日時>/report.html）
mix giocci_bench.visualize.compare \
  --session-dir giocci_bench_output/session_20260407-100000-sequence-nightly \
  --session-dir giocci_bench_output/session_20260407-101000-sequence-baseline \
  --output tmp/compare_report.html

# ワイルドカード指定（ "" 囲み必須）
mix giocci_bench.visualize.compare \
  --session-dir "giocci_bench_output/session_20260407-10*-sequence-*"
```

`mix giocci_bench.visualize.compare` の主な仕様:

- `--session-dir` を2つ以上指定して比較（同一 Mix タスク種別のセッションのみ許可）
  - `*`, `?`, `[]` のワイルドカード指定に対応（展開結果が比較対象）
  - セッションが異なる種別（single/sequence/local）ならエラー
- `--os-info` で取得した CSV（`*_os_info_free.csv`, `*_os_info_proc_stat.csv`）も箱ひげ図で比較
  - 指定したセッションのいずれかに os-info CSV が不足している場合は、不足セッション名を含めてエラー
  - `*_os_info_proc_stat.csv` は単一セッション可視化と同じく、差分から算出した `cpu_usage_pct`（%）を比較
- 凡例ラベルは各 `meta.json` の `title` を優先
  - `title` がない場合は `A`, `B`, ... で代用
- 比較レポートの既定出力先は `giocci_bench_output/comparison_<日時>/report.html`
- 各比較グラフについて CSV/SVG を `giocci_bench_output/comparison_<日時>/report/` に出力

## Docker での実行

このリポジトリには Docker Compose でそのまま使える開発用コンテナを用意しています。

- ベースイメージ: `hexpm/elixir:1.19.5-erlang-28.3-ubuntu-noble-20251013`
- 追加パッケージ: `chrony`, `iputils-ping`, `procps`, `git`, `build-essential`
- リポジトリ全体を `/workspace` に bind mount
- コンテナ内の実行ユーザはホストの `uid/gid` と名前をビルド時に合わせられる

### ビルド

```bash
LOCAL_USER="$(id -un)" \
LOCAL_UID="$(id -u)" \
LOCAL_GID="$(id -g)" \
docker compose build
```

> `LOCAL_USER` / `LOCAL_UID` / `LOCAL_GID` を省略した場合は `dev:1000:1000` で作成されます。

### シェルに入る

`docker compose run` で bash に入り、その中で `mix` コマンドを実行していく運用を想定しています。

```bash
LOCAL_USER="$(id -un)" \
LOCAL_UID="$(id -u)" \
LOCAL_GID="$(id -g)" \
docker compose run --rm giocci_bench
```

以降はDockerコンテナ内での操作を示しています。

```bash
mix deps.get
mix compile
mix test
mix giocci_bench.single
mix giocci_bench.sequence
```

### 補足

- `chrony` はイメージ内にインストールされますが、systemd を使わないためデーモンは自動起動しません。
- Mix / Hex のホームディレクトリは Docker volume に保持されるため、コンテナを作り直してもキャッシュが残ります。
- ベンチマーク結果は bind mount されたワークスペース側に出力されます。

