#!/bin/bash

# Copyright (C) 2026 ravindu644 <droidcasts@protonmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

set -e

DEFAULT_PA="$PREFIX/etc/pulse/default.pa"
AAUDIO_LINE="load-module module-aaudio-sink"
ALWAYS_LINE="load-module module-always-sink"
SLES_LINE="load-module module-sles-sink"
CK_LINE="load-module module-console-kit"
SIDLE_LINE="load-module module-suspend-on-idle"

BOLD="\033[1m"
GREEN="\033[1;32m"
CYAN="\033[0;36m"
RESET="\033[0m"

log() {
    echo -e "${GREEN}===> ${BOLD}$*${RESET}\n"
}

detail() {
    echo -e "  ${CYAN}->${RESET} $*"
}

log "Setting up Droidspaces dependencies..."

log "Updating repos and upgrading Termux..."
DEBIAN_FRONTEND=noninteractive pkg update -y -o Dpkg::Options::="--force-confold"
DEBIAN_FRONTEND=noninteractive pkg upgrade -y -o Dpkg::Options::="--force-confold"

log "Installing x11-repo..."
DEBIAN_FRONTEND=noninteractive pkg install -y -o Dpkg::Options::="--force-confold" x11-repo

log "Installing Termux:X11, VirGL and PulseAudio..."
DEBIAN_FRONTEND=noninteractive pkg install -y -o Dpkg::Options::="--force-confold" pulseaudio termux-x11 virglrenderer-android

log "Installing libandroid-stub (OpenSL ES HAL fix)..."
DEBIAN_FRONTEND=noninteractive pkg install -y -o Dpkg::Options::="--force-confold" libandroid-stub

log "Patching $DEFAULT_PA..."

if [ ! -f "$DEFAULT_PA" ]; then
    echo "Error: $DEFAULT_PA not found." >&2
    exit 1
fi

# Comment out module-aaudio-sink (fails on multiple Snapdragon devices due to HAL block)
if grep -q "^${AAUDIO_LINE}" "$DEFAULT_PA"; then
    sed -i "s|^${AAUDIO_LINE}|#${AAUDIO_LINE}|" "$DEFAULT_PA"
    detail "Commented out $AAUDIO_LINE"
fi

# Comment out module-console-kit (no D-Bus system bus on Android, causes futex deadlock)
if grep -q "^${CK_LINE}" "$DEFAULT_PA"; then
    sed -i "s|^${CK_LINE}|#${CK_LINE}|" "$DEFAULT_PA"
    detail "Commented out $CK_LINE"
fi

# Comment out module-suspend-on-idle (causes PA futex deadlock on audio device changes)
if grep -q "^${SIDLE_LINE}" "$DEFAULT_PA"; then
    sed -i "s|^${SIDLE_LINE}|#${SIDLE_LINE}|" "$DEFAULT_PA"
    detail "Commented out $SIDLE_LINE"
fi

# Check if already patched (sles appears before always-sink)
SLES_LINE_NUM=$(grep -n "^${SLES_LINE}$" "$DEFAULT_PA" | head -1 | cut -d: -f1)
ALWAYS_LINE_NUM=$(grep -n "^${ALWAYS_LINE}$" "$DEFAULT_PA" | head -1 | cut -d: -f1)

if [ -n "$SLES_LINE_NUM" ] && [ -n "$ALWAYS_LINE_NUM" ] && [ "$SLES_LINE_NUM" -lt "$ALWAYS_LINE_NUM" ]; then
    detail "default.pa already patched for OpenSL ES, skipping."
else
    sed -i "s|^${ALWAYS_LINE}|${SLES_LINE}\nset-default-sink OpenSL_ES_sink\n${ALWAYS_LINE}|" "$DEFAULT_PA"
    detail "Injected $SLES_LINE and default sink before $ALWAYS_LINE"

    # Remove duplicate sles line at bottom if present
    SLES_COUNT=$(grep -c "^${SLES_LINE}$" "$DEFAULT_PA" || true)
    if [ "$SLES_COUNT" -gt 1 ]; then
        awk "BEGIN{found=0} /^${SLES_LINE}$/{if(found){next}; found=1} {print}" "$DEFAULT_PA" > "$DEFAULT_PA.tmp"
        mv "$DEFAULT_PA.tmp" "$DEFAULT_PA"
        detail "Removed duplicate $SLES_LINE"
    fi
fi

log "All done. Droidspaces audio/display dependencies are ready."
