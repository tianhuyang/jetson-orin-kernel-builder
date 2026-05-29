# Kernel Config Preset Script

## Overview

`config.sh` applies a preset of routing and traffic-control options to the active kernel `.config` in your source tree.

Enabled symbols:

- `CONFIG_IP_ADVANCED_ROUTER`
- `CONFIG_IP_MULTIPLE_TABLES`
- `CONFIG_NET_SCH_HTB`
- `CONFIG_NET_SCH_TBF`
- `CONFIG_NET_SCH_CAKE`
- `CONFIG_NET_ACT_POLICE`
- `CONFIG_NET_CLS_U32`
- `CONFIG_NET_CLS_MATCHALL`

By default, it also runs `make olddefconfig` to resolve dependencies.

## Usage

```bash
./scripts/config.sh [options]
```

## Options

- `-d, --directory <path>`: Kernel source path (default: `/usr/src/kernel/kernel-jammy-src`)
- `--no-olddefconfig`: Skip `make olddefconfig`
- `-h, --help`: Show help

## Example

```bash
./scripts/config.sh
```

Custom kernel source path:

```bash
./scripts/config.sh -d /usr/src/kernel/kernel-jammy-src
```

Apply only symbol changes and skip dependency refresh:

```bash
./scripts/config.sh --no-olddefconfig
```

## Notes

- The script expects a valid `.config` and `scripts/config` in the selected kernel source tree.
- If `JETSON_PASS` is exported, the script can use it for non-interactive sudo.
- After changing config options, rebuild kernel and modules before deployment.

