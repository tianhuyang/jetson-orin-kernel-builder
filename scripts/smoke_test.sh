#!/usr/bin/env bash
# Quick post-build sanity checks for Jetson kernel/module deployment.

set -uo pipefail

KERNEL_SRC="/usr/src/kernel/kernel-jammy-src"
SAMPLE_MODULE="dm9601"
SHOW_DMESG=1
REQUIRED_CONFIGS=(
  "CONFIG_IP_ADVANCED_ROUTER"
  "CONFIG_IP_MULTIPLE_TABLES"
  "CONFIG_NET_SCH_HTB"
  "CONFIG_NET_SCH_TBF"
  "CONFIG_NET_SCH_CAKE"
  "CONFIG_NET_ACT_POLICE"
  "CONFIG_NET_CLS_U32"
  "CONFIG_NET_CLS_MATCHALL"
)

usage() {
  cat <<'EOF'
Usage: ./scripts/smoke_test.sh [options]

Options:
  -k, --kernel-src <path>     Kernel source tree (default: /usr/src/kernel/kernel-jammy-src)
  -m, --sample-module <name>  Module name to probe (default: dm9601)
  --no-dmesg                  Skip dmesg error summary
  -h, --help                  Show this help
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

pass() { echo "[PASS] $1"; }
warn() { echo "[WARN] $1"; }
fail() { echo "[FAIL] $1"; }

get_config_value() {
  local key="$1"
  local line

  # Prefer running-kernel config if available.
  if sudo_run zcat /proc/config.gz >/tmp/smoke_test_config.txt 2>/dev/null; then
    line="$(grep -E "^${key}=" /tmp/smoke_test_config.txt | tail -n 1 || true)"
    rm -f /tmp/smoke_test_config.txt
    if [[ -n "$line" ]]; then
      echo "${line#*=}"
      return 0
    fi
  fi

  # Fallback to source-tree .config.
  if [[ -f "$KERNEL_SRC/.config" ]]; then
    line="$(grep -E "^${key}=" "$KERNEL_SRC/.config" | tail -n 1 || true)"
    if [[ -n "$line" ]]; then
      echo "${line#*=}"
      return 0
    fi
  fi

  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -k|--kernel-src)
      shift
      KERNEL_SRC="${1:-}"
      ;;
    -m|--sample-module)
      shift
      SAMPLE_MODULE="${1:-}"
      ;;
    --no-dmesg)
      SHOW_DMESG=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift

done

FAILURES=0

krel="$(uname -r 2>/dev/null || true)"
if [[ -n "$krel" ]]; then
  pass "Running kernel: $krel"
else
  fail "Unable to read running kernel version"
  ((FAILURES+=1))
fi

if [[ -f /boot/Image ]]; then
  pass "Found /boot/Image"
else
  fail "Missing /boot/Image"
  ((FAILURES+=1))
fi

if [[ -f "$KERNEL_SRC/arch/arm64/boot/Image" ]]; then
  pass "Found built Image in $KERNEL_SRC"
else
  warn "Built Image not found in $KERNEL_SRC"
fi

if [[ -n "$krel" && -d "/lib/modules/$krel" ]]; then
  pass "Found /lib/modules/$krel"
else
  fail "Missing /lib/modules/$krel"
  ((FAILURES+=1))
fi

if [[ -n "$krel" && -f "/lib/modules/$krel/modules.dep" ]]; then
  pass "Found /lib/modules/$krel/modules.dep"
else
  fail "Missing /lib/modules/$krel/modules.dep"
  ((FAILURES+=1))
fi

for cfg in "${REQUIRED_CONFIGS[@]}"; do
  cfg_val="$(get_config_value "$cfg" || true)"
  if [[ "$cfg_val" == "y" ]]; then
    pass "$cfg=y"
  elif [[ -n "$cfg_val" ]]; then
    fail "$cfg expected y, got $cfg_val"
    ((FAILURES+=1))
  else
    fail "$cfg not found in /proc/config.gz or $KERNEL_SRC/.config"
    ((FAILURES+=1))
  fi
done

sample_path=""
if [[ -n "$krel" ]]; then
  sample_path="$(find "/lib/modules/$krel" -type f -name "${SAMPLE_MODULE}.ko*" 2>/dev/null | head -n 1)"
fi

if [[ -n "$sample_path" ]]; then
  pass "Sample module present: $sample_path"
  if modinfo "$sample_path" >/dev/null 2>&1; then
    pass "modinfo works for $SAMPLE_MODULE"
  else
    warn "modinfo failed for $sample_path"
  fi
else
  warn "Sample module '${SAMPLE_MODULE}' not found under /lib/modules/$krel"
fi

if [[ "$SHOW_DMESG" -eq 1 ]]; then
  if sudo_run dmesg -T >/tmp/smoke_test_dmesg.txt 2>/dev/null; then
    err_count="$(grep -Eic 'error|fail|fatal|panic|oops' /tmp/smoke_test_dmesg.txt || true)"
    if [[ "$err_count" -gt 0 ]]; then
      warn "dmesg contains $err_count error-like lines (showing last 50)"
      grep -Ei 'error|fail|fatal|panic|oops' /tmp/smoke_test_dmesg.txt | tail -n 50
    else
      pass "No error-like lines found in dmesg"
    fi
    rm -f /tmp/smoke_test_dmesg.txt
  else
    warn "Unable to read dmesg (permission or environment issue)"
  fi
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "Smoke test result: PASS"
  exit 0
fi

echo "Smoke test result: FAIL ($FAILURES checks failed)"
exit 1

