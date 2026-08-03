#!/usr/bin/env bash
#
# Install or update the mahjong.koplugin on a Kindle connected to this PC.
#
# This machine runs WSL (Windows Subsystem for Linux). A Kindle plugged into
# Windows shows up as drive D:, which WSL exposes under /mnt/d. The plugin is
# synced into KOReader's plugins directory on the device:
#
#   /mnt/d/koreader/plugins/mahjong.koplugin
#
# Usage:
#   ./install_plugin.sh            # install/update (leave the device mounted)
#   ./install_plugin.sh --unmount  # install/update, then unmount D:
#
# After copying, fully restart KOReader on the Kindle (plugins load at startup)
# and look under the menu: Tools -> Mahjong Solitaire.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SRC="$REPO_DIR/mahjong.koplugin"
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

# 0. Pre-flight: does Windows actually see the device as D: ?
if command -v powershell.exe >/dev/null 2>&1; then
    if ! powershell.exe -NoProfile -Command "if (Test-Path 'D:\\') { 'TRUE' } else { 'FALSE' }" 2>/dev/null | grep -qi true; then
        echo "ERROR: Windows does not see a D: drive." >&2
        echo "       Connect the Kindle and make sure it is mounted as D:" >&2
        echo "       (it must be in USB mass-storage mode, not charging only)." >&2
        exit 1
    fi
fi

# 1. Make sure the device is mounted and accessible (mount D: if needed).
#    Handles: not mounted, mounted but stale, and disconnected.
is_mounted() {
    grep -q " $KINDLE_MOUNT " /proc/mounts 2>/dev/null
}
is_accessible() {
    ls "$KINDLE_MOUNT" >/dev/null 2>&1
}

mount_device() {
    sudo mkdir -p "$KINDLE_MOUNT" 2>/dev/null || true
    if sudo mount -t drvfs "$DRIVE_LABEL" "$KINDLE_MOUNT" 2>/dev/null; then
        return 0
    fi
    sudo umount "$KINDLE_MOUNT" 2>/dev/null || true
    if sudo mount -t drvfs "$DRIVE_LABEL" "$KINDLE_MOUNT" 2>/dev/null; then
        return 0
    fi
    return 1
}

if ! is_mounted || ! is_accessible; then
    if is_mounted && ! is_accessible; then
        sudo umount "$KINDLE_MOUNT" 2>/dev/null || true
    fi
    echo "==> Device not mounted; mounting $DRIVE_LABEL"
    if ! mount_device; then
        echo "ERROR: could not mount $DRIVE_LABEL at $KINDLE_MOUNT." >&2
        echo "       Is the Kindle connected and assigned drive letter D:?" >&2
        exit 1
    fi
fi

if [[ ! -d "$KINDLE_PLUGINS_DIR" ]]; then
    echo "ERROR: KOReader plugins dir not found at $KINDLE_PLUGINS_DIR." >&2
    echo "       Is this a jailbroken Kindle with KOReader installed?" >&2
    exit 1
fi

# 2. Sync the plugin directory (mirrors: also removes stale files).
#    The Kindle's FAT filesystem has no Unix perms/groups, so do NOT use -a
#    (that would try to preserve them and fail with "Operation not permitted").
echo "==> Syncing plugin to $KINDLE_PLUGIN_DEST"
mkdir -p "$KINDLE_PLUGIN_DEST"
rsync -r --delete "$PLUGIN_SRC/" "$KINDLE_PLUGIN_DEST/"

# 3. Verify the copy is identical to the source.
if diff -r "$PLUGIN_SRC" "$KINDLE_PLUGIN_DEST" >/dev/null; then
    echo "==> OK: plugin files identical on device"
else
    echo "ERROR: copied files differ from source!" >&2
    exit 1
fi

echo
echo "Installed. On the Kindle, fully restart KOReader, then open"
echo "the menu: Tools -> Mahjong Solitaire."

if $UNMOUNT_AFTER; then
    echo "==> Unmounting $KINDLE_MOUNT"
    sudo umount "$KINDLE_MOUNT"
fi
