#!/bin/bash
# Kernel Source Retrieval and Setup Script for NVIDIA Jetson Developer Kit
# This script downloads, extracts, and configures the kernel source for Jetson Linux 36.X on 
# Ubuntu 22.04 Jammy. It ensures required dependencies are installed, provides options for 
# backing up or replacing existing sources, and sets up the kernel source for compilation.
# Logs the entire process for reference.
#
# Usage:
#   ./get_kernel_sources.sh [-d /usr/src] [--force-replace] [--force-backup] [--download-scope required|all]
#
# Options:
#   --force-replace  Replace existing destination source folders before publishing staged sources.
#   --force-backup   Backup existing destination source folders before publishing staged sources.
#   --download-scope Choose sync scope: required (default) or all.
#   -d, --directory  Parent source directory (default: /usr/src).
#   -h, --help       Show this help.
#
# Example:
#   ./get_kernel_sources.sh             # Interactive mode: prompts user if sources exist
#   ./get_kernel_sources.sh --force-replace # Replace destination source folders before publish
#   ./get_kernel_sources.sh --force-backup  # Backup destination source folders before publish
#   ./get_kernel_sources.sh --download-scope all # Sync full source_sync source list
#
# Logs are saved in a 'logs' directory within the script's execution path.
#
# Copyright (c) 2016-25 JetsonHacks
# MIT License

set -euo pipefail  # Exit on error

# script directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Set the log directory to ./logs relative to the current working directory
LOG_DIR=${LOG_DIR:-$PWD/logs}

# Define kernel source directories (for native Jetson builds)
BUILD_DIR=${BUILD_DIR:-$(pwd)/build}
SOURCE_SYNC_SCRIPT="${SCRIPT_DIR}/source_sync.sh"
SYNC_TAG_REPO="https://gitlab.com/nvidia/nv-tegra/3rdparty/canonical/linux-jammy.git"

# Default behavior (interactive mode)
FORCE_REPLACE=0
DOWNLOAD_SCOPE="required"

usage() {
  cat <<'EOF'
Usage: ./scripts/get_kernel_sources.sh [options]

Options:
  -d, --directory <path>          Build directory (default: $(pwd)/build)
  -l, --log <path>          log directory (default: $(pwd)/logs)
  --force-replace                 Replace existing destination source folders before publishing
  --download-scope required|all   Sync required kernel trees only or the full source_sync list (default: required)
  --download-required             Alias for --download-scope required
  --download-all                  Alias for --download-scope all
  -h, --help                      Show this help
EOF
}

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --force-replace) FORCE_REPLACE=1 ;;
    -d|--directory)
      shift
      if [[ $# -eq 0 || -z "${1:-}" ]]; then
        echo "[ERROR] --directory requires a directory path"
        usage
        exit 1
      fi
      BUILD_DIR="$1"
      ;;
    -l|--log)
      shift
      LOG_DIR="$1"
      ;;
    --download-scope)
      shift
      if [[ $# -eq 0 || -z "${1:-}" ]]; then
        echo "[ERROR] --download-scope requires a value: required|all"
        usage
        exit 1
      fi
      case "$1" in
        required|all) DOWNLOAD_SCOPE="$1" ;;
        *)
          echo "[ERROR] Invalid --download-scope value: $1 (expected: required|all)"
          usage
          exit 1
          ;;
      esac
      ;;
    --download-required) DOWNLOAD_SCOPE="required" ;;
    --download-all) DOWNLOAD_SCOPE="all" ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Invalid option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ "$FORCE_REPLACE" -eq 1 && "$FORCE_BACKUP" -eq 1 ]]; then
  echo "[ERROR] --force-replace and --force-backup cannot be used together"
  exit 1
fi

KERNEL_SRC_ENV_FILE="$BUILD_DIR/build.env"
rm -f "$KERNEL_SRC_ENV_FILE" || true

# Set the log file path
LOG_FILE="$LOG_DIR/get_kernel_sources.log"
# Ensure the logs directory exists
mkdir -p "$LOG_DIR"

# Logging function
log() {
  echo "[INFO] $(date +"%Y-%m-%d %H:%M:%S") - ${1}" | tee -a "$LOG_FILE"
}

error_exit() {
  echo "[ERROR] $(date +"%Y-%m-%d %H:%M:%S") - ${1}" | tee -a "$LOG_FILE" >&2
  exit 1
}

resolve_sync_tag() {
  local major="$1"
  local minor="$2"
  local release_full
  local tag

  release_full="${major}.${minor}"
  tag=$(git ls-remote --tags --refs "$SYNC_TAG_REPO" 2>/dev/null \
    | awk '{print $2}' \
    | sed 's#refs/tags/##' \
    | grep -E "_${release_full}$" \
    | sort -V \
    | tail -n 1 || true)
  if [[ -n "$tag" ]]; then
    echo "$tag"
    return 0
  fi

  return 1
}

if [[ ! -d "$BUILD_DIR" ]]; then
  error_exit "Build directory does not exist: $BUILD_DIR"
fi

TEGRAS_DIR="$BUILD_DIR/Tegras"
mkdir -p "$TEGRAS_DIR"
KERNEL_SRC_DIR=""

# Staging area where source_sync keeps git metadata
SYNC_STAGE_DIR="$BUILD_DIR/jetson-kernel-sync"

log "BUILD_DIR=$BUILD_DIR, LOG_DIR=$LOG_DIR"

validate_sync_tag_repo_access() {
  if ! git ls-remote --heads "$SYNC_TAG_REPO" >/dev/null 2>&1; then
    error_exit "Unable to access sync tag repository: $SYNC_TAG_REPO"
  fi
}

# Extract L4T version details using sed
L4T_MAJOR=$(sed -n 's/^.*R\([0-9]\+\).*/\1/p' /etc/nv_tegra_release)
L4T_MINOR=$(sed -n 's/^.*REVISION: \([0-9]\+\(\.[0-9]\+\)*\).*/\1/p' /etc/nv_tegra_release)

if [[ -z "$L4T_MAJOR" || -z "$L4T_MINOR" ]]; then
  error_exit "Unable to parse L4T version from /etc/nv_tegra_release"
fi


if [[ ! -f "$SOURCE_SYNC_SCRIPT" ]]; then
  error_exit "source_sync.sh not found at $SOURCE_SYNC_SCRIPT"
fi

if ! command -v git >/dev/null 2>&1; then
  error_exit "git is required but not installed"
fi

if ! command -v rsync >/dev/null 2>&1; then
  error_exit "rsync is required but not installed"
fi

validate_sync_tag_repo_access

log "Detected L4T version: ${L4T_MAJOR} (${L4T_MINOR})"
log "Download scope: ${DOWNLOAD_SCOPE}"

download_bsp() {
  local l4t_major="$1"
  local l4t_minor="$2"
  local major_minor
  local minor_first
  local minor_second
  local candidate
  local candidate_minor
  local -a minor_candidates=()
  local http_code
  local curl_rc
  local tried_list=""

  BSP_SRC_TMPL="https://developer.nvidia.com/downloads/embedded/l4t/r${l4t_major}_release_v%s/sources/public_sources.tbz2"

  # Build fallback list: exact x.y, then x.<y..0>, then x.
  major_minor=$(echo "$l4t_minor" | awk -F. '{if (NF >= 2) print $1 "." $2; else print $1}')
  minor_first=$(echo "$major_minor" | awk -F. '{print $1}')
  minor_second=$(echo "$major_minor" | awk -F. '{if (NF >= 2) print $2; else print ""}')

  if [[ -n "$minor_second" && "$minor_second" =~ ^[0-9]+$ ]]; then
    for ((candidate=minor_second; candidate>=0; candidate--)); do
      minor_candidates+=("${minor_first}.${candidate}")
    done
  else
    minor_candidates+=("$major_minor")
  fi
  minor_candidates+=("$minor_first")

  candidate_minor=""
  for candidate in "${minor_candidates[@]}"; do
    BSP_SRC=$(printf "$BSP_SRC_TMPL" "$candidate")
    http_code=$(curl -L -sS -o /dev/null -w "%{http_code}" "$BSP_SRC")
    curl_rc=$?

    if [[ -n "$tried_list" ]]; then
      tried_list="${tried_list}, ${candidate}"
    else
      tried_list="$candidate"
    fi

    if [[ $curl_rc -ne 0 ]]; then
      error_exit "Failed checking BSP source URL (curl rc=${curl_rc}): $BSP_SRC"
    fi

    if [[ "$http_code" == "200" ]]; then
      candidate_minor="$candidate"
      break
    fi

    if [[ "$http_code" == "404" ]]; then
      continue
    fi

    error_exit "Unexpected HTTP status ${http_code} while checking BSP source URL: $BSP_SRC"
  done

  if [[ -z "$candidate_minor" ]]; then
    error_exit "No BSP source match found for r${l4t_major} after trying release versions: ${tried_list}"
  fi

  BSP_SRC=$(printf "$BSP_SRC_TMPL" "$candidate_minor")
  BSP_SRC_DIR="$TEGRAS_DIR/${l4t_major}-${candidate_minor}"
  BSP_SRC_DIR_FILE="$BSP_SRC_DIR/public_sources.tbz2"

  log "Found BSP_SRC=$BSP_SRC for BSP_SRC_DIR=$BSP_SRC_DIR"
  mkdir -p "$BSP_SRC_DIR"
  if [ -f "$BSP_SRC_DIR_FILE" ]; then
    log "BSP source archive already exists at $BSP_SRC_DIR_FILE skipping download."
  else
    rm -f "$BSP_SRC_DIR_FILE.tmp" || true
    log "Downloading BSP sources from $BSP_SRC to $BSP_SRC_DIR_FILE.tmp..."
    wget -O "$BSP_SRC_DIR_FILE.tmp" "$BSP_SRC"
    mv "$BSP_SRC_DIR_FILE.tmp" "$BSP_SRC_DIR_FILE"
  fi
  BSP_SRC_DIR="$BSP_SRC_DIR/Linux_for_Tegra"
  KERNEL_SRC_DIR="$BSP_SRC_DIR/source"
  if [ -d "$BSP_SRC_DIR" ]; then
    log "BSP source directory already exists at $BSP_SRC_DIR skipping extraction."
  else
    BSP_SRC_DIR_TMP="$BSP_SRC_DIR".tmp
    rm -rf "$BSP_SRC_DIR_TMP" || true
    mkdir -p "$BSP_SRC_DIR_TMP"
    tar xf "$BSP_SRC_DIR_FILE" -C "$BSP_SRC_DIR_TMP" --strip-components=1
    log "BSP sources extracted to $BSP_SRC_DIR_TMP"
    cd "$BSP_SRC_DIR_TMP/source"
    tar xf kernel_src.tbz2
    tar xf kernel_oot_modules_src.tbz2
    tar xf nvidia_kernel_display_driver_source.tbz2
    mv "$BSP_SRC_DIR_TMP" "$BSP_SRC_DIR"
    cd "$BSP_SRC_DIR"
    log "BSP kernel sources and modules extracted to $BSP_SRC_DIR"
  fi
  cd "$KERNEL_SRC_DIR"
  log "Kernel sources directory: $KERNEL_SRC_DIR"
}

download_bsp "$L4T_MAJOR" "$L4T_MINOR"

SYNC_TAG=$(resolve_sync_tag "$L4T_MAJOR" "$L4T_MINOR") || true
if [[ -z "$SYNC_TAG" ]]; then
  error_exit "Failed to resolve sync tag for detected L4T release ${L4T_MAJOR}.${L4T_MINOR}."
fi
log "Resolved sync tag: ${SYNC_TAG}"

SYNC_STAGE_DIR="$SYNC_STAGE_DIR/${SYNC_TAG}"

log "Syncing sources to staging directory: $SYNC_STAGE_DIR"
mkdir -p "$SYNC_STAGE_DIR"
SOURCE_SYNC_ARGS=("-d" "$SYNC_STAGE_DIR" "-e")
if [[ "$DOWNLOAD_SCOPE" == "all" ]]; then
  SOURCE_SYNC_ARGS+=("-t" "$SYNC_TAG")
else
  SOURCE_SYNC_ARGS+=("-k" "$SYNC_TAG")
fi
if ! bash "$SOURCE_SYNC_SCRIPT" "${SOURCE_SYNC_ARGS[@]}" >> "$LOG_FILE" 2>&1; then
  error_exit "source_sync.sh failed. See $LOG_FILE for details."
fi

for staged_dir in \
  "$SYNC_STAGE_DIR/kernel/kernel-jammy-src" \
  "$SYNC_STAGE_DIR/nvidia-oot" \
  "$SYNC_STAGE_DIR/nvethernetrm" \
  "$SYNC_STAGE_DIR/nvdisplay"; do
  if [[ ! -d "$staged_dir" ]]; then
    error_exit "Expected staged source directory not found: $staged_dir"
  fi
done

log "Publishing all staged source subfolders from $SYNC_STAGE_DIR into $KERNEL_SRC_DIR using rsync..."
mkdir -p "$KERNEL_SRC_DIR"
shopt -s nullglob
STAGED_SUBDIRS=("$SYNC_STAGE_DIR"/*/)
shopt -u nullglob
if [[ ${#STAGED_SUBDIRS[@]} -eq 0 ]]; then
  error_exit "No staged source subfolders found in $SYNC_STAGE_DIR"
fi

# Check matching destination folders for every staged direct subfolder before publishing.
EXISTING_TARGETS=()
for staged_subdir in "${STAGED_SUBDIRS[@]}"; do
  staged_name=$(basename "${staged_subdir%/}")
  target="${KERNEL_SRC_DIR}/${staged_name}"
  if [[ -d "$target" ]]; then
    EXISTING_TARGETS+=("$target")
  fi
done

# backup Makefile for kernel
KERNEL_SRC_BACKUP_DIR="$KERNEL_SRC_DIR/backup"
mkdir -p "$KERNEL_SRC_BACKUP_DIR"
SYNC_FILE="$KERNEL_SRC_DIR/kernel/synced"
if [[ -f "$KERNEL_SRC_DIR/kernel/Makefile" ]]; then
  cp "$KERNEL_SRC_DIR/kernel/Makefile" "$KERNEL_SRC_BACKUP_DIR/Makefile"
  log "Backed up existing kernel Makefile to $KERNEL_SRC_BACKUP_DIR/Makefile"
fi

delete_existing_targets() {
  for target in "${EXISTING_TARGETS[@]}"; do
      rm -rf "$target"
  done
}
NEED_SYNC=1
# replace or backup
if [[ ${#EXISTING_TARGETS[@]} -gt 0 ]]; then
  log "Destination source folders already exist:"
  for target in "${EXISTING_TARGETS[@]}"; do
    log " - $target"
  done
  if [[ "$FORCE_REPLACE" -eq 1 ]]; then
    log "Forcing deletion of existing destination source folders..."
    delete_existing_targets
  elif [[ ! -f "$SYNC_FILE" ]]; then
    log "SYNC_FILE=$SYNC_FILE not found, assuming first time sync. Deleting existing destination source folders..."
    delete_existing_targets
  else
    NEED_SYNC=0
     log "SYNC_FILE=$SYNC_FILE found, skipping sync source folders"
  fi
fi
if [ $NEED_SYNC -eq 1 ]; then
  for staged_subdir in "${STAGED_SUBDIRS[@]}"; do
    staged_name=$(basename "${staged_subdir%/}")
    log "Publishing staged source folder: ${staged_name}"
    rsync -a --exclude '.git/' "$staged_subdir" "${KERNEL_SRC_DIR}/${staged_name}/"
  done
fi


# recover Makefile for kernel if it was backed up
if [[ -f "$KERNEL_SRC_BACKUP_DIR/Makefile" ]]; then
  cp  "$KERNEL_SRC_BACKUP_DIR/Makefile" "$KERNEL_SRC_DIR/kernel/Makefile"
  log "Recovered kernel Makefile from backup to $KERNEL_SRC_DIR/kernel/Makefile"
fi
touch "$SYNC_FILE"
echo "KERNEL_SRC_DIR=$KERNEL_SRC_DIR" > "$KERNEL_SRC_ENV_FILE"

log "Kernel sources and modules published to $KERNEL_SRC_DIR"

log "Kernel source setup complete!"
