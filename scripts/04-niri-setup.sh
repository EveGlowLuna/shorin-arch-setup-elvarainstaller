#!/bin/bash

# ==============================================================================
# 04-niri-setup.sh - Niri Desktop (Automated Version)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

check_root

log "==============================================="
log "Niri Desktop Setup"
log "==============================================="

# 读取用户信息
detect_target_user

# --- 设置临时sudo权限 ---
grant_nopasswd_sudo "$TARGET_USER"
trap 'revoke_nopasswd_sudo "$TARGET_USER"' EXIT INT TERM

# --- Step 1: 安装Meta包 ---
echo "[$(date '+%H:%M:%S')] INFO: Step 1/3 - Install Environment & Dotfiles"

AUR_HELPER="paru"
CORE_PKG="shorin-niri-git"
PRE_PKGS="xdg-desktop-portal-gnome"

log "Generating verify list for pre-requisites..."
echo "$PRE_PKGS" | tr ' ' '\n' >> "$VERIFY_LIST"

log "Installing pre-requisites explicitly..."
if ! as_user "$AUR_HELPER" -S --noconfirm --needed $PRE_PKGS; then
    critical_failure_handler "Failed to install pre-requisites: $PRE_PKGS"
fi



echo "[$(date '+%H:%M:%S')] INFO: Installing $CORE_PKG via AUR..."
if ! as_user "$AUR_HELPER" -S --noconfirm --needed "$CORE_PKG"; then
    echo "[$(date '+%H:%M:%S')] ERROR: Failed to install '$CORE_PKG' from AUR"
    exit 1
fi

echo "[$(date '+%H:%M:%S')] INFO: Running shorinniri initialization..."
as_user shorinniri init

# --- Step 2: 部署静态资源 ---
echo "[$(date '+%H:%M:%S')] INFO: Step 2/3 - Static Resources"

echo "[$(date '+%H:%M:%S')] INFO: Deploying wallpapers..."
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"
as_user mkdir -p "$WALLPAPER_DIR"
if [ -d "/usr/share/backgrounds/gnome" ]; then
    cp -rf "/usr/share/backgrounds/gnome/." "$WALLPAPER_DIR/"
elif [ -d "/usr/share/backgrounds" ]; then
    cp -rf "/usr/share/backgrounds/." "$WALLPAPER_DIR/"
fi
chown -R "$TARGET_USER:" "$WALLPAPER_DIR"
echo "[$(date '+%H:%M:%S')] OK: Wallpapers deployed"

# --- Step 3: 清理和引导配置 ---
echo "[$(date '+%H:%M:%S')] INFO: Step 3/3 - Cleanup & Boot Configuration"

echo "[$(date '+%H:%M:%S')] INFO: Cleaning up legacy TTY autologin configs..."

# 检测显示管理器冲突
SKIP_DM=false
KNOWN_DMS=("lemurs" "ly" "gdm" "lightdm" "lxdm" "plasma-login-manager" "sddm" "greetd")

for dm in "${KNOWN_DMS[@]}"; do
    if pacman -Q "$dm" &>/dev/null; then
        SKIP_DM=true
        echo "[$(date '+%H:%M:%S')] INFO: Display manager conflict detected: $dm"
        break
    fi
done

if [ "$SKIP_DM" = true ]; then
    echo "[$(date '+%H:%M:%S')] WARN: Display manager setup skipped due to conflict"
else
    echo "[$(date '+%H:%M:%S')] INFO: Installing ly display manager..."
    pacman -S --noconfirm --needed ly
    systemctl enable ly@tty1
    echo "[$(date '+%H:%M:%S')] OK: ly display manager configured"
fi

revoke_nopasswd_sudo "$TARGET_USER"
echo "[$(date '+%H:%M:%S')] OK: Module 04 completed successfully. Shorin Niri is ready!"
