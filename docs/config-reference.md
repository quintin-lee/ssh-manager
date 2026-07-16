# 配置参考

## 文件路径

配置路径优先级（从高到低）：

1. `--config <path>` 命令行参数
2. `SSH_MANAGER_CONFIG` 环境变量
3. `~/.config/ssh-manager/config.yaml`（推荐）
4. `/etc/ssh-manager/config.yaml`
5. `./config.yaml`（当前目录）

## 字段说明

```yaml
nodes:
  - name: <string>        # 节点显示名称（必填）
    group: <string>       # 分组名，影响 TUI 排序（必填）
    host: <string>        # 主机名或 IP 地址（必填）
    port: <integer>       # SSH 端口，默认 22
    user: <string>        # 登录用户名（必填）
    type: <string>        # 认证类型：pass | key | env（必填）
    pass: <string>        # 密码明文（type=pass 时必填，type=key 时可选用于解密密钥）
    keypath: <string>     # SSH 私钥路径（type=key 时必填）
    tags: <string>        # 逗号分隔的标签（可选，TUI 中显示）
```

### type 字段详解

| 值 | 说明 | 需配合字段 |
|----|------|-----------|
| `pass` | 密码认证 | `pass` |
| `key` | SSH 密钥认证 | `keypath` |
| `env` | 环境变量引用 | 见下方 |

### 密码/密钥的引用方式

`pass` 字段支持三种形式：

```yaml
# 1. 明文
pass: "my-password"

# 2. 环境变量引用（推荐，避免明文存储）
pass: "(env:MY_SSH_PASS)"

# 3. 变量替换
pass: "${MY_SSH_PASS}"
```

### tags 格式

用逗号分隔多个标签：

```yaml
tags: "prod,important,东京"
```

TUI 中每个标签会显示为彩色标记。

## 完整示例

```yaml
nodes:
  - name: 生产-Web-01
    group: Production
    host: 192.168.1.100
    port: 22
    user: admin
    type: key
    keypath: "/home/user/.ssh/prod-key.pem"
    tags: "prod,web"

  - name: 数据库
    group: Production
    host: 10.0.0.5
    port: 22
    user: dbadmin
    type: pass
    pass: "(env:DB_PASS)"
    tags: "prod,db"

  - name: 开发沙箱
    group: Development
    host: dev.example.com
    user: dev
    type: key
    keypath: "/home/user/.ssh/dev-key.pem"
```

## 安全

- 工具启动时会自动将配置文件权限设为 `600`（仅所有者可读写）
- 推荐使用 `(env:VAR)` 语法引用环境变量，避免在文件中存储明文密码
- 推荐使用 SSH 密钥认证（`type: key`），绕过密码传输
- 不要将 `config.yaml` 提交到版本控制系统
