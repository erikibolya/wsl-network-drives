#!/usr/bin/env bash
# Discover Windows mapped network drives and mount them into WSL.
#
# Intended to run as root from a systemd service. Windows interop still runs as
# the Windows user, so the user's HKCU / SMB mappings are visible.

set -u

PS="${PS:-/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe}"
MOUNT_ROOT="${MOUNT_ROOT:-/mnt}"
LINK_ROOT="${LINK_ROOT:-/mnt/user}"
WSL_USER="${WSL_USER:-$(getent passwd 1000 | cut -d: -f1)}"
WSL_USER="${WSL_USER:-erik}"

log() { printf 'mount-network-drives: %s\n' "$*"; }

[ -d /mnt/c ] || { log '/mnt/c is not mounted; skipping'; exit 0; }
[ -x "$PS" ] || { log 'powershell.exe not found; skipping'; exit 0; }

if id "$WSL_USER" >/dev/null 2>&1; then
  UID_NUM=$(id -u "$WSL_USER")
  GID_NUM=$(id -g "$WSL_USER")
else
  log "user '$WSL_USER' not found; falling back to 1000:1000"
  UID_NUM=1000
  GID_NUM=1000
fi

# DriveType=4 is a network drive. Output is "LETTER|\\SERVER\SHARE".
RAW=$(timeout 20 "$PS" -NoProfile -NonInteractive -Command \
  'Get-CimInstance Win32_LogicalDisk -Filter "DriveType=4" | Sort-Object DeviceID | ForEach-Object { $l = $_.DeviceID.TrimEnd(":"); $r = $_.ProviderName; if ($l -match "^[A-Za-z]$" -and $r) { "$l|$r" } }' \
  2>/dev/null) || {
  log 'drive discovery failed or timed out'
  exit 0
}
LIST=$(printf '%s\n' "$RAW" | tr -d '\r')

mkdir -p "$LINK_ROOT"

while IFS='|' read -r letter remote; do
  [ -n "${letter:-}" ] || continue
  [ -n "${remote:-}" ] || continue

  # Do not mount the \\wsl.localhost share back into WSL (recursive loop).
  case "$remote" in
    *'wsl.localhost'*|*'wsl$'*) continue ;;
  esac
  case "$letter" in
    [A-Za-z]) ;;
    *) log "skipping invalid drive letter: $letter"; continue ;;
  esac

  lower=$(printf '%s' "$letter" | tr '[:upper:]' '[:lower:]')
  mnt="$MOUNT_ROOT/$lower"

  if mountpoint -q "$mnt"; then
    :
  else
    mkdir -p "$mnt"
    if timeout 30 mount -t drvfs -o "defaults,uid=$UID_NUM,gid=$GID_NUM" "${letter}:" "$mnt" 2>/dev/null; then
      log "$letter: mounted $remote at $mnt"
    else
      log "$letter: mount failed ($remote); will retry"
      continue
    fi
  fi

  # Compatibility link: /mnt/user/<share> -> /mnt/<letter>.
  share="${remote//\\//}"
  share="${share##*/}"
  share="${share//[^A-Za-z0-9._-]/_}"
  [ -n "$share" ] || continue
  link="$LINK_ROOT/$share"

  if [ -L "$link" ]; then
    target=$(readlink -f "$link" 2>/dev/null || true)
    if [ "$target" != "$mnt" ]; then
      log "$letter: $link already exists (-> ${target:-?}); not replacing"
    fi
  elif mountpoint -q "$link" 2>/dev/null; then
    log "$letter: $link is an old mountpoint; symlink will be created after the next WSL restart"
  elif [ -e "$link" ]; then
    :
  else
    ln -s "$mnt" "$link" && log "$letter: linked $link -> $mnt"
  fi
done <<< "$LIST"
