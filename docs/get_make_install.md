# End-to-End Kernel Build Pipeline (`get_make_install.sh`)

## Overview

`get_make_install.sh` is the top-level pipeline helper that runs kernel source retrieval, applies preset config updates, builds kernel + modules, and optionally installs and updates initramfs.

Pipeline stages:
1. Retrieve sources via `scripts/get_kernel_sources.sh`
2. Apply preset config via `scripts/config.sh`
3. Build kernel + modules
4. (Optional) Install kernel + modules
5. (Optional) Reboot

---

## Usage

```bash
bash scripts/get_make_install.sh [options]
```

### Options

- `-d, --directory <path>`
  - Build directory passed to `get_kernel_sources.sh`
  - Default from environment: `BUILD_DIR`, otherwise `/data/dev/build`
- `-l, --log <path>`
  - Log directory passed to `get_kernel_sources.sh`
  - Default from environment: `LOG_DIR`, otherwise `./logs`
- `--download-scope required|all`
  - Source sync scope (default: `required`)
- `--clean`
  - Run clean before build
- `--install`
  - Install kernel and modules after successful build
- `--reboot`
  - Reboot after install (requires `--install`)
- `-h, --help`
  - Show help

---

## What It Uses Internally

- `scripts/get_kernel_sources.sh`
  - Produces `<build_dir>/build.env` containing `KERNEL_SRC_DIR=...`
- `scripts/config.sh -d "$KERNEL_SRC"`
  - Applies preset kernel config flags
- Build commands in source root (`$KERNEL_SRC_DIR`):
  - `make -C kernel`
  - `make modules`
- Install flow (`--install`):
  - `sudo make -C kernel install`
  - `sudo -E make modules_install`
  - `sudo depmod -a "$KERNEL_VERSION"`
  - `sudo nv-update-initrd`

---

## Environment Variables

- `BUILD_DIR`
  - Default build directory if `-d` is not provided
- `LOG_DIR`
  - Default log directory if `-l` is not provided
- `JETSON_HTTPS_PROXY`
  - If set, script exports it to `https_proxy` before source retrieval

---

## Examples

### 1) Required-scope build only

```bash
bash scripts/get_make_install.sh -d /data/dev/build -l "$PWD/logs"
```

### 2) Full source sync + clean build

```bash
bash scripts/get_make_install.sh -d /data/dev/build -l "$PWD/logs" --download-scope all --clean
```

### 3) Build, install, and reboot

```bash
bash scripts/get_make_install.sh -d /data/dev/build -l "$PWD/logs" --install --reboot
```

### 4) Remote shell with proxy

```bash
export https_proxy="$JETSON_HTTPS_PROXY"
bash scripts/get_make_install.sh -d /data/dev/build -l "$PWD/logs" --install
```

---

## Notes

- `--reboot` is rejected unless `--install` is also set.
- Source retrieval must succeed and generate `<build_dir>/build.env`; otherwise pipeline stops.
- If proxy access is required, set `JETSON_HTTPS_PROXY` (or `https_proxy`) before running.
- Run from repository root so relative script paths resolve correctly.

