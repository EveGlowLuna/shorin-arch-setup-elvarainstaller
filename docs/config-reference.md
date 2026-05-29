
# Shorin Arch Setup - 配置文件参考文档

## 概述

本文档描述了 Shorin Arch Setup 自动化安装脚本的配置文件格式。脚本会自动从 `/root/setup-config.json` 读取配置并执行安装，无需任何用户交互。

## 配置文件位置

配置文件必须位于：`/root/setup-config.json`

## 配置文件格式

```json
{
  "desktop_env": "kde",
  "optional_modules": ["gpu", "grub", "apps"],
  "mirror": "cn",
  "grub_theme": "1CyberGRUB-2077",
  "flatpak_mirror": "ustc"
}
```

## 字段详解

### 1. desktop_env (必填)

指定要安装的桌面环境。

| 值 | 描述 |
|----|------|
| `none` | 不安装桌面环境（仅基础系统） |
| `kde` | KDE Plasma |
| `gnome` | GNOME |
| `shorinniri` | Shorin Niri (推荐) |
| `minimalniri` | 极简版 Niri |
| `minimallabwc` | 极简版 Labwc |
| `end4` | End4 Quickshell |
| `dms` | DMS Quickshell |
| `caelestia` | Caelestia Quickshell |
| `inir` | Inir Quickshell |
| `shorindms` | Shorin DMS |
| `shorinnocniri` | Shorin Noctalia |
| `hyprniri` | Shorin HyprNiri |

### 2. optional_modules (可选)

指定要启用的可选模块，为数组类型。

| 值 | 模块名称 | 描述 |
|----|----------|------|
| `iwd` | IWD网络后端 | 使用IWD替代NetworkManager |
| `dualboot` | 双系统修复 | 修复Windows双系统时间同步问题 |
| `gpu` | GPU驱动 | 自动检测并安装Intel/AMD/NVIDIA驱动 |
| `grub` | GRUB主题 | 安装GRUB主题 |
| `apps` | 常用应用 | 安装common-applist.txt中的应用 |

**示例：**
```json
"optional_modules": ["gpu", "grub", "apps"]
```

### 3. mirror (可选)

指定镜像源区域。

| 值 | 描述 |
|----|------|
| `cn` | 中国镜像（自动选择国内源） |
| `global` | 全球镜像（默认） |

### 4. grub_theme (可选)

指定GRUB主题名称。需先启用 `grub` 模块。

可用主题需位于 `grub-themes/` 目录下。

**示例：**
```json
"grub_theme": "1CyberGRUB-2077"
```

**注意：** 若为空字符串或未设置，将不应用GRUB主题。

### 5. flatpak_mirror (可选)

指定Flatpak镜像源。

| 值 | 镜像源 | URL |
|----|--------|-----|
| `sjtu` | 上海交通大学 | https://mirror.sjtu.edu.cn/flathub |
| `ustc` | 中国科学技术大学 | https://mirrors.ustc.edu.cn/flathub |
| `official` | 官方源（默认） | https://dl.flathub.org/repo/ |

## 完整配置示例

### 示例1：KDE桌面 + 中国镜像 + GPU驱动 + GRUB主题

```json
{
  "desktop_env": "kde",
  "optional_modules": ["gpu", "grub", "apps"],
  "mirror": "cn",
  "grub_theme": "1CyberGRUB-2077",
  "flatpak_mirror": "ustc"
}
```

### 示例2：Niri桌面 + 全球镜像 + 常用应用

```json
{
  "desktop_env": "shorinniri",
  "optional_modules": ["apps"],
  "mirror": "global",
  "flatpak_mirror": "official"
}
```

### 示例3：仅基础系统（无桌面）

```json
{
  "desktop_env": "none",
  "optional_modules": ["gpu"],
  "mirror": "cn"
}
```

## 用户检测机制

脚本会自动检测 `/home/` 目录下的唯一用户，无需配置用户名：

1. 首先检查 `/tmp/shorin_install_user` 文件
2. 若不存在，扫描 `/home/` 目录查找唯一用户
3. 若找到多个或零个用户，脚本将报错退出

## chroot环境支持

脚本支持在chroot环境中运行：

1. 自动检测chroot环境（通过 `/proc/1/cgroup` 或 `/` 目录下的 `.chroot` 文件）
2. 在chroot中跳过显示管理器配置
3. 使用纯文本输出，无ANSI颜色转义符

## 运行方式

### 在chroot中运行

```bash
# 创建配置文件
cat > /root/setup-config.json << EOF
{
  "desktop_env": "kde",
  "optional_modules": ["gpu", "apps"],
  "mirror": "cn"
}
EOF

# 运行安装脚本
bash /path/to/install.sh
```

### 在Live CD环境中运行

```bash
# 创建配置文件
cat > /root/setup-config.json << EOF
{
  "desktop_env": "shorinniri",
  "optional_modules": ["gpu", "grub", "apps"],
  "mirror": "cn",
  "grub_theme": "1CyberGRUB-2077"
}
EOF

# 挂载系统分区后运行
bash /path/to/install.sh
```

## 模块执行顺序

脚本按以下顺序执行模块：

1. **必选模块**（始终执行）：
   - `00-btrfs-init.sh` - Btrfs快照初始化
   - `01a-base.sh` - 基础系统配置
   - `02-musthave.sh` - 必备软件（PipeWire、Fcitx5等）
   - `03a-user.sh` - 用户配置
   - `03c-snapshot-before-desktop.sh` - 安装桌面前快照
   - `05-verify-desktop.sh` - 安装验证

2. **可选模块**（按配置顺序）：
   - `01b-nm-backend.sh` - IWD网络后端
   - `02a-dualboot-fix.sh` - 双系统修复
   - `03b-gpu-driver.sh` - GPU驱动
   - `07-grub-theme.sh` - GRUB主题
   - `99-apps.sh` - 常用应用

3. **桌面环境模块**（根据desktop_env选择）：
   - KDE: `04b-kdeplasma-setup.sh`
   - Niri: `04-niri-setup.sh`
   - GNOME: `04d-gnome.sh`
   - 其他: 对应模块

## 日志文件

安装日志会保存到：
- 临时位置：`/tmp/log-shorin-arch-setup.txt`
- 用户文档：`/home/<用户名>/Documents/log-shorin-arch-setup.txt`

## 错误处理

### 断点续装

脚本支持断点续装。若安装中断，再次运行脚本会跳过已完成的模块。

进度文件位置：`/path/to/repo/.install_progress`

### 失败处理

- 单个模块失败会导致整个安装终止
- 失败的应用会记录到：`/home/<用户名>/Documents/install-failures.txt`

## 注意事项

1. **配置文件必须存在**：若 `/root/setup-config.json` 不存在，脚本将报错退出
2. **用户必须存在**：`/home/` 目录下必须有且仅有一个用户
3. **需要root权限**：脚本必须以root身份运行
4. **网络连接**：安装过程需要网络连接
5. **闭源软件**：本脚本已移除所有闭源应用（如linuxqq、wechat等）

## 环境变量

| 变量名 | 默认值 | 描述 |
|--------|--------|------|
| `DEBUG` | 0 | 设置为1启用调试模式 |
| `CN_MIRROR` | 0 | 设置为1强制使用中国镜像 |
| `IN_CHROOT` | 自动检测 | 指示是否在chroot环境中 |

## 常见问题

### Q: 如何跳过某些模块？

A: 从 `optional_modules` 数组中移除对应模块即可。

### Q: 如何不安装任何应用？

A: 从 `optional_modules` 中移除 `apps`。

### Q: 如何查看安装日志？

A: 日志保存在 `/home/<用户名>/Documents/log-shorin-arch-setup.txt`

### Q: 安装失败后如何重试？

A: 直接重新运行 `install.sh`，脚本会自动跳过已完成的模块。
