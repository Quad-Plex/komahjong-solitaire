#!/usr/bin/env bash
#
# Install or update the mahjong.koplugin on a Kindle.
#
# Two transport paths are supported, and the script always tries them in
# this order:
#
#   1. SSH — preferred. A SSH server runs on the Kindle at root@192.168.2.213
#      (login: root, empty password). Files are pushed with rsync over ssh to
#      /mnt/us/koreader/plugins. The running KOReader is stopped first (over
#      SSH) so state saves cleanly and the new plugin loads on restart.
#
#   2. USB mass-storage (fallback when SSH is unreachable). The Kindle is
#      plugged into Windows as drive D:, which WSL exposes under /mnt/d. The
#      plugin is synced into /mnt/d/koreader/plugins.
#
# Usage:
#   ./install_plugin.sh            # install/update (leave the device mounted)
#   ./install_plugin.sh --unmount  # USB path only: install/update, then unmount D:
#
# After installing, fully restart KOReader on the Kindle (plugins load at
# startup) and open the menu: Tools -> Mahjong Solitaire. With the SSH path
# this script stops KOReader before syncing and relaunches it afterwards, so
# no manual restart is needed. The USB path leaves KOReader running; restart
# it manually.
# Requires sshpass (only for the SSH path): `sudo apt-get install sshpass`.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SRC="$REPO_DIR/mahjong.koplugin"

# --- SSH transport settings -----------------------------------------------
SSH_HOST="192.168.2.213"
SSH_USER="root"
SSH_PASS=""
SSH_DEST_KOREADER="/mnt/us/koreader"
SSH_PLUGINS_DIR="$SSH_DEST_KOREADER/plugins"
SSH_PLUGIN_DEST="$SSH_PLUGINS_DIR/mahjong.koplugin"
# The Kindle's ssh server has an empty root password, so we need sshpass.
# Use `-e` (password from $SSHPASS) so an empty password never becomes a
# word that gets re-split. Disable host-key checking for this private device.
export SSHPASS="$SSH_PASS"
SSH_OPTS=(-o ConnectTimeout=6 -o StrictHostKeyChecking=no -o UserKnownHostsFile="$HOME/.ssh/kindle_known_hosts" -o PreferredAuthentications=password -o PubkeyAuthentication=no -o KbdInteractiveAuthentication=no)
SSH_CMD=(sshpass -e ssh "${SSH_OPTS[@]}" "$SSH_USER@$SSH_HOST")

# --- USB mass-storage settings (fallback) ---------------------------------
KINDLE_MOUNT="/mnt/d"
KINDLE_PLUGINS_DIR="$KINDLE_MOUNT/koreader/plugins"
KINDLE_PLUGIN_DEST="$KINDLE_PLUGINS_DIR/mahjong.koplugin"
DRIVE_LABEL='D:'

UNMOUNT_AFTER=false
if [[ "${1:-}" == "--unmount" ]]; then
    UNMOUNT_AFTER=true
fi

echo "==> Mahjong plugin install/update"
echo "    source : $PLUGIN_SRC"

if [[ ! -d "$PLUGIN_SRC" ]]; then
    echo "ERROR: plugin source not found at $PLUGIN_SRC" >&2
    exit 1
fi

verify_copy() {
    local src="$1" dst="$2"
    if diff -r "$src" "$dst" >/dev/null; then
        echo "==> OK: plugin files identical on device"
    else
        echo "ERROR: copied files differ from source!" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Method 1: push over SSH (preferred). Also stops the running KOReader.
# ---------------------------------------------------------------------------
try_ssh() {
    echo "==> Trying SSH transport to $SSH_USER@$SSH_HOST ..."
    if ! "${SSH_CMD[@]}" 'true' >/dev/null 2>&1; then
        echo "    SSH not reachable; falling back to USB mount."
        return 1
    fi

    # Resolve the koreader path on the device. Note: busybox readlink has no
    # -m, so just test the expected path (Dropbear/sshd on a Kindle always
    # sees /mnt/us).
    local remote_koreader="$SSH_DEST_KOREADER"
    if ! "${SSH_CMD[@]}" "test -d '$remote_koreader'" 2>/dev/null; then
        echo "ERROR: remote KOReader dir not found at $remote_koreader." >&2
        echo "       Is this a jailbroken Kindle with KOReader installed?" >&2
        return 1
    fi
    local remote_plugins="$remote_koreader/plugins"
    local remote_dest="$remote_plugins/mahjong.koplugin"

    if ! "${SSH_CMD[@]}" "test -d '$remote_plugins'" 2>/dev/null; then
        echo "ERROR: remote KOReader plugins dir not found at $remote_plugins." >&2
        echo "       Is this a jailbroken Kindle with KOReader installed?" >&2
        return 1
    fi

    # Stop the running KOReader instance before syncing, so stale files are
    # not held open and it saves state cleanly. SIGTERM to the reader.lua UI
    # process gives KOReader a chance to flush state (SIGKILL would lose it).
    echo "==> Stopping running KOReader instance"
    "${SSH_CMD[@]}" \
        "pkill -TERM reader.lua 2>/dev/null; " \
        "pkill -TERM koreader.sh 2>/dev/null; " \
        "sleep 1; pkill -KILL -f reader.lua 2>/dev/null; true" \
        >/dev/null 2>&1 || true

    echo "==> Syncing plugin to $remote_dest"
    "${SSH_CMD[@]}" "mkdir -p '$remote_dest'"
    local ssh_e
    ssh_e="sshpass -e ssh ${SSH_OPTS[*]}"
    if ! rsync -rt --delete -e "$ssh_e" \
            "$PLUGIN_SRC/" "$SSH_USER@$SSH_HOST:$remote_dest/"; then
        echo "ERROR: rsync over SSH failed." >&2
        return 1
    fi

    # Verify the copy: rsync checksum dry-run reports nothing when the trees
    # are identical. This needs no extra tooling on the (busybox) device.
    if rsync -rcn --delete -e "$ssh_e" \
            "$PLUGIN_SRC/" "$SSH_USER@$SSH_HOST:$remote_dest/" 2>/dev/null | head -1 | grep -q .; then
        echo "ERROR: copied files differ from source!" >&2
        return 1
    fi
    echo "==> OK: plugin files identical on device"

    # Relaunch KOReader so the freshly-installed plugin is loaded. The
    # koreader.sh script must run from /mnt/us/koreader; launch it in a
    # detached subshell so it survives this SSH session ending. BusyBox has
    # no nohup, so `(cmd &)` inside the remote command is the way.
    echo "==> Restarting KOReader"
    "${SSH_CMD[@]}" \
        "cd $remote_koreader && (./koreader.sh >/var/tmp/koreader.log 2>&1 &); true" \
        >/dev/null 2>&1

    echo
    echo "Installed over SSH and KOReader relaunched."
    echo "Open the menu: Tools -> Mahjong Solitaire."
    return 0
}

# ---------------------------------------------------------------------------
# Method 2: USB mass-storage copy (fallback if SSH is unreachable).
# ---------------------------------------------------------------------------
usb_copy() {
    # 0. Pre-flight: does Windows actually see the device as D: ?
    if command -v powershell.exe >/dev/null 2>&1; then
        if ! powershell.exe -NoProfile -Command "if (Test-Path 'D:\\') { 'TRUE' } else { 'FALSE' }" 2>/dev/null | grep -qi true; then
            echo "ERROR: Windows does not see a D: drive." >&2
            echo "       Connect the Kindle and make sure it is mounted as D:" >&2
            echo "       (it must be in USB mass-storage mode, not charging only)." >&2
            return 1
        fi
    fi

    # 1. Make sure the device is mounted and accessible.
    is_mounted() { grep -q " $KINDLE_MOUNT " /proc/mounts 2>/dev/null; }
    is_accessible() { ls "$KINDLE_MOUNT" >/dev/null 2>&1; }
    mount_device() {
        sudo mkdir -p "$KINDLE_MOUNT" 2>/dev/null || true
        if sudo mount -t drvfs "$DRIVE_LABEL" "$KINDLE_MOUNT" 2>/dev/null; then
            return 0
        fi
        sudo umount "$KINDLE_MOUNT" 2>/dev/null || true
        sudo mount -t drvfs "$DRIVE_LABEL" "$KINDLE_MOUNT" 2>/dev/null
    }

    if ! is_mounted || ! is_accessible; then
        if is_mounted && ! is_accessible; then
            sudo umount "$KINDLE_MOUNT" 2>/dev/null || true
        fi
        echo "==> Device not mounted; mounting $DRIVE_LABEL"
        if ! mount_device; then
            echo "ERROR: could not mount $DRIVE_LABEL at $KINDLE_MOUNT." >&2
            echo "       Is the Kindle connected and assigned drive letter D:?" >&2
            return 1
        fi
    fi

    if [[ ! -d "$KINDLE_PLUGINS_DIR" ]]; then
        echo "ERROR: KOReader plugins dir not found at $KINDLE_PLUGINS_DIR." >&2
        echo "       Is this a jailbroken Kindle with KOReader installed?" >&2
        return 1
    fi

    # 2. Sync the plugin dir (mirrors: also removes stale files). FAT16/32 has
    #    no Unix perms/groups, so do NOT use -a (that fails on ownership).
    echo "==> Syncing plugin to $KINDLE_PLUGIN_DEST"
    mkdir -p "$KINDLE_PLUGIN_DEST"
    rsync -r --delete "$PLUGIN_SRC/" "$KINDLE_PLUGIN_DEST/"

    # 3. Verify the copy is identical to the source.
    verify_copy "$PLUGIN_SRC" "$KINDLE_PLUGIN_DEST" || return 1

    echo
    echo "Installed. On the Kindle, fully restart KOReader, then open"
    echo "the menu: Tools -> Mahjong Solitaire."

    if $UNMOUNT_AFTER; then
        echo "==> Unmounting $KINDLE_MOUNT"
        sudo umount "$KINDLE_MOUNT"
    fi
    return 0
}

if try_ssh; then
    exit 0
fi

echo "==> Falling back to USB mass-storage copy."
usb_copy