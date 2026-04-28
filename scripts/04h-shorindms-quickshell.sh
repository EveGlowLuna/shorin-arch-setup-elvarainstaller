#!/bin/bash

# ==============================================================================
# 04-dms-setup.sh - DMS Desktop (Pre-install separated + Pre-Verify)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found in $SCRIPT_DIR."
    exit 1
fi

check_root
VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"

# --- Identify User & DM Check ---
log "Identifying target user..."
detect_target_user


if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
    error "Target user invalid or home directory does not exist."
    exit 1
fi

info_kv "Target User" "$TARGET_USER"
check_dm_conflict
log "DM Check result $SKIP_DM"
critical_failure_handler() {
    local failed_reason="$1"
    trap - ERR
    echo -e "\n\033[0;31m[CRITICAL FAILURE] $failed_reason\033[0m\n"
    exit 1
}
trap 'critical_failure_handler "Script Error at Line $LINENO"' ERR

# --- Temporary Sudo Privileges ---
log "Granting temporary sudo privileges..."
grant_nopasswd_sudo "$TARGET_USER"
trap 'revoke_nopasswd_sudo "$TARGET_USER"' EXIT INT TERM

AUR_HELPER="paru"

# ==============================================================================
# STEP 1: Pre-requisites Installation
# ==============================================================================
section "Shorin DMS" "Installing Pre-requisites"

PRE_PKGS="quickshell-git vulkan-headers xdg-desktop-portal-gnome"

log "Generating verify list for pre-requisites..."
echo "$PRE_PKGS" | tr ' ' '\n' >> "$VERIFY_LIST"

log "Installing pre-requisites explicitly..."
if ! as_user "$AUR_HELPER" -S --noconfirm --needed $PRE_PKGS; then
    critical_failure_handler "Failed to install pre-requisites: $PRE_PKGS"
fi

# ==============================================================================
# STEP 2: Core Meta Environment
# ==============================================================================
section "Shorin DMS" "Installing Core Environment"
CORE_PKG="shorin-dms-niri-git"

log "Fetching dependency list from AUR for verification..."
echo "$CORE_PKG" >> "$VERIFY_LIST"
# 使用 -Si 查询远程信息，提前写入清单 (剥离版本号 <>=)
if as_user "$AUR_HELPER" -Si "$CORE_PKG" &>/dev/null; then
    as_user "$AUR_HELPER" -Si "$CORE_PKG" | grep "^Depends On" | cut -d':' -f2- | tr -s ' ' '\n' | sed -e 's/[<>=].*//g' -e '/^$/d' -e '/None/d' >> "$VERIFY_LIST"
    log "Dependencies added to $VERIFY_LIST."
else
    warn "Could not fetch remote dependency info for $CORE_PKG. Skipping verify list append."
fi

log "Installing $CORE_PKG environment via AUR..."
if ! as_user "$AUR_HELPER" -S --noconfirm --needed "$CORE_PKG"; then
    critical_failure_handler "Failed to install $CORE_PKG"
fi

# ==============================================================================
# STEP 3: Initialize Dotfiles & Environment
# ==============================================================================
log "Initializing User Dotfiles and Environment..."
exe as_user shorindms init

# ==============================================================================
# STEP 4: Static Resources
# ==============================================================================
section "Shorin DMS" "Wallpapers & Tutorials"

log "Deploying wallpapers..."
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"
as_user mkdir -p "$WALLPAPER_DIR"
if [ -d "/usr/share/backgrounds/gnome" ]; then
    force_copy "/usr/share/backgrounds/gnome/." "$WALLPAPER_DIR/"
elif [ -d "/usr/share/backgrounds" ]; then
    force_copy "/usr/share/backgrounds/." "$WALLPAPER_DIR/"
fi
chown -R "$TARGET_USER:" "$WALLPAPER_DIR"

# ==============================================================================
# Finalization & Auto-Login
# ==============================================================================
section "Final" "Auto-Login & Cleanup"


log "Cleaning up legacy TTY autologin configs..."

if [[ "$SKIP_DM" == false ]]; then
    setup_ly
fi

success "Shorin DMS Niri Installation Complete!"