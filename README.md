# SSH Manager

基于 expect 工具实现的 SSH 自动登录与连接管理工具。
支持密码认证和密钥认证等多种方式，提供了交互式的终端界面，支持节点分组、搜索、导入导出等功能。

## 1. 安装方法

### 1.1 通用一键安装 (推荐)

我们提供了一个自解压安装包，可以在任何 Linux 发行版上运行。

**构建安装包:**
```bash
./scripts/build_makeself.sh
```
这将在根目录下生成一个名为 `ssh-manager-0.2.run` 的文件。

**安装:**
```bash
sudo ./ssh-manager-0.2.run
```

该安装程序会自动：
- 安装二进制文件到 `/usr/local/bin/sshm`
- 安装默认配置到 `/etc/ssh-manager/config.yaml`
- 自动处理依赖检查和权限设置
- 生成卸载脚本 `/usr/local/bin/sshm-uninstall`

### 1.2 系统原生包安装 (.deb / .rpm)

如果您更喜欢使用系统的包管理器（如 `apt` 或 `yum`/`dnf`），可以使用打包脚本生成对应的安装包。

**生成安装包:**
```bash
./scripts/package.sh
```
该脚本会自动检测您的系统类型并尝试生成对应的包。您也可以在任何系统上生成通用包。生成的文件位于 `dist/` 目录下。

**安装 (Debian/Ubuntu):**
```bash
sudo dpkg -i dist/ssh-manager_0.2-1_all.deb
sudo apt-get install -f  # 修复可能缺失的依赖
```

**安装 (RHEL/CentOS/Fedora):**
```bash
sudo rpm -ivh dist/ssh-manager-0.2-1.noarch.rpm
```

### 1.3 Arch Linux 安装

对于 Arch Linux 用户，可以直接使用 `makepkg` 或通过 `package.sh` 脚本构建。

```bash
git clone https://github.com/quintin-lee/ssh-manager.git
cd ssh-manager
makepkg -si
```

## 2. 使用说明

### 2.1 启动程序

在终端中直接运行：
```bash
sshm
```

首次运行程序时，如果未找到配置文件，它会自动为您创建一个默认的用户配置文件 `~/.config/ssh-manager/config.yaml`。

### 2.2 交互式菜单

程序提供优化的交互式菜单，支持键盘快捷键：

| 快捷键   | 功能                            |
| -------- | ------------------------------- |
| **回车** | 进入节点列表模式 / 确认操作     |
| **/**    | 快捷搜索节点 (Search)           |
| **a**    | 添加新节点 (Add)                |
| **d**    | 删除节点 (Delete)               |
| **e**    | 导出配置 (Base64 或 文件)       |
| **i**    | 导入配置 (Base64 或 文件)       |
| **h**    | 显示帮助 (Help)                 |
| **q**    | 退出程序 (Quit)                 |

### 2.3 配置文件路径优先级

1. **环境变量**: `SSH_MANAGER_CONFIG`
2. **用户配置**: `~/.config/ssh-manager/config.yaml` (推荐)
3. **系统配置**: `/etc/ssh-manager/config.yaml`
4. **当前目录**: `./config.yaml`

### 2.4 配置文件格式

配置文件采用 YAML 格式：

```yaml
nodes:
  - name: 生产服务器
    group: Production
    host: 192.168.1.100
    port: 22
    user: admin
    type: pass
    pass: "123456"
  - name: AWS节点
    group: Cloud
    host: ec2-user@1.2.3.4
    port: 22
    user: ec2-user
    type: key
    keypath: "/home/user/.ssh/my-key.pem"
```

## 3. 开发与构建

本项目包含方便的构建脚本，位于 `scripts/` 目录下：

- **`scripts/build_makeself.sh`**: 生成 `.run` 自解压安装包 (需要安装 `makeself`)。
- **`scripts/package.sh`**: 自动检测系统并生成 `.deb`, `.rpm` 或 `.tar.gz` 包。

**依赖项:**
- expect
- bash
- sed
- awk
- ping (可选，用于健康检查)
- base64 (用于导入导出)

## 4. 卸载

如果您是通过 `.run` 安装包或 `install.sh` 安装的，可以使用以下命令卸载：

```bash
sudo sshm-uninstall
```

如果是通过包管理器（apt/yum/pacman）安装的，请使用对应的卸载命令（如 `apt remove ssh-manager`）。

## 5. 安全建议

1. **权限保护**: 配置文件包含敏感信息，程序会自动尝试将其权限设为 `600`。请确保您的系统多用户环境下该文件不被他人读取。
2. **密钥认证**: 推荐使用 SSH 密钥对认证，并在配置文件中指定 `keypath`。
3. **备份**: 建议定期使用程序内置的导出功能 (`e` 键) 备份您的配置。

---
License: MIT