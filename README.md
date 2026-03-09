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
- `local_exec` - ローカルで直接実行（比較用）

### 出力ディレクトリ構造

計測セッションごとにディレクトリを作成し、メタデータと計測結果を分離します。

```
giocci_bench_output/
  session_1771220881580/
    meta.json                  # 計測セッションのメタデータ
    ping.csv                   # ping 計測結果
    register_client.csv        # 単体計測結果（ケースごとに分割）
    register_client_os_info_free.csv      # OS情報（--os-info 指定時のみ）
    register_client_os_info_proc_stat.csv # OS情報（--os-info 指定時のみ）
    save_module.csv
    exec_func.csv
    local_exec.csv
  session_1771221459080/
    meta.json
    ping.csv
    register_client.csv
    save_module.csv
    exec_func.csv
    local_exec.csv
```

- 出力先ディレクトリのデフォルトは `giocci_bench_output`
- `session_<run_id>` ディレクトリ名は実行開始時刻（UTC）を `YYYYMMDD-HHMMSS` 形式にしたもの
- 単体計測結果は `case_id` ごとに別ファイルに分割（例: `register_client.csv`, `save_module.csv`）
- `--os-info` 指定時は各ケースごとに OS 情報 CSV（`*_os_info_free.csv`, `*_os_info_proc_stat.csv`）を同じディレクトリに保存

### メタデータ仕様 (meta.json)

計測セッション全体の環境情報と、計測ケース説明を JSON で記録します。

```json
{
  "run_id": "20260309-140530",
  "started_at": "2026-02-17T10:00:00Z",
  "elixir_version": "1.14.0",
  "otp_version": "24.0",
  "os_type": "unix-linux",
  "system_arch": "x86_64-pc-linux-gnu",
  "cpu_cores": 4,
  "cases": {
    "register_client": "Giocci.register_client/2",
    "save_module": "Giocci.save_module/3",
    "exec_func": "Giocci.exec_func/3",
    "local_exec": "GiocciBench.Samples.Sieve.run/1"
  }
}
```

### CSV 出力仕様

#### ping 計測 (ping.csv)

ping の計測結果を記録します。`session_<run_id>` ディレクトリ内に保存されます。

##### カラム

| column | type | description |
| --- | --- | --- |
| run_id | string | 計測セッション識別子 (実行開始時刻（UTC）の `YYYYMMDD-HHMMSS`) |
| target | string | 宛先 IP アドレス |
| iteration | integer | 計測回数の通し番号 (1..count) |
| elapsed_ms | float | RTT ($ms$, 小数点以下3桁、失敗時は空) |
| success | boolean | 成功フラグ |
| error | string | エラーメッセージ（成功時は空） |

#### 単体計測 (register_client.csv, save_module.csv, exec_func.csv, local_exec.csv)

- 計測結果は `case_id` ごとに別ファイルに分割
- ファイル名は計測ケースの `case_id` と同じ
- 1 行 1 計測結果
- UTF-8, 改行は LF
- 環境情報は `meta.json` に記録するため CSV に含めない
- ケース説明 (`case_desc`) は `meta.json` の `cases` マップに記録
- 計算済み通信時間はデフォルトで出力
- 計算元タイムスタンプは `--include-timestamps` 指定時のみ出力（デフォルト: 非出力）

##### カラム

| column | type | description |
| --- | --- | --- |
| run_id | string | 計測セッション識別子 (実行開始時刻（UTC）の `YYYYMMDD-HHMMSS`) |
| case_id | string | 計測ケース識別子 (`register_client`, `save_module`, `exec_func`, `local_exec`) |
| iteration | integer | 計測回数の通し番号 (1..iterations) |
| elapsed_ms | float | クライアント側での呼び出しからリターンまでの時間 ($ms$, 小数点以下3桁) |
| function_elapsed_ms | float | 関数の処理時間 ($ms$, 小数点以下3桁、`exec_func`/`local_exec` のみ、サンプルモジュールが `GiocciBench.Samples.Benchmark` behaviour を実装して返す) |
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

# 計算元タイムスタンプ列も出力
mix giocci_bench.single --include-timestamps

# OS情報（CPU/メモリ）も取得（100ms周期、warmup後〜計測完了まで）
mix giocci_bench.single --os-info
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
- `--include-timestamps` - 計算元タイムスタンプ列をCSVに含める（デフォルト: 無効）
- `--os-info` - OS情報計測を有効化（100ms周期、warmup後〜計測完了まで、デフォルト: 無効）
