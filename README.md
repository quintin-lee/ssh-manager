# SSH Manager

基于 expect 的 SSH 连接管理工具。方向键导航、实时过滤、命令行直连、5 种打包格式。

[![Tests](https://github.com/quintin-lee/ssh-manager/actions/workflows/test.yml/badge.svg)](https://github.com/quintin-lee/ssh-manager/actions/workflows/test.yml)

## 安装

### 自解压包 (推荐，所有 Linux)

```bash
./scripts/build_makeself.sh
sudo ./ssh-manager-0.5.3.run
```

### 系统包管理器

```bash
# Debian/Ubuntu
sudo dpkg -i ssh-manager_0.5.3-1_all.deb

# RHEL/Fedora
sudo rpm -ivh ssh-manager-0.5.3-1.noarch.rpm

# Arch Linux
sudo pacman -U ssh-manager-0.5.3-4-any.pkg.tar.zst

# 通用 tarball
tar xzf ssh-manager-0.5.3.tar.gz
cd ssh-manager-0.5.3 && sudo ./install.sh
```

### 从源码构建包

```bash
./scripts/package.sh    # 自动检测系统，生成 .deb/.rpm/.tar.gz
makepkg -si             # Arch (使用 PKGBUILD)
```

### 依赖

`expect` `bash` `sed` `awk` `ping` `base64`（ping 用于节点健康检查）

## 使用

### 交互模式

```bash
sshm
```

| 操作 | 按键 |
|------|------|
| 选择节点 | `↑` `↓` |
| 连接选中节点 | `Enter` |
| 实时过滤 | 直接输入关键词 |
| 清除过滤 | `ESC` |
| 跳到顶部/底部 | `g` / `G` |
| 排序切换 | `s`（按组→按名→按状态） |
| 添加节点 | `a`（表单模式，数字键改字段，Enter 保存） |
| 删除节点 | `d`（再按退出删除模式） |
| 导出/导入配置 | `e` / `i` |
| 连接历史 | `r` |
| 帮助 | `h` |
| 退出 | `q` |
| 优雅中断 | `Ctrl+C`（清过滤回顶部，不退出） |

底部栏实时显示选中节点的 `名称@主机`。`g` 跳顶部，`G` 跳底部。

### 命令行直连

```bash
sshm prod           # 搜索"prod"，单结果直接 SSH 连接
sshm db-server      # 多结果列出选项
```

### CLI 选项

```bash
sshm --help                  # 帮助
sshm --version               # 版本
sshm --config <path>         # 指定配置文件
sshm --validate              # 校验配置文件
sshm --import-ssh-config f   # 导入 ~/.ssh/config 的 Host 条目
sshm --export-ssh-config     # 导出为 SSH config 格式
```

## 配置

### 路径优先级

1. `--config <path>` 命令行参数
2. `SSH_MANAGER_CONFIG` 环境变量
3. `~/.config/ssh-manager/config.yaml`（推荐）
4. `/etc/ssh-manager/config.yaml`
5. `./config.yaml`

### YAML 格式

```yaml
nodes:
  - name: 生产服务器
    group: Production
    host: 192.168.1.100
    port: 22
    user: admin
    type: pass
    pass: "password"
  - name: AWS 节点
    group: Cloud
    host: 10.0.0.5
    port: 22
    user: ec2-user
    type: key
    keypath: "/home/user/.ssh/my-key.pem"
```

### SSH config 互转

```bash
# 导入 ~/.ssh/config 中的 Host 条目
sshm --import-ssh-config ~/.ssh/config

# 导出节点为 ~/.ssh/config 格式
sshm --export-ssh-config
```

## Shell 补全

安装后自动部署到系统路径：

| Shell | 路径 |
|-------|------|
| bash | `/usr/share/bash-completion/completions/sshm` |
| zsh  | `/usr/share/zsh/site-functions/_sshm` |
| fish | `/usr/share/fish/vendor_completions.d/sshm.fish` |

`sshm <Tab>` 补全节点名和选项。

## 开发

```bash
./bin/sshm.sh               # 从源码运行
bats tests/                  # 运行测试 (73 tests)
shellcheck bin/sshm.sh       # 静态检查
```

## CI/CD

每次 push 触发 `Tests` 工作流：

- `lint-and-test`：ShellCheck 静态检查 + 73 个 bats 单元测试（Ubuntu 与 macOS 双平台）
- `package-verify`：deb/rpm/run/tarball/arch 五种包格式的安装→运行→卸载循环

tag `v*` 触发 Release 自动构建全格式包并发布到 GitHub Releases。

## 安全

- 配置文件权限自动设为 `600`
- 所有修改操作前自动备份（`config.yaml.bak.<timestamp>`）
- 主机/用户名字段拒绝 shell 特殊字符
- `set -o pipefail` 防止管道静默失败
- 推荐使用 SSH 密钥认证

### 密码存储警告

本工具在 `config.yaml` 中以**明文**存储密码。请确保：

- 配置文件权限为 `600`（工具已自动设置）
- 不要将 `config.yaml` 提交到版本控制系统
- 导出/分享配置时注意 Base64 编码内容包含明文密码
- 推荐使用 SSH **密钥认证**，避免在配置中保存密码

## 卸载

```bash
sudo sshm-uninstall          # makeself/install.sh 安装
sudo apt remove ssh-manager  # 包管理器安装
```

---

License: MIT
