#!/usr/bin/env bash
# Enable selected networking and traffic-control kernel config options.

set -euo pipefail

KERNEL_SRC="/usr/src/kernel/kernel-jammy-src"

RUN_OLDDEFCONFIG=1

usage() {
  cat <<'EOF'
Usage: ./scripts/config.sh [options]

Options:
  -d, --directory <path>  Kernel source path (default: /usr/src/kernel/kernel-jammy-src)
  --no-olddefconfig       Skip running make olddefconfig
  -h, --help              Show this help
EOF
}

sudo_run() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
    return
  fi

  if [[ -n "${JETSON_PASS:-}" ]]; then
    printf '%s\n' "$JETSON_PASS" | sudo -S -p '' "$@"
  else
    sudo "$@"
  fi
}


load_running_config() {
  # Use the currently running kernel config as a baseline when available.
  if sudo_run test -r /proc/config.gz; then
    echo "[INFO] Loading baseline config from /proc/config.gz"
    sudo_run bash -c "zcat /proc/config.gz > '$KERNEL_SRC/.config'"
  else
    echo "[WARN] /proc/config.gz not available; keeping existing $KERNEL_SRC/.config"
  fi
}

verify_kernelrelease() {
  local kernel_release
  kernel_release=$(sudo_run make -s -C "$KERNEL_SRC" kernelrelease)
  echo "[INFO] Kernel release after config: $kernel_release"
  if [[ "$kernel_release" != *-tegra ]]; then
    echo "[ERROR] Kernel release must end with -tegra, got: $kernel_release" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--directory)
      shift
      KERNEL_SRC="${1:-}"
      ;;
    --no-olddefconfig)
      RUN_OLDDEFCONFIG=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Invalid option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift

done

if [[ -z "$KERNEL_SRC" || ! -d "$KERNEL_SRC" ]]; then
  echo "[ERROR] Kernel source path does not exist: $KERNEL_SRC" >&2
  exit 1
fi

if [[ ! -x "$KERNEL_SRC/scripts/config" ]]; then
  echo "[ERROR] scripts/config not found or not executable in $KERNEL_SRC" >&2
  exit 1
fi

echo "[INFO] Applying requested config options in $KERNEL_SRC/.config"

load_running_config

sudo_run bash -c "
set -e
cd '$KERNEL_SRC'
scripts/config --file .config --enable IP_ADVANCED_ROUTER
scripts/config --file .config --enable IP_MULTIPLE_TABLES
scripts/config --file .config --enable NET_SCH_HTB
scripts/config --file .config --enable NET_SCH_TBF
scripts/config --file .config --enable NET_SCH_CAKE
scripts/config --file .config --enable NET_ACT_POLICE
scripts/config --file .config --enable NET_CLS_U32
scripts/config --file .config --enable NET_CLS_MATCHALL
"
# verify_kernelrelease

echo "[INFO] Resulting values:"
sudo_run bash -c "
cd '$KERNEL_SRC'
grep -E '^(CONFIG_LOCALVERSION|CONFIG_IP_ADVANCED_ROUTER|CONFIG_IP_MULTIPLE_TABLES|CONFIG_NET_SCH_HTB|CONFIG_NET_SCH_TBF|CONFIG_NET_SCH_CAKE|CONFIG_NET_ACT_POLICE|CONFIG_NET_CLS_U32|CONFIG_NET_CLS_MATCHALL)=' .config || true
"
DEFCONFIG="$KERNEL_SRC/arch/arm64/configs/defconfig"
DEFCONFIG_ORIGIN="$DEFCONFIG.origin"
sudo_run bash -c "
[ -f '$DEFCONFIG_ORIGIN' ] && { echo '[INFO] $DEFCONFIG_ORIGIN already exists, skipping backup'; exit; }
cp '$DEFCONFIG' '$DEFCONFIG_ORIGIN'
echo '[INFO] Backup $DEFCONFIG_ORIGIN'
"
sudo_run cp "$KERNEL_SRC/.config" "$DEFCONFIG"
echo "[INFO] Overwrite defconfig at $DEFCONFIG"

echo "[INFO] Done"

