#!/usr/bin/env bash
# End-to-end helper: get sources -> apply preset config -> build kernel -> build modules

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR=${BUILD_DIR:-/data/dev/build}
LOG_DIR=${LOG_DIR:-$PWD/logs}
DOWNLOAD_SCOPE="required"
INSTALL=0
CLEAN=0
REBOOT_AFTER_INSTALL=0

usage() {
  cat <<'EOF'
Usage: ./scripts/get_make_install.sh [options]

Options:
  -d, --directory <path>          Parent build directory (default: $PWD/build)
  -l, --log <path>          The log directory (default: $PWD/logs)
  --download-scope required|all   Scope for get_kernel_sources.sh (default: required)
  --clean                       Clean before build (default: no)
  --install                       Install kernel Image and modules after build (default: no)
  --reboot                        Reboot after successful --install flow (default: no)
  -h, --help                      Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--directory)
      shift
      if [[ $# -eq 0 || -z "${1:-}" ]]; then
        echo "[ERROR] --directory requires a directory path" >&2
        usage
        exit 1
      fi
      BUILD_DIR="${1:-}"
      ;;
    -l|--log)
      shift
      LOG_DIR="$1"
      ;;
    --download-scope)
      shift
      case "${1:-}" in
        required|all) DOWNLOAD_SCOPE="$1" ;;
        *) echo "[ERROR] --download-scope must be required|all" >&2; exit 1 ;;
      esac
      ;;
    --clean)
      CLEAN=1
      ;;
    --install)
      INSTALL=1
      ;;
    --reboot)
      REBOOT_AFTER_INSTALL=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ "$REBOOT_AFTER_INSTALL" -eq 1 && "$INSTALL" -eq 0 ]]; then
  echo "[ERROR] --reboot requires --install" >&2
  exit 1
fi

BUILD_DIR="${BUILD_DIR%/}"
if [[ -z "$BUILD_DIR" || "$BUILD_DIR" == "/" ]]; then
  echo "[ERROR] --directory must be a non-root parent source directory" >&2
  exit 1
fi

KERNEL_SRC_ENV_FILE="$BUILD_DIR/build.env"

make_clean_all() {
  # clean
  make -C kernel clean
  export KERNEL_HEADERS="$KERNEL_SRC"
  make clean
}

echo "[INFO] Source target: $BUILD_DIR"
echo "[INFO] Download scope: $DOWNLOAD_SCOPE"
echo "[INFO] Install after build: $INSTALL"

if [[ -n "${JETSON_HTTPS_PROXY:-}" ]]; then
  export https_proxy="$JETSON_HTTPS_PROXY"
  echo "[INFO] Exported https_proxy from JETSON_HTTPS_PROXY"
elif [[ -n "${https_proxy:-}" ]]; then
  echo "[INFO] Using existing https_proxy"
else
  echo "[WARN] https_proxy is not set"
fi

GET_SRC_ARGS=("-d" "$BUILD_DIR" -l "$LOG_DIR" "--download-scope" "$DOWNLOAD_SCOPE")

echo "[STEP 1/5] Retrieving kernel sources"
bash "$SCRIPT_DIR/get_kernel_sources.sh" "${GET_SRC_ARGS[@]}"
source "$KERNEL_SRC_ENV_FILE"
KERNEL_SRC="${KERNEL_SRC_DIR}/kernel/kernel-jammy-src"
echo "[INFO] Kernel source directory: KERNEL_SRC=$KERNEL_SRC"

echo "[STEP 2/5] Applying preset kernel config options"
bash "$SCRIPT_DIR/config.sh" -d "$KERNEL_SRC"

echo "[STEP 3/5] Building kernel Image and modules"
cd "$KERNEL_SRC_DIR"
if [[ "$CLEAN" -eq 1 ]]; then
  echo "[INFO] Cleaning build artifacts before build"
  make_clean_all
else
  echo "[INFO] Skipping clean before build"
fi
# build kernel
make -C kernel
# build modules
export KERNEL_HEADERS="$KERNEL_SRC"
make modules

# install & update initramfs if requested
if [[ "$INSTALL" -eq 1 ]]; then
  echo "[STEP 4/5] Installing kernel and modules"
  # install
  sudo make -C kernel install
  sudo -E make modules_install

  echo "[STEP 5/5] Applying kernel and modules metadata and update initramfs"
  # Use built tree release, not current uname -r, to avoid mismatched metadata updates.
  KERNEL_VERSION=$(sudo make -s -C "$KERNEL_SRC" kernelrelease)
  echo "KERNEL_VERSION from built kernel: $KERNEL_VERSION"
  KERNEL_VERSION=$(uname -r)
  echo "KERNEL_VERSION from uname -r: $KERNEL_VERSION"
  # install
  sudo rm -rf "/lib/modules/$KERNEL_VERSION/updates/opensrc-disp"
  sudo depmod -a "$KERNEL_VERSION"
  sudo nv-update-initrd
  # reboot if requested
  if [[ "$REBOOT_AFTER_INSTALL" -eq 1 ]]; then
    echo "[INFO] Rebooting now..."
    sudo reboot
  fi
else
  echo "[STEP 4/5] Skipped (install disabled)"
fi

echo "[INFO] Pipeline finished successfully"
