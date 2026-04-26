#!/bin/bash

# ==============================================================================
# 00-utils.sh - Utility Functions (Minimal Version for chroot)
# ==============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "[$(date '+%H:%M:%S')] ERROR: Script must be run as root."
        exit 1
    fi
}
check_root

# ==============================================================================
# detect_target_user - 自动检测/home/下唯一用户
# ==============================================================================
detect_target_user() {
    if [[ -f "/tmp/shorin_install_user" ]]; then
        TARGET_USER=$(cat "/tmp/shorin_install_user")
        HOME_DIR="/home/$TARGET_USER"
        export TARGET_USER HOME_DIR
        return 0
    fi
    
    local users=()
    while IFS= read -r line; do
        users+=("$line")
    done < <(find /home -maxdepth 1 -mindepth 1 -type d ! -name '.*' ! -name 'lost+found' -printf '%f\n' 2>/dev/null)
    
    if [ ${#users[@]} -eq 1 ]; then
        TARGET_USER="${users[0]}"
        HOME_DIR="/home/$TARGET_USER"
        echo "[$(date '+%H:%M:%S')] INFO: Detected user: $TARGET_USER"
    elif [ ${#users[@]} -eq 0 ]; then
        echo "[$(date '+%H:%M:%S')] ERROR: No users found in /home/"
        exit 1
    else
        echo "[$(date '+%H:%M:%S')] ERROR: Multiple users found in /home/: ${users[*]}"
        exit 1
    fi
    
    echo "$TARGET_USER" > "/tmp/shorin_install_user"
    export TARGET_USER HOME_DIR
}

# ==============================================================================
# JSON解析函数 (纯bash实现，无jq依赖)
# ==============================================================================

# 读取JSON字符串中的字段值
# usage: get_json_field <json_string> <field_name>
get_json_field() {
    local json="$1"
    local field="$2"
    
    local result=$(echo "$json" | grep -o "\"$field\"\s*:\s*\"[^\"]*\"" | sed "s/\"$field\"\s*:\s*\"//" | sed 's/"$//')
    
    if [ -z "$result" ]; then
        result=$(echo "$json" | grep -o "\"$field\"\s*:\s*[^\",}]*" | sed "s/\"$field\"\s*:\s*//")
    fi
    
    echo "$result" | tr -d ' '
}

# 读取JSON数组字段
# usage: get_json_array <json_string> <field_name>
get_json_array() {
    local json="$1"
    local field="$2"
    
    local array_content=$(echo "$json" | sed 's/"/\n/g' | grep -A 100 "\"$field\"" | grep -E '^\[' -A 100 | grep -E '^\]' -B 100 | grep -v '^\[' | grep -v '^\]')
    echo "$array_content" | tr ',' '\n' | sed 's/^[ \t]*//;s/[ \t]*$//' | grep -v '^$'
}

# 读取配置文件
read_config() {
    local config_file="${1:-/tmp/setup-config.json}"
    
    if [ ! -f "$config_file" ]; then
        echo "[$(date '+%H:%M:%S')] ERROR: Config file not found: $config_file"
        exit 1
    fi
    
    local json_content=$(cat "$config_file")
    
    export DESKTOP_ENV=$(get_json_field "$json_content" "desktop_env")
    export MIRROR_MODE=$(get_json_field "$json_content" "mirror")
    export GRUB_THEME=$(get_json_field "$json_content" "grub_theme")
    export FLATPAK_MIRROR=$(get_json_field "$json_content" "flatpak_mirror")
    
    export OPTIONAL_MODULES=()
    local modules=$(get_json_array "$json_content" "optional_modules")
    while IFS= read -r module; do
        OPTIONAL_MODULES+=("$module")
    done <<< "$modules"
    
    if [ -z "$DESKTOP_ENV" ]; then
        DESKTOP_ENV="none"
    fi
    if [ -z "$MIRROR_MODE" ]; then
        MIRROR_MODE="global"
    fi
    
    echo "[$(date '+%H:%M:%S')] INFO: Loaded config - desktop_env: $DESKTOP_ENV, mirror: $MIRROR_MODE"
}

# ==============================================================================
# 日志文件
# ==============================================================================
export TEMP_LOG_FILE="/tmp/log-shorin-arch-setup.txt"
[ ! -f "$TEMP_LOG_FILE" ] && touch "$TEMP_LOG_FILE" && chmod 666 "$TEMP_LOG_FILE"

# --- 日志函数 ---
write_log() {
    local clean_msg=$(echo "$2" | sed 's/\x1b\[[0-9;]*m//g')
    echo "[$(date '+%H:%M:%S')] [$1] $clean_msg" >> "$TEMP_LOG_FILE"
}

log() {
    echo "[$(date '+%H:%M:%S')] INFO: $1"
    write_log "LOG" "$1"
}

success() {
    echo "[$(date '+%H:%M:%S')] OK: $1"
    write_log "SUCCESS" "$1"
}

warn() {
    echo "[$(date '+%H:%M:%S')] WARN: $1"
    write_log "WARN" "$1"
}

error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $1"
    write_log "ERROR" "$1"
}

# --- 命令执行器 ---
exe() {
    local full_command="$*"
    
    echo "[$(date '+%H:%M:%S')] EXEC: $full_command"
    write_log "EXEC" "$full_command"
    
    "$@"
    local status=$?
    
    if [ $status -eq 0 ]; then
        echo "[$(date '+%H:%M:%S')] OK: Command succeeded"
    else
        echo "[$(date '+%H:%M:%S')] ERROR: Command failed with exit code $status"
        write_log "FAIL" "Exit Code: $status"
        return $status
    fi
}

exe_silent() {
    "$@" > /dev/null 2>&1
}

# --- 辅助函数 ---
as_user() {
    runuser -u "$TARGET_USER" -- "$@"
}

force_copy() {
    local src="$1"
    local target_dir="$2"
    
    if [[ -z "$src" || -z "$target_dir" ]]; then
        warn "force_copy: Missing arguments"
        return 1
    fi
    
    if [[ -d "${src%/}" ]]; then
        (cd "$src" && find . -type d) | while read -r d; do
            as_user rm -f "$target_dir/$d" 2>/dev/null
        done
    fi
    
    exe as_user cp -rf "$src" "$target_dir"
}

# --- Flathub镜像选择 ---
select_flathub_mirror() {
    local name=""
    local url=""
    
    case "$FLATPAK_MIRROR" in
        sjtu)
            name="SJTU (Shanghai Jiao Tong)"
            url="https://mirror.sjtu.edu.cn/flathub"
            ;;
        ustc)
            name="USTC (Univ of Sci & Tech of China)"
            url="https://mirrors.ustc.edu.cn/flathub"
            ;;
        *)
            name="FlatHub Official"
            url="https://dl.flathub.org/repo/"
            ;;
    esac
    
    log "Setting Flathub mirror to: $name"
    exe flatpak remote-modify flathub --url="$url"
}

# --- 显示管理器检测 ---
check_dm_conflict() {
    local KNOWN_DMS=("lemurs" "ly" "gdm" "lightdm" "lxdm" "plasma-login-manager" "sddm" "greetd")
    export SKIP_DM=false
    
    for dm in "${KNOWN_DMS[@]}"; do
        if pacman -Q "$dm" &>/dev/null; then
            export SKIP_DM=true
            log "Display manager conflict detected: $dm"
            return
        fi
    done
    
    export SKIP_DM=false
}

# --- 安装ly显示管理器 ---
setup_ly() {
    log "Installing ly display manager..."
    exe pacman -S --noconfirm --needed ly
    log "Enabling ly service..."
    systemctl enable ly@tty1
    echo "[$(date '+%H:%M:%S')] OK: ly display manager configured"
}

# --- 隐藏桌面图标 ---
hide_desktop_file() {
    local source_file="$1"
    local filename=$(basename "$source_file")
    local user_dir="$HOME_DIR/.local/share/applications"
    local target_file="$user_dir/$filename"
    
    mkdir -p "$user_dir"
    
    if [[ -f "$source_file" ]]; then
        cp -fv "$source_file" "$target_file"
        if grep -q "^NoDisplay=" "$target_file"; then
            sed -i 's/^NoDisplay=.*/NoDisplay=true/' "$target_file"
        else
            echo "NoDisplay=true" >> "$target_file"
        fi
        chown "$TARGET_USER:" "$target_file"
    fi
}

run_hide_desktop_file() {
    local apps_to_hide=(
        "avahi-discover.desktop"
        "qv4l2.desktop"
        "qvidcap.desktop"
        "bssh.desktop"
        "org.fcitx.Fcitx5.desktop"
        "org.fcitx.fcitx5-migrator.desktop"
        "xgps.desktop"
        "xgpsspeed.desktop"
        "gvim.desktop"
        "kbd-layout-viewer5.desktop"
        "bvnc.desktop"
        "yazi.desktop"
        "btop.desktop"
        "vim.desktop"
        "nvim.desktop"
        "nvtop.desktop"
        "mpv.desktop"
        "org.gnome.Settings.desktop"
        "thunar-settings.desktop"
        "thunar-bulk-rename.desktop"
        "thunar-volman-settings.desktop"
        "clipse-gui.desktop"
        "waypaper.desktop"
        "xfce4-about.desktop"
        "cmake-gui.desktop"
        "assistant.desktop"
        "qdbusviewer.desktop"
        "linguist.desktop"
        "designer.desktop"
        "org.kde.drkonqi.coredump.gui.desktop"
        "org.kde.kwrite.desktop"
        "org.freedesktop.MalcontentControl.desktop"
        "org.gnome.Nautilus.desktop"
        "lstopo.desktop"
    )
    
    echo "[$(date '+%H:%M:%S')] INFO: Hiding desktop icons..."
    
    for app in "${apps_to_hide[@]}"; do
        hide_desktop_file "/usr/share/applications/$app"
    done
    chown -R "$TARGET_USER:" "$HOME_DIR/.local/share/applications"
    
    echo "[$(date '+%H:%M:%S')] OK: Desktop icons hidden"
}

# --- Nautilus配置 ---
configure_nautilus_user() {
    local sys_file="/usr/share/applications/org.gnome.Nautilus.desktop"
    local user_dir="$HOME_DIR/.local/share/applications"
    local user_file="$user_dir/org.gnome.Nautilus.desktop"
    
    if [ -f "$sys_file" ]; then
        local need_modify=0
        local env_vars="env"
        
        if command -v niri >/dev/null 2>&1; then
            env_vars="$env_vars GTK_IM_MODULE=fcitx"
            need_modify=1
        fi
        
        local gpu_count=$(lspci | grep -E -i "vga|3d" | wc -l)
        local has_nvidia=$(lspci | grep -E -i "nvidia" | wc -l)
        
        if [ "$gpu_count" -gt 1 ] && [ "$has_nvidia" -gt 0 ]; then
            env_vars="$env_vars GSK_RENDERER=gl"
            need_modify=1
            
            local env_conf_dir="$HOME_DIR/.config/environment.d"
            if [ ! -f "$env_conf_dir/gsk.conf" ]; then
                mkdir -p "$env_conf_dir"
                echo "GSK_RENDERER=gl" > "$env_conf_dir/gsk.conf"
                if [ -n "$TARGET_USER" ]; then
                    chown -R "$TARGET_USER" "$env_conf_dir"
                fi
            fi
        fi
        
        if [ "$need_modify" -eq 1 ]; then
            mkdir -p "$user_dir"
            cp "$sys_file" "$user_file"
            
            if [ -n "$TARGET_USER" ]; then
                chown "$TARGET_USER" "$user_file"
            fi
            
            sed -i "s|^Exec=|Exec=$env_vars |" "$user_file"
        fi
    fi
}
