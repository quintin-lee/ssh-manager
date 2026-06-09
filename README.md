# SSH Manager

基于 expect 的 SSH 连接管理工具。方向键导航、实时过滤、命令行直连。

## 安装

### 一键安装 (推荐)

```bash
./scripts/build_makeself.sh    # 构建自解压包
sudo ./ssh-manager-0.2.run     # 安装
```

### 系统包

```bash
./scripts/package.sh           # 自动检测系统，生成 .deb/.rpm/Arch 包
sudo dpkg -i dist/ssh-manager*.deb   # Debian/Ubuntu
sudo rpm -ivh dist/ssh-manager*.rpm  # RHEL/Fedora
makepkg -si                          # Arch
```

### 依赖

`expect` `bash` `sed` `awk` `base64`（ping 可选）

## 使用

### 交互模式

```bash
sshm              # 启动交互列表
```

| 操作 | 按键 |
|------|------|
| 选择节点 | `↑` `↓` |
| 连接 | `Enter` |
| 过滤 | 直接输入关键词 |
| 清除过滤 | `ESC` |
| 排序切换 | `s`（按组→按名→按状态） |
| 添加 | `a` |
| 删除 | `d`（再按退出删除模式） |
| 导出/导入 | `e` / `i` |
| 连接历史 | `r` |
| 帮助 | `h` |
| 退出 | `q` |

### 命令行直连

```bash
sshm prod           # 搜索"prod"，单结果直接连接
sshm db-server      # 多结果列出选项
```

### CLI 选项

```bash
sshm --help          # 帮助
sshm --version       # 版本
sshm --config <path> # 指定配置文件
sshm --validate      # 校验配置文件
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

### SSH config 导入

```bash
sshm --import-ssh-config ~/.ssh/config   # 导入标准 SSH config 的 Host 条目
```

导入时自动跳过通配符 Host（如 `Host *`），只导入具体主机条目。

## Shell 补全

```bash
# bash
source /usr/share/bash-completion/completions/sshm

# zsh (自动加载)
# fish
source /usr/share/fish/vendor_completions.d/sshm.fish
```

## 开发

```bash
./bin/sshm.sh               # 从源码运行
bats tests/                  # 运行测试 (39 tests)
shellcheck bin/sshm.sh       # 静态检查
```

## 安全

- 配置文件权限自动设为 600
- 所有修改操作前自动备份（`.bak.<timestamp>`）
- 推荐使用 SSH 密钥认证

## 卸载

```bash
sudo sshm-uninstall          # makeself/install.sh 安装
sudo apt remove ssh-manager  # 包管理器安装
```

---

License: MIT
