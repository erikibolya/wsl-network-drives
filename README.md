# wsl-network-drives

Automatically discover and mount **all Windows mapped network drives** inside WSL 2.

WSL automounts local Windows volumes (`C:`, `D:`, ...) under `/mnt/c`, `/mnt/d`, but it does not mount per-user network mappings created with `net use` or Explorer. This repo provides a small root script plus a systemd service and timer that discover those mappings through Windows PowerShell and mount them with `drvfs`.

## What it does

- Asks Windows for all drives with `DriveType=4` (network drives).
- Mounts each one at `/mnt/<letter>` (for example `Z:` -> `/mnt/z`).
- Creates compatibility links `/mnt/user/<share>` -> `/mnt/<letter>`.
- Skips `\\wsl.localhost` and `\\wsl$` so WSL does not mount itself.
- Retries every 5 minutes, so drives that reconnect after WSL starts are picked up.
- Has no hardcoded drive letters or share names.

## Requirements

- WSL 2 with **systemd enabled**:

  ```ini
  # /etc/wsl.conf
  [boot]
  systemd=true
  ```

  Apply it with `wsl --shutdown`, then reopen WSL.

- Windows PowerShell interop available at `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe`.
- Network drives mapped in the same Windows user account that starts WSL.

## Install

```bash
git clone https://github.com/erikibolya/wsl-network-drives.git
cd wsl-network-drives
sudo ./install.sh
```

If `/etc/fstab` still contains hardcoded `drvfs` network mounts, run:

```bash
sudo ./install.sh --clean-fstab
```

That comments out the old `drvfs` lines and creates a timestamped backup. Existing mounts stay active until you restart WSL:

```bash
wsl --shutdown
```

## Verify

```bash
findmnt -rn -o TARGET,SOURCE | grep '^/mnt/[a-z] '
ls -la /mnt/user
journalctl -u mount-network-drives -n 50
systemctl list-timers mount-network-drives.timer
```

Example:

```text
/mnt/h H:
/mnt/z Z:

/mnt/user/ProgramDataHDD -> /mnt/h
/mnt/user/Development    -> /mnt/z
```

## Configuration

The script accepts these environment variables:

| Variable     | Default                         | Meaning                              |
|--------------|---------------------------------|--------------------------------------|
| `WSL_USER`   | first user with UID 1000        | owner for the mounted files          |
| `MOUNT_ROOT` | `/mnt`                          | where drive letters are mounted      |
| `LINK_ROOT`  | `/mnt/user`                     | where compatibility links are placed |

Override them with a systemd drop-in:

```bash
sudo systemctl edit mount-network-drives.service
```

```ini
[Service]
Environment=WSL_USER=erik
```

Then restart the service:

```bash
sudo systemctl restart mount-network-drives.service
```

## How it works

The discovery script runs:

```powershell
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=4"
```

and reads `DeviceID` (`Z:`) and `ProviderName` (`\\HOLLY\Development`). It then runs:

```bash
mount -t drvfs -o defaults,uid=1000,gid=1000 'Z:' /mnt/z
```

The systemd timer runs the script at WSL boot and every 5 minutes. Failed mounts are retried, so a share that is not ready when WSL starts is mounted later.

## Persistence and caveats

- The script and systemd units live inside the WSL distro, so they survive WSL and PC restarts.
- Windows mappings are persistent in `HKCU\Network`, so Windows reconnects them at logon.
- If a mapping is missing or disconnected, the mount fails and the timer retries every 5 minutes.
- WSL must be running for the mounts and timer to exist. This repo does not start WSL at boot.
- Only network drives (`DriveType=4`) are handled. Local volumes are left to WSL automount, and `subst` drives are not included.
- If migrating from `/etc/fstab`, restart WSL after `--clean-fstab` so the old mount disappears and the compatibility link can be created.

## Uninstall

```bash
sudo ./uninstall.sh
```

Existing mounts under `/mnt/<letter>` and links under `/mnt/user` are left in place.

## License

MIT
