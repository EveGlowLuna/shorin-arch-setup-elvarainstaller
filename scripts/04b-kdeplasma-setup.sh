#!/bin/bash

# ==============================================================================
# 04b-kdeplasma-setup.sh - KDE Plasma Setup (Automated Version)
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
log "KDE Plasma Environment"
log "==============================================="

# 读取用户信息
detect_target_user

# --- 检测显示管理器冲突 ---
SKIP_DM=false
KNOWN_DMS=("lemurs" "ly" "gdm" "lightdm" "lxdm" "plasma-login-manager" "sddm" "greetd")

for dm in "${KNOWN_DMS[@]}"; do
    if pacman -Q "$dm" &>/dev/null; then
        SKIP_DM=true
        echo "[$(date '+%H:%M:%S')] INFO: Display manager conflict detected: $dm"
        break
    fi
done

# --- Step 1: 安装KDE Plasma核心 ---
echo "[$(date '+%H:%M:%S')] INFO: Step 1/5 - Plasma Core"

echo "[$(date '+%H:%M:%S')] INFO: Installing KDE Plasma Meta & Apps..."
KDE_PKGS="plasma-meta konsole dolphin kate firefox qt6-multimedia-ffmpeg pipewire-jack plasma-login-manager"
pacman -S --noconfirm --needed $KDE_PKGS
echo "[$(date '+%H:%M:%S')] OK: KDE Plasma installed"

# --- Step 2: 软件商店和网络配置 ---
echo "[$(date '+%H:%M:%S')] INFO: Step 2/5 - Software Store & Network"

echo "[$(date '+%H:%M:%S')] INFO: Configuring Discover & Flatpak..."
FLATPAK_PKGS="flatpak flatpak-kcm"
pacman -S --noconfirm --needed $FLATPAK_PKGS

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# --- 设置临时sudo权限 ---
grant_nopasswd_sudo "$TARGET_USER"
trap 'revoke_nopasswd_sudo "$TARGET_USER"' EXIT INT TERM

# --- Step 3: 安装依赖 ---
echo "[$(date '+%H:%M:%S')] INFO: Step 3/5 - KDE Dependencies"

LIST_FILE="$PARENT_DIR/kde-applist.txt"

if [ -f "$LIST_FILE" ] && grep -q -vE "^\s*#|^\s*$" "$LIST_FILE"; then
    REPO_APPS=()
    AUR_APPS=()

    while IFS= read -r line; do
        raw_pkg=$(echo "$line" | cut -f1 -d$'\t' | xargs)
        [[ -z "$raw_pkg" ]] && continue

        [ "$raw_pkg" == "imagemagic" ] && raw_pkg="imagemagick"

        if [[ "$raw_pkg" == AUR:* ]]; then
            clean_name="${raw_pkg#AUR:}"
            AUR_APPS+=("$clean_name")
        elif [[ "$raw_pkg" == *"-git" ]]; then
            AUR_APPS+=("$raw_pkg")
        else
            REPO_APPS+=("$raw_pkg")
        fi
    done < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE")

    # 安装官方仓库软件
    if [ ${#REPO_APPS[@]} -gt 0 ]; then
        echo "[$(date '+%H:%M:%S')] INFO: Installing ${#REPO_APPS[@]} repo packages..."
        REPO_QUEUE=()
        for pkg in "${REPO_APPS[@]}"; do
            if ! pacman -Qi "$pkg" &>/dev/null; then
                REPO_QUEUE+=("$pkg")
            fi
        done
        if [ ${#REPO_QUEUE[@]} -gt 0 ]; then
            as_user yay -S --noconfirm --needed --answerdiff=None --answerclean=None "${REPO_QUEUE[@]}"
        fi
    fi

    # 安装AUR软件
    if [ ${#AUR_APPS[@]} -gt 0 ]; then
        echo "[$(date '+%H:%M:%S')] INFO: Installing ${#AUR_APPS[@]} AUR packages..."
        for aur_pkg in "${AUR_APPS[@]}"; do
            if ! pacman -Qi "$aur_pkg" &>/dev/null; then
                if ! as_user yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$aur_pkg"; then
                    echo "[$(date '+%H:%M:%S')] WARN: Failed to install $aur_pkg"
                fi
            fi
        done
    fi
else
    echo "[$(date '+%H:%M:%S')] WARN: kde-applist.txt not found or empty"
fi

# --- Step 4: 部署Dotfiles ---
echo "[$(date '+%H:%M:%S')] INFO: Step 4/5 - KDE Config Deployment"

DOTFILES_SOURCE="$PARENT_DIR/kde-dotfiles"

if [ -d "$DOTFILES_SOURCE" ]; then
    echo "[$(date '+%H:%M:%S')] INFO: Deploying KDE configurations..."
    
    # 备份现有配置
    BACKUP_NAME="config_backup_kde_$(date +%s).tar.gz"
    if [ -d "$HOME_DIR/.config" ]; then
        as_user tar -czf "$HOME_DIR/$BACKUP_NAME" -C "$HOME_DIR" .config
    fi
    
    # 复制配置文件
    if [ -d "$DOTFILES_SOURCE/.config" ]; then
        mkdir -p "$HOME_DIR/.config"
        cp -rf "$DOTFILES_SOURCE/.config/"* "$HOME_DIR/.config/" 2>/dev/null || true
        cp -rf "$DOTFILES_SOURCE/.config/." "$HOME_DIR/.config/" 2>/dev/null || true
        chown -R "$TARGET_USER" "$HOME_DIR/.config"
    fi

    if [ -d "$DOTFILES_SOURCE/.local" ]; then
        mkdir -p "$HOME_DIR/.local"
        cp -rf "$DOTFILES_SOURCE/.local/"* "$HOME_DIR/.local/" 2>/dev/null || true
        cp -rf "$DOTFILES_SOURCE/.local/." "$HOME_DIR/.local/" 2>/dev/null || true
        chown -R "$TARGET_USER" "$HOME_DIR/.local"
    fi
    
    echo "[$(date '+%H:%M:%S')] OK: KDE Dotfiles applied"
else
    echo "[$(date '+%H:%M:%S')] WARN: Folder 'kde-dotfiles' not found"
fi

# --- Step 5: 启用显示管理器 ---
echo "[$(date '+%H:%M:%S')] INFO: Step 5/5 - Enable Display Manager"

if [ "$SKIP_DM" = true ]; then
    echo "[$(date '+%H:%M:%S')] INFO: Display Manager setup skipped"
else
    systemctl enable plasmalogin
    echo "[$(date '+%H:%M:%S')] OK: Plasma login manager enabled"
fi

# --- 清理 ---
revoke_nopasswd_sudo "$TARGET_USER"
echo "[$(date '+%H:%M:%S')] OK: Module 06 completed"
