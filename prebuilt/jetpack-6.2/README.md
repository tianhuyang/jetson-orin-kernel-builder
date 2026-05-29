# Prebuilt Modules

This directory contains prebuilt modules for Jetson Linux 36.4.3 (JetPack 6.2).
These binaries are provided as a convenience for systems where a given in-tree module is not enabled by default.

- Expected `vermagic`: `5.15.148-tegra`
- Each module archive includes:
  - License file (for Linux in-tree modules this is typically GPL-2.0)
  - `README.md` with module-specific notes
  - Kernel module artifact(s)
  - Install helper script

Each archive has a matching SHA-256 checksum file.

Verify checksums:

```bash
sha256sum -c *.sha256
```

Available modules (named by kernel config symbol):

- `USB_SERIAL_CH341` - Driver for CH341-based USB serial adapters.
- `IP_NF_RAW` - Netfilter raw table support before standard iptables chains.


