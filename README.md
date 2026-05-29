# jetson-orin-kernel-builder
Tools to build the Linux kernel and modules on board the **Jetson AGX Orin, Orin Nano, or Orin NX**. This tool is designed for **beginning to intermediate users**. Please **read this entire document before proceeding**.

This is for **JetPack 6**. [Supporting video.](https://youtu.be/7P6I2jeJNYo) on YouTube.

Reference https://docs.nvidia.com/jetson/archives/r36.3/DeveloperGuide/SD/Kernel/KernelCustomization.html

## Overview
This repository contains **convenience scripts** to simplify the process of:
- **Downloading Kernel and Module Sources** (Board Support Package Sources - BSP)
- **Editing Kernel Configuration** (Both **GUI** and **CLI** options available)
- **Building the Kernel Image**
- **Building Kernel Modules (in-tree (tested) and out of tree (untested) )**

These scripts help automate common tasks involved in kernel modification and module development on **Jetson Linux 36.X**.

---

## Prerequisites
Before using these scripts, ensure:
- You have a **Jetson Orin** device running **JetPack 6.X**.
- Your system is **up to date**:
  ```bash
  sudo apt update && sudo apt upgrade -y
  ```

### Quick Start on Remote Jetson
If you use `auth.env` and a synced remote workspace, this is the minimal flow:

```bash
source auth.env
ssh -p "$JETSON_PORT" "$JETSON_USER@$JETSON_HOST"
```

On the Jetson shell:

```bash
export https_proxy="$JETSON_HTTPS_PROXY"
cd /home/ubuntu/work/jetson-kernel
./scripts/get_kernel_sources.sh
```

Optional full sync mode (instead of default required-only mode):

```bash
./scripts/get_kernel_sources.sh --download-scope all
```

---

## Scripts

### **1. Get Kernel and Module Sources**
#### [`get_kernel_sources.sh`](scripts/get_kernel_sources.sh)
**Syncs and configures** kernel source for **Jetson Linux 36.X**.
- Automatically detects **L4T version**.
- Supports **backing up or replacing** existing kernel sources.
- Uses [`source_sync.sh`](scripts/source_sync.sh) to sync sources by L4T tag.
- Publishes required trees into `/usr/src` using `rsync`.
- Copies the **current kernel config** as basis for modification.

Usage:
```bash
./scripts/get_kernel_sources.sh [-d /usr/src] [--force-replace] [--force-backup] [--download-scope required|all]
```
Options:
- `-d | --directory <path>` → Parent source directory (default: `/usr/src`).
- `--force-replace` → Delete existing target source trees and sync fresh sources.
- `--force-backup` → Backup existing target source trees before syncing new ones.
- `--download-scope required|all` → Choose sync scope:
  - `required` (default): publish `/usr/src/kernel/kernel-jammy-src`, `/usr/src/nvidia/nvidia-oot`, `/usr/src/nvidia/nvdisplay`
  - `all`: additionally mirror full sync tree to `/usr/src/source_sync_all`

---

### **2. Edit Kernel Configuration**
#### GUI Mode: [`edit_config_gui.sh`](scripts/edit_config_gui.sh)
Launches `make xconfig`, a **graphical interface** for kernel configuration.
- Checks for required **Qt5 libraries** and installs them if missing.
- Runs `make xconfig` with appropriate permissions.

Usage:
```bash
./scripts/edit_config_gui.sh [kernel_source_directory]
```
_Defaults to `/usr/src/kernel/kernel-jammy-src`._

---

#### CLI Mode: [`edit_config_cli.sh`](scripts/edit_config_cli.sh)
Launches `make menuconfig`, a **text-based interface** for kernel configuration.
- Checks for **ncurses** dependency (`libncurses5-dev`).
- Runs 'make menuconfig' with appropriate permissions

Usage:
```bash
./scripts/edit_config_cli.sh [[-d directory] | [-h]]
```
Options:
- `-d | --directory <path>` → Specify kernel source directory.
- `-h | --help` → Display help message.

---

#### Preset Config Mode: [`config.sh`](scripts/config.sh)
Applies a preset of common routing and traffic-control options to the kernel `.config`:
- `CONFIG_IP_ADVANCED_ROUTER`
- `CONFIG_IP_MULTIPLE_TABLES`
- `CONFIG_NET_SCH_HTB`
- `CONFIG_NET_SCH_TBF`
- `CONFIG_NET_SCH_CAKE`
- `CONFIG_NET_ACT_POLICE`
- `CONFIG_NET_CLS_U32`
- `CONFIG_NET_CLS_MATCHALL`

Usage:
```bash
./scripts/config.sh [-d <kernel_source_path>] [--no-olddefconfig]
```

Options:
- `-d | --directory <path>` → Kernel source directory (default: `/usr/src/kernel/kernel-jammy-src`).
- `--no-olddefconfig` → Skip `make olddefconfig` after applying preset options.
- `-h | --help` → Display help message.

---

### **3. Build the Kernel**
#### [`make_kernel.sh`](scripts/make_kernel.sh)
Compiles the Linux kernel for the **Jetson Orin** series.
- **Checks kernel source path**.
- **Removes old kernel images** to ensure a clean build.
- Uses **multiple CPU cores** to optimize compilation.
- **Retries with a single-threaded build** if necessary.

Usage:
```bash
./scripts/make_kernel.sh [[-d directory] [--install] | [-h]]
```
Options:
- `-d | --directory <path>` → Specify kernel source directory.
- `--install` → Install built `Image` to `/boot/Image` after successful build (default: no install).
- `-h | --help` → Display help message.

---

### **4. Build Kernel Modules**
#### [`make_kernel_modules.sh`](scripts/make_kernel_modules.sh)
Builds and **optionally installs** kernel modules.
- Uses **optimized CPU allocation** for faster compilation.
- Automatically **updates module dependencies** after installation.
- If installation is skipped, **provides manual install instructions**.

Usage:
```bash
./scripts/make_kernel_modules.sh [[-d directory] [--install] | [-h]]
```
Options:
- `-d | --directory <path>` → Specify kernel source directory.
- `--install` → Install modules after successful build (default: no install).
- `-h | --help` → Display help message.

---

### **5. Build NVIDIA OOT Modules**
#### [`make_oot_modules.sh`](scripts/make_oot_modules.sh)
Builds NVIDIA out-of-tree module trees (`nvidia-oot`, `nvethernetrm`, `nvdisplay`) against the same kernel source and kernel release.
- Helps avoid module version mismatch after custom kernel builds.
- Can install directly to `/lib/modules/<kernelrelease>/extra/oot`.
- Can stage both a versioned directory tree and an archive with checksum.

Usage:
```bash
./scripts/make_oot_modules.sh [-d /usr/src] [--oot-scope full|net] [--install] [--stage-dir /tmp/oot_stage]
```

Options:
- `-d | --directory <path>` → Parent source directory (default: `/usr/src`).
- `--oot-scope full|net` → Build all OOT modules (`full`) or targeted network OOT modules (`net`, default).
- `--install` → Install OOT modules into `/lib/modules/<kernelrelease>`.
- `--stage-dir <path>` → Emit staged tree at `<path>/<kernelrelease>/...` and `<path>/<kernelrelease>_oot_modules.tar.xz` plus `.sha256`.

---

### **6. End-to-End Pipeline**
#### [`get_make_install.sh`](scripts/get_make_install.sh)
Runs the full pipeline in one command:
- `get_kernel_sources.sh`
- `config.sh`
- `make_kernel.sh`
- `make_kernel_modules.sh`
- `make_oot_modules.sh` (unless skipped)

Usage:
```bash
./scripts/get_make_install.sh [--download-scope required|all] [--force-replace|--force-backup] [--install] [--skip-oot] [--oot-scope full|net] [--stage-dir /tmp/oot_stage] [-d /usr/src]
```

Options:
- `--install` → Install `/boot/Image` and run `modules_install` after build (default: no install).
- `-d | --directory <path>` → Parent source directory passed to source retrieval and build scripts (default: `/usr/src`).
- `--download-scope required|all` → Choose required-only or full source sync (default: `required`).
- `--force-replace | --force-backup` → Control existing source-tree handling during retrieval.
- `--skip-oot` → Skip OOT module build/install stage.
- `--oot-scope full|net` → Select OOT build scope passed to `make_oot_modules.sh` (default: `net`).
- `--stage-dir <path>` → Stage OOT modules to versioned tree + tarball + sha256.

---

### Query Tool
This script analyzes kernel module flags, their dependencies, and configuration types for the **NVIDIA Jetson Developer Kit**. It helps users understand module flags, their status, dependencies, and related configurations by searching through **Makefiles, Kconfig, and .config**. The script also supports searching for related strings within kernel configuration files.

Usage:
```bash
./scripts/module_info.sh [-h] [-s <search_string>] <module_flag>
```

Options:
- `-h` : Display help message.
- `-s <search_string>` : Search for a string in **Makefiles, Kconfig, and .config** (case-insensitive).

Examples:
Analyze a specific config flag:
```bash
./scripts/module_info.sh CONFIG_LOGITECH_FF
```

Analyze a config module:
```bash
./scripts/module_info.sh CONFIG_USB_SERIAL_CH341
```

Search for USB-related configurations:
```bash
./scripts/module_info.sh -s usb
```

Features:
- Extracts module and flag information, including its type, possible values, and dependencies.
- Checks if the module is built-in (`y`), a loadable module (`m`), or not set (`n`).
- Supports searching for related configuration strings across **kernel sources**.

Environment Variables:
- `KERNEL_URI` : Specifies the kernel source directory (default: `/usr/src/kernel/kernel-jammy-src`).

### Pre-built module
The prebuilt directory contains pre-compiled linux kernel modules, mostly sourced from the mainline Linux kernel. They are offered as a convenience binary for systems where this in-tree module is not included or enable by default.


---

## Release History

### **March 2025**
- **Initial Release**
- Tested on **JetPack 6.2**
- Tested on the following devices:
  - **Jetson Orin Nano**
  - **Jetson AGX Orin**

---

## Notes
- **Ensure that all kernel changes are backed up** before installing a new kernel or modules.
- Running kernel modifications **requires root privileges**.
- If you face issues, check the **log files** generated in the `logs/` directory.


