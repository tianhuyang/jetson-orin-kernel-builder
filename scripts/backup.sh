#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR=${1:-/var/backups/kernel_backup}

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

quick_backup() {
  local krel="$1"
  local backup_root="$2"
  local initrd_img="/boot/initrd.img-${krel}"
  local tmp_script
  sudo_run mkdir -p "$backup_root"
  sudo_run cp -a /boot/Image "$backup_root/Image.bak"
  sudo_run cp -a /boot/extlinux/extlinux.conf "$backup_root/extlinux.conf.bak"
  if [[ -f /boot/initrd ]]; then
    sudo_run cp -a /boot/initrd "$backup_root/initrd.bak"
  fi
  if [[ -f "$initrd_img" ]]; then
    sudo_run cp -a "$initrd_img" "$backup_root/initrd.img-${krel}.bak"
  fi
  # Capture existing module tree for fast rollback of the running kernel only.
  sudo_run rsync -a "/lib/modules/${krel}/" "$backup_root/modules-${krel}/"
  tmp_script="$(mktemp)"
  cat >"$tmp_script" <<EOF2
#!/usr/bin/env bash
set -xeuo pipefail
KREL="${krel}"
BACKUP_DIR="${backup_root}"
BACKUP_IMAGE="\${BACKUP_DIR}/Image.bak"
if [[ "\${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo \$0"
  exit 1
fi
if [[ ! -f "\$BACKUP_IMAGE" ]]; then
  echo "ERROR: backup image not found at \$BACKUP_IMAGE" >&2
  exit 1
fi

cp -a "\$BACKUP_IMAGE" /boot/Image
sync
echo "Kernel Image restored from \$BACKUP_IMAGE. "

rsync -a --delete "\${BACKUP_DIR}/modules-\${KREL}/" "/lib/modules/\${KREL}/"
cp -a "\${BACKUP_DIR}/extlinux.conf.bak" /boot/extlinux/extlinux.conf
if [[ -f "\${BACKUP_DIR}/initrd.bak" ]]; then
  cp -a "\${BACKUP_DIR}/initrd.bak" /boot/initrd
fi
if [[ -f "\${BACKUP_DIR}/initrd.img-\${KREL}.bak" ]]; then
  cp -a "\${BACKUP_DIR}/initrd.img-\${KREL}.bak" "/boot/initrd.img-\${KREL}"
fi
depmod -a "\${KREL}"
nv-update-initrd
echo "Rollback complete for \${KREL}."
EOF2
  sudo_run install -m 0755 "$tmp_script" "$backup_root/quick_rollback.sh"
  rm -f "$tmp_script"
}
KREL="$(uname -r)"
echo "Creating quick rollback bundle for $KREL at ${BACKUP_DIR} "
quick_backup "$KREL" "$BACKUP_DIR"
