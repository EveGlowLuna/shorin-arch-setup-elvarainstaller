
# Shorin Arch Setup 自动化改造计划

## 一、需求分析

### 1.1 核心需求
| 需求点 | 描述 | 优先级 |
|--------|------|--------|
| **完全自动执行** | 脚本从 `/tmp/setup-config.json` 读取配置，无需任何用户交互 | 高 |
| **chroot兼容** | 移除GUI环境依赖命令，确保在chroot环境正常运行 | 高 |
| **移除美化转义符** | 删除所有ANSI颜色、符号等美化输出 | 高 |
| **版权合规** | 删除第三方闭源应用（linuxqq、wechat等） | 高 |
| **文档生成** | 编写完整的配置参数文档 | 高 |

### 1.2 当前架构问题分析

**需要修改的核心问题：**

1. **交互式菜单依赖**：
   - `install.sh` 中的 FZF 菜单需要移除
   - `scripts/99-apps.sh` 中的 FZF 应用选择需要移除
   - 移除 random 桌面环境选项

2. **美化输出依赖**：
   - 所有 ANSI 颜色转义符需要删除
   - 所有 TUI 组件（section、info_kv等）需要简化为纯文本

3. **用户管理**：
   - /home/ 下只有一个用户，自动检测即可，无需配置

4. **版权问题**：
   - `common-applist.txt` 中包含 linuxqq、wechat 等闭源应用
   - 需要清理所有非开源软件

---

## 二、改造方案

### 2.1 配置文件格式设计

**`/tmp/setup-config.json` 结构：**

```json
{
  "desktop_env": "kde",
  "optional_modules": [
    "gpu-driver",
    "grub-theme"
  ],
  "mirror": "cn",
  "grub_theme": "1CyberGRUB-2077",
  "flatpak_mirror": "ustc"
}
```

| 字段 | 类型 | 说明 | 可选值 |
|------|------|------|--------|
| `desktop_env` | string | 桌面环境（无random选项） | `none`, `kde`, `gnome`, `shorinniri`, `minimalniri`, `minimallabwc`, `end4`, `dms`, `caelestia`, `inir`, `shorindms`, `shorinnocniri`, `hyprniri` |
| `optional_modules` | array | 可选模块 | `iwd`, `dualboot`, `gpu`, `grub`, `apps` |
| `mirror` | string | 镜像源 | `cn`, `global` |
| `grub_theme` | string | GRUB主题名（为空则不设置） | 见 grub-themes/ 目录 |
| `flatpak_mirror` | string | Flatpak镜像 | `sjtu`, `ustc`, `official` |

### 2.2 用户检测逻辑

```bash
# 自动检测/home/下唯一用户
detect_user() {
    local users=($(ls -la /home/ | grep -E '^d' | awk '{print $9}' | grep -v '^\.'))
    if [ ${#users[@]} -eq 1 ]; then
        export TARGET_USER="${users[0]}"
        export HOME_DIR="/home/$TARGET_USER"
    else
        error "Multiple or no users found in /home/"
        exit 1
    fi
}
```

### 2.3 文件修改清单

| 文件 | 修改类型 | 描述 |
|------|----------|------|
| `install.sh` | 重写核心逻辑 | 移除FZF菜单，移除美化输出，自动检测用户 |
| `scripts/00-utils.sh` | 重构 | 删除所有ANSI颜色，简化日志函数为纯文本 |
| `scripts/99-apps.sh` | 重构 | 移除FZF交互，自动安装，移除美化输出 |
| `scripts/07-grub-theme.sh` | 重构 | 移除TUI菜单，支持配置参数，移除美化输出 |
| `scripts/04-niri-setup.sh` | 修改 | 移除美化输出，确保无交互 |
| `scripts/04b-kdeplasma-setup.sh` | 修改 | 移除美化输出，确保无交互 |
| `common-applist.txt` | 清理 | 删除闭源应用 |
| `docs/config-reference.md` | 新建 | 配置文档 |

---

## 三、实施步骤

### 3.1 第一步：清理闭源应用

**修改 `common-applist.txt`：**
- 删除：`AUR:linuxqq-appimage`, `AUR:wechat-appimage`, `AUR:flclash-bin`
- 保留：开源软件（firefox、mpv、virt-manager等）

### 3.2 第二步：重构工具函数

**重写 `scripts/00-utils.sh`：**
1. 删除所有 ANSI 颜色定义
2. 删除所有美化符号（TICK、CROSS、INFO等）
3. 简化日志函数为纯文本输出：
   ```bash
   log() { echo "[$(date '+%H:%M:%S')] INFO: $1"; }
   success() { echo "[$(date '+%H:%M:%S')] OK: $1"; }
   warn() { echo "[$(date '+%H:%M:%S')] WARN: $1"; }
   error() { echo "[$(date '+%H:%M:%S')] ERROR: $1"; }
   ```
4. 添加JSON解析函数（纯bash实现，无jq依赖）
5. 添加用户自动检测函数

### 3.3 第三步：重构主安装脚本

**重写 `install.sh`：**
1. 移除FZF桌面选择菜单
2. 移除FZF可选模块选择菜单
3. 添加JSON配置读取逻辑
4. 添加chroot环境检测
5. 添加用户自动检测（从/home/获取）
6. 移除所有美化输出
7. 移除random桌面环境选项
8. 确保所有操作无交互

### 3.4 第四步：重构应用安装模块

**修改 `scripts/99-apps.sh`：**
1. 移除FZF交互式选择
2. 移除美化输出
3. 改为自动安装预定义的基础应用列表
4. 确保无任何用户确认提示

### 3.5 第五步：重构GRUB主题模块

**修改 `scripts/07-grub-theme.sh`：**
1. 移除TUI菜单
2. 移除美化输出
3. 支持从配置文件读取主题名称
4. 默认为不设置主题

### 3.6 第六步：创建配置文档

**创建 `docs/config-reference.md`：**
- 配置文件格式说明
- 所有字段详细说明
- 使用示例
- chroot环境准备指南

---

## 四、chroot环境适配

### 4.1 需要移除的GUI依赖

| 模块 | 需要修改的内容 |
|------|----------------|
| `install.sh` | 移除fzf、所有交互式菜单、所有美化输出 |
| `scripts/00-utils.sh` | 移除所有ANSI颜色和TUI组件 |
| `scripts/99-apps.sh` | 移除fzf、所有美化输出 |
| `scripts/07-grub-theme.sh` | 移除TUI菜单、所有美化输出 |
| `scripts/04-niri-setup.sh` | 移除美化输出、确保无交互 |
| `scripts/04b-kdeplasma-setup.sh` | 移除美化输出、确保无交互 |

### 4.2 chroot检测逻辑

```bash
detect_chroot() {
    if grep -q "chroot" /proc/1/cgroup 2>/dev/null || [ -f "/.chroot" ]; then
        export IN_CHROOT=true
        log "Detected chroot environment"
    else
        export IN_CHROOT=false
    fi
}
```

---

## 五、风险评估

| 风险 | 描述 | 应对措施 |
|------|------|----------|
| **jq依赖** | chroot环境可能没有jq | 使用纯bash解析JSON |
| **桌面安装失败** | chroot中无法运行GUI相关命令 | 条件跳过或使用轻量方案 |
| **网络问题** | chroot中网络配置可能不同 | 增加网络检测和重试 |
| **权限问题** | chroot中某些操作需要特殊处理 | 确保使用正确的sudo配置 |

---

## 六、测试计划

### 6.1 测试场景

| 场景 | 描述 | 验证点 |
|------|------|--------|
| **chroot环境测试** | 在arch-chroot中运行 | 脚本正常执行，无交互 |
| **配置文件测试** | 使用不同配置组合 | 正确解析并应用配置 |
| **网络测试** | 测试CN/Global镜像切换 | 正确选择镜像源 |
| **清理验证** | 检查闭源软件是否移除 | 确认common-applist.txt已清理 |
| **输出验证** | 检查输出是否为纯文本 | 无ANSI转义符 |

---

## 七、交付物

| 交付物 | 状态 | 说明 |
|--------|------|------|
| `install.sh` | 修改 | 支持JSON配置自动安装，纯文本输出 |
| `scripts/00-utils.sh` | 修改 | 纯文本日志函数，JSON解析 |
| `scripts/99-apps.sh` | 修改 | 自动安装模式，纯文本输出 |
| `scripts/07-grub-theme.sh` | 修改 | 支持配置驱动，纯文本输出 |
| `scripts/04-niri-setup.sh` | 修改 | 纯文本输出，无交互 |
| `scripts/04b-kdeplasma-setup.sh` | 修改 | 纯文本输出，无交互 |
| `common-applist.txt` | 修改 | 清理闭源软件 |
| `docs/config-reference.md` | 新建 | 配置文档 |
