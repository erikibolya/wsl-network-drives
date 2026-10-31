#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

systemctl disable --now mount-network-drives.timer mount-network-drives.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/mount-network-drives.service
rm -f /etc/systemd/system/mount-network-drives.timer
rm -f /usr/local/bin/mount-network-drives
systemctl daemon-reload

echo "Removed mount-network-drives."
echo "Existing mounts at /mnt/<letter> and links under /mnt/user were left in place."
