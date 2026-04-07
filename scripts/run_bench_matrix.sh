#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$ROOT_DIR/config/config.exs"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "config file not found: $CONFIG_FILE" >&2
  exit 1
fi

if [[ -z "${ZENOH_EP_CONFIG1:-}" ]]; then
  cat >&2 <<'EOF'
Missing endpoint env var.
Set at least:
  ZENOH_EP_CONFIG1=<endpoint-for-config1>
Optional:
  ZENOH_EP_CONFIG2=<endpoint-for-config2>
EOF
  exit 1
fi

if ! command -v mix >/dev/null 2>&1; then
  echo "mix command not found" >&2
  exit 1
fi

ORIGINAL_CONFIG_BACKUP="$(mktemp)"
cp "$CONFIG_FILE" "$ORIGINAL_CONFIG_BACKUP"
restore_config() {
  cp "$ORIGINAL_CONFIG_BACKUP" "$CONFIG_FILE"
  rm -f "$ORIGINAL_CONFIG_BACKUP"
}
trap restore_config EXIT

replace_measure_mfargs() {
  local app="$1"
  local mfargs=""

  case "$app" in
    sieve)
      mfargs="{GiocciBench.Samples.Sieve, :run, [[1_000_000]]}"
      ;;
    big_beam)
      mfargs="{GiocciBench.Samples.BigBeam, :run, [[]]}"
      ;;
    cpu_eater)
      mfargs="{GiocciBench.Samples.CpuEater, :run, [[]]}"
      ;;
    memory_eater)
      mfargs="{GiocciBench.Samples.MemoryEater, :run, [[]]}"
      ;;
    *)
      echo "unknown app: $app" >&2
      return 1
      ;;
  esac

  sed "s/^  measure_mfargs: .*/  measure_mfargs: ${mfargs}/" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" \
    && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
}

run_mix_task() {
  local task="$1"
  local endpoint="$2"
  local title="$3"

  echo "[run] task=$task title=$title endpoint=$endpoint"
  (
    cd "$ROOT_DIR"
    echo "ZENOHD_CONNECT_ENDPOINTS=\"$endpoint\" \
      mix giocci_bench.${task} --os-info --iterations 100 --title \"$title\""
    ZENOHD_CONNECT_ENDPOINTS="$endpoint" \
      mix giocci_bench.${task} --os-info --iterations 100 --title "$title"
  )
}

apps=(sieve big_beam cpu_eater memory_eater)
app_labels=(appA appB appC appD)
config_names=(config1)
endpoints=("$ZENOH_EP_CONFIG1")

if [[ -n "${ZENOH_EP_CONFIG2:-}" ]]; then
  config_names+=(config2)
  endpoints+=("$ZENOH_EP_CONFIG2")
fi

tasks=(single sequence)

for app_index in "${!apps[@]}"; do
  app="${apps[$app_index]}"
  app_label="${app_labels[$app_index]}"

  replace_measure_mfargs "$app"

  for i in "${!config_names[@]}"; do
    config_name="${config_names[$i]}"
    endpoint="${endpoints[$i]}"
    title="${config_name}-${app_label}"

    for task in "${tasks[@]}"; do
      run_mix_task "$task" "$endpoint" "$title"
    done
  done
done

echo "All runs completed. config/config.exs was restored."
