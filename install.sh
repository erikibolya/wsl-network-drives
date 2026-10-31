#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CLEAN_FSTAB=0

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh [--clean-fstab]

Installs the mount-network-drives script and its systemd service and timer.

Options:
  --clean-fstab  Comment out existing drvfs lines in /etc/fstab.
                 A timestamped backup is created first.
  -h, --help     Show this help.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --clean-fstab) CLEAN_FSTAB=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

if [ "$(ps -p 1 -o comm=)" != "systemd" ]; then
  echo "systemd is not PID 1 in this WSL distro." >&2
  echo "Add this to /etc/wsl.conf, then run 'wsl --shutdown' and reopen WSL:" >&2
  echo "  [boot]" >&2
  echo "  systemd=true" >&2
  exit 1
fi

if [ ! -x /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe ]; then
  echo "warning: powershell.exe was not found under /mnt/c" >&2
  echo "         make sure Windows interop and /mnt/c are available" >&2
fi

if [ "$CLEAN_FSTAB" -eq 1 ]; then
  backup="/etc/fstab.bak-$(date +%Y%m%d-%H%M%S)"
  cp -a /etc/fstab "$backup"
  sed -i -E 's|^([^#].*[[:space:]]drvfs[[:space:]].*)$|# disabled by wsl-network-drives: \1|' /etc/fstab
  echo "Commented out drvfs lines in /etc/fstab (backup: $backup)"
fi

install -m 0755 "$SCRIPT_DIR/mount-network-drives.sh" /usr/local/bin/mount-network-drives
install -m 0644 "$SCRIPT_DIR/mount-network-drives.service" /etc/systemd/system/mount-network-drives.service
install -m 0644 "$SCRIPT_DIR/mount-network-drives.timer" /etc/systemd/system/mount-network-drives.timer

systemctl daemon-reload
systemctl enable mount-network-drives.service mount-network-drives.timer >/dev/null
systemctl restart mount-network-drives.timer
systemctl start mount-network-drives.service

echo
echo "Installed. Network drives are mounted at /mnt/<letter>."
echo "Compatibility links are created at /mnt/user/<share>."
echo
echo "Logs:  journalctl -u mount-network-drives -n 50"
echo "Timer: systemctl list-timers mount-network-drives.timer"
