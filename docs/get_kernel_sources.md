# Kernel Source Setup Script Documentation

## Overview

This Bash script automates retrieval and setup of kernel sources for NVIDIA Jetson devices running Linux for Tegra (L4T) 36.X on Ubuntu 22.04 Jammy. It uses `scripts/source_sync.sh` to sync sources by L4T-matched git tag into a staging directory, then publishes selected trees to `/usr/src` with `rsync`. The script manages existing source trees based on user input or command-line flags, ensures required dependencies are installed, and logs all actions to a timestamped file.

## Requirements

To run this script successfully, the following are required:

- **Operating System**: A Jetson device running Ubuntu 22.04 Jammy with Linux for Tegra (L4T) version 36.X.
- **Internet Access**: Required to sync source repositories from NVIDIA's public git remotes.
- **Sudo Privileges**: Necessary for writing to `/usr/src/`, extracting files, and installing packages.
- **Utilities**: 
  - `git`: For syncing kernel-related source repositories.
  - `rsync`: For publishing source trees from staging into `/usr/src`.
- **Dependency**: 
  - `libssl-dev`: Required for kernel building; the script will install it if absent.
- **File Access**: Read access to `/etc/nv_tegra_release` for L4T version detection and `/proc/config.gz` for kernel configuration.

## Usage
```bash
./scripts/get_kernel_sources.sh [-d /usr/src] [--force-replace | --force-backup] [--download-scope required|all]
```

### Quick Start on Remote Jetson
If your IDE syncs this workspace to Jetson and you use `auth.env` for login:

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

Optional full sync mode:

```bash
./scripts/get_kernel_sources.sh --download-scope all
```

### Options
-d, --directory <path>:
Sets the parent source directory. Defaults to `/usr/src`. Published trees are placed below this directory.

--force-replace:
Deletes existing target source trees without prompting and syncs fresh sources.

--force-backup:
Backs up existing target source trees to timestamped paths (for example, `/usr/src/kernel/kernel-jammy-src_backup_YYYYMMDD_HHMMSS`) without prompting and syncs fresh sources.

--download-scope required|all:
Controls what is synced from `source_sync.sh`.
- `required` (default): sync using `-k` and publish only required trees.
- `all`: sync full `source_sync.sh` list and additionally publish the full tree under `/usr/src/source_sync_all/`.

If no options are provided and any target source tree already exists, the script will prompt you to choose an action:
[K]eep: Retain existing sources and exit (default).

[R]eplace: Delete existing sources and download new ones.

[B]ackup: Backup existing sources to a timestamped directory and download new ones.

### Published paths
- `<source-root>/kernel/kernel-jammy-src`
- `<source-root>/nvidia/nvidia-oot`
- `<source-root>/nvidia/nvdisplay`

When `--download-scope all` is used, the full synced source tree is also mirrored to:
- `<source-root>/source_sync_all`

## Notes
The script requires sudo privileges and will prompt for a password if necessary.

The script resolves candidate tags from `/etc/nv_tegra_release` and stops with an error if no candidate exists remotely on required repos.

All actions are logged to a timestamped file in the ./logs directory (e.g., ./logs/get_kernel_sources_YYYYMMDD_HHMMSS.log).



