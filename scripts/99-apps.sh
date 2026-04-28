#!/bin/bash

# ==============================================================================
# 99-apps.sh - Common Applications (Automated Version)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# 直接读取用户信息，不依赖工具函数库中的detect_target_user
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER}"
HOME_DIR="/home/$TARGET_USER"

echo "[$(date '+%H:%M:%S')] INFO: Target user: $TARGET_USER"

as_user() {
    runuser -u "$TARGET_USER" -- "$@"
}

# ==============================================================================
# 应用安装
# ==============================================================================
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
echo "[$(date '+%H:%M:%S')] INFO: Phase 5 - Common Applications"
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="

# 选择应用列表
if [ "$DESKTOP_ENV" == "kde" ]; then
    LIST_FILENAME="kde-applist.txt"
else
    LIST_FILENAME="common-applist.txt"
fi
LIST_FILE="$PARENT_DIR/$LIST_FILENAME"

REPO_APPS=()
AUR_APPS=()
FLATPAK_APPS=()
FAILED_PACKAGES=()
INSTALL_LAZYVIM=false
LAZYVIM_DEPS=("neovim" "ripgrep" "fd" "ttf-jetbrains-mono-nerd" "git")

if [ ! -f "$LIST_FILE" ]; then
    echo "[$(date '+%H:%M:%S')] WARN: File $LIST_FILENAME not found. Skipping."
    exit 0
fi

if ! grep -q -vE "^\s*#|^\s*$" "$LIST_FILE"; then
    echo "[$(date '+%H:%M:%S')] WARN: App list is empty. Skipping."
    exit 0
fi

# 解析应用列表
echo "[$(date '+%H:%M:%S')] INFO: Processing application list..."

while IFS= read -r line; do
    raw_pkg=$(echo "$line" | cut -f1 -d$'\t' | xargs)
    [[ -z "$raw_pkg" ]] && continue

    if [[ "${raw_pkg,,}" == "lazyvim" ]]; then
        INSTALL_LAZYVIM=true
        REPO_APPS+=("${LAZYVIM_DEPS[@]}")
        echo "[$(date '+%H:%M:%S')] INFO: LazyVim detected, will install dependencies"
        continue
    fi

    if [[ "$raw_pkg" == flatpak:* ]]; then
        clean_name="${raw_pkg#flatpak:}"
        FLATPAK_APPS+=("$clean_name")
    elif [[ "$raw_pkg" == AUR:* ]]; then
        clean_name="${raw_pkg#AUR:}"
        AUR_APPS+=("$clean_name")
    else
        REPO_APPS+=("$raw_pkg")
    fi
done < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE")

echo "[$(date '+%H:%M:%S')] INFO: Scheduled - Repo: ${#REPO_APPS[@]}, AUR: ${#AUR_APPS[@]}, Flatpak: ${#FLATPAK_APPS[@]}"

# --- 设置临时sudo权限 ---
if [ ${#REPO_APPS[@]} -gt 0 ] || [ ${#AUR_APPS[@]} -gt 0 ]; then
    grant_nopasswd_sudo "$TARGET_USER"
    trap 'revoke_nopasswd_sudo "$TARGET_USER"' EXIT INT TERM
    echo "[$(date '+%H:%M:%S')] INFO: Temporary NOPASSWD configured"
fi

# --- 安装官方仓库软件 ---
if [ ${#REPO_APPS[@]} -gt 0 ]; then
    echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
    echo "[$(date '+%H:%M:%S')] INFO: Step 1/3 - Official Repository Packages"
    echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
    
    REPO_QUEUE=()
    for pkg in "${REPO_APPS[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            echo "[$(date '+%H:%M:%S')] INFO: Skipping '$pkg' (Already installed)"
        else
            REPO_QUEUE+=("$pkg")
        fi
    done

    if [ ${#REPO_QUEUE[@]} -gt 0 ]; then
        echo "[$(date '+%H:%M:%S')] INFO: Installing ${#REPO_QUEUE[@]} packages via Pacman/Yay..."
        BATCH_LIST="${REPO_QUEUE[*]}"
        
        if ! as_user yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
            echo "[$(date '+%H:%M:%S')] ERROR: Batch installation failed"
            for pkg in "${REPO_QUEUE[@]}"; do
                FAILED_PACKAGES+=("repo:$pkg")
            done
        else
            echo "[$(date '+%H:%M:%S')] OK: Repo batch installation completed"
        fi
    else
        echo "[$(date '+%H:%M:%S')] INFO: All Repo packages are already installed"
    fi
fi

# --- 安装AUR软件 ---
if [ ${#AUR_APPS[@]} -gt 0 ]; then
    echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
    echo "[$(date '+%H:%M:%S')] INFO: Step 2/3 - AUR Packages"
    echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
    
    for app in "${AUR_APPS[@]}"; do
        if pacman -Qi "$app" &>/dev/null; then
            echo "[$(date '+%H:%M:%S')] INFO: Skipping '$app' (Already installed)"
            continue
        fi

        echo "[$(date '+%H:%M:%S')] INFO: Installing AUR: $app..."
        install_success=false
        max_retries=1
        
        for (( i=0; i<=max_retries; i++ )); do
            if as_user yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "$app"; then
                install_success=true
                echo "[$(date '+%H:%M:%S')] OK: Installed $app"
                break
            else
                echo "[$(date '+%H:%M:%S')] WARN: Attempt $((i+1)) failed for $app"
            fi
        done

        if [ "$install_success" = false ]; then
            echo "[$(date '+%H:%M:%S')] ERROR: Failed to install $app"
            FAILED_PACKAGES+=("aur:$app")
        fi
    done
fi

# --- 安装Flatpak软件 ---
if [ ${#FLATPAK_APPS[@]} -gt 0 ]; then
    echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
    echo "[$(date '+%H:%M:%S')] INFO: Step 3/3 - Flatpak Packages"
    echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
    
    for app in "${FLATPAK_APPS[@]}"; do
        if flatpak info "$app" &>/dev/null; then
            echo "[$(date '+%H:%M:%S')] INFO: Skipping '$app' (Already installed)"
            continue
        fi

        echo "[$(date '+%H:%M:%S')] INFO: Installing Flatpak: $app..."
        if ! flatpak install -y flathub "$app"; then
            echo "[$(date '+%H:%M:%S')] ERROR: Failed to install: $app"
            FAILED_PACKAGES+=("flatpak:$app")
        else
            echo "[$(date '+%H:%M:%S')] OK: Installed $app"
        fi
    done
fi

# --- 后续配置 ---
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
echo "[$(date '+%H:%M:%S')] INFO: Post-Install - System & App Tweaks"
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="

# Virt-Manager配置
if pacman -Qi virt-manager &>/dev/null && ! systemd-detect-virt -q; then
    echo "[$(date '+%H:%M:%S')] INFO: Configuring Virt-Manager..."
    pacman -S --noconfirm --needed qemu-full virt-manager swtpm dnsmasq virt-viewer
    usermod -a -G libvirt "$TARGET_USER"
    usermod -a -G kvm,input "$TARGET_USER"
    systemctl enable --now libvirtd
    sleep 3
    virsh net-start default >/dev/null 2>&1 || true
    virsh net-autostart default >/dev/null 2>&1 || true
    echo "[$(date '+%H:%M:%S')] OK: Virtualization (KVM) configured"
fi

# Wine配置
if command -v wine &>/dev/null; then
    echo "[$(date '+%H:%M:%S')] INFO: Configuring Wine..."
    pacman -S --noconfirm --needed wine wine-gecko wine-mono
    
    WINE_PREFIX="$HOME_DIR/.wine"
    if [ ! -d "$WINE_PREFIX" ]; then
        echo "[$(date '+%H:%M:%S')] INFO: Initializing wine prefix..."
        as_user env WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u
        as_user wineserver -w
    fi
    
    FONT_SRC="$PARENT_DIR/resources/windows-sim-fonts"
    FONT_DEST="$WINE_PREFIX/drive_c/windows/Fonts"
    
    if [ -d "$FONT_SRC" ]; then
        as_user mkdir -p "$FONT_DEST"
        sudo -u "$TARGET_USER" cp -rf "$FONT_SRC"/. "$FONT_DEST/"
        if command -v wineserver &> /dev/null; then
            as_user env WINEPREFIX="$WINE_PREFIX" wineserver -k
        fi
        echo "[$(date '+%H:%M:%S')] OK: Wine fonts installed"
    fi
fi

# Lutris游戏依赖
if command -v lutris &> /dev/null; then
    echo "[$(date '+%H:%M:%S')] INFO: Installing gaming dependencies for Lutris..."
    pacman -S --noconfirm --needed alsa-plugins giflib glfw gst-plugins-base-libs lib32-alsa-plugins lib32-giflib lib32-gst-plugins-base-libs lib32-gtk3 lib32-libjpeg-turbo lib32-libva lib32-mpg123 lib32-openal libjpeg-turbo libva libxslt mpg123 openal ttf-liberation
fi

# Steam语言修复
if [ -f "/usr/share/applications/steam.desktop" ]; then
    if ! grep -q "env LC_CTYPE=zh_CN.UTF-8" "/usr/share/applications/steam.desktop"; then
        sed -i 's|^Exec=/usr/bin/steam|Exec=env LC_CTYPE=zh_CN.UTF-8 /usr/bin/steam|' "/usr/share/applications/steam.desktop"
        sed -i 's|^Exec=steam|Exec=env LC_CTYPE=zh_CN.UTF-8 steam|' "/usr/share/applications/steam.desktop"
        echo "[$(date '+%H:%M:%S')] OK: Patched Native Steam .desktop"
    fi
fi

if flatpak list | grep -q "com.valvesoftware.Steam"; then
    flatpak override --env=LANG=zh_CN.UTF-8 com.valvesoftware.Steam
    echo "[$(date '+%H:%M:%S')] OK: Applied Flatpak Steam override"
fi

# LazyVim配置
if [ "$INSTALL_LAZYVIM" = true ]; then
    echo "[$(date '+%H:%M:%S')] INFO: Installing LazyVim..."
    NVIM_CFG="$HOME_DIR/.config/nvim"

    if [ -d "$NVIM_CFG" ]; then
        BACKUP_PATH="$HOME_DIR/.config/nvim.old.apps.$(date +%s)"
        mv "$NVIM_CFG" "$BACKUP_PATH"
        echo "[$(date '+%H:%M:%S')] INFO: Backed up existing nvim config to $BACKUP_PATH"
    fi

    if as_user git clone https://github.com/LazyVim/starter "$NVIM_CFG"; then
        rm -rf "$NVIM_CFG/.git"
        echo "[$(date '+%H:%M:%S')] OK: LazyVim installed"
    else
        echo "[$(date '+%H:%M:%S')] ERROR: Failed to clone LazyVim"
    fi
fi

# --- 清理临时sudo权限 ---
revoke_nopasswd_sudo "$TARGET_USER"

# --- 生成失败报告 ---
if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
    DOCS_DIR="$HOME_DIR/Documents"
    REPORT_FILE="$DOCS_DIR/install-failures.txt"
    
    if [ ! -d "$DOCS_DIR" ]; then as_user mkdir -p "$DOCS_DIR"; fi
    
    echo "========================================================" >> "$REPORT_FILE"
    echo " Installation Failure Report - $(date)" >> "$REPORT_FILE"
    echo "========================================================" >> "$REPORT_FILE"
    printf "%s\n" "${FAILED_PACKAGES[@]}" >> "$REPORT_FILE"
    
    chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
    
    echo "[$(date '+%H:%M:%S')] WARN: Some applications failed to install"
    echo "[$(date '+%H:%M:%S')] WARN: Report saved to: $REPORT_FILE"
else
    echo "[$(date '+%H:%M:%S')] OK: All applications processed successfully"
fi

echo "[$(date '+%H:%M:%S')] INFO: Module 99-apps completed"
