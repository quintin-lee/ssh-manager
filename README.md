# SSH Manager

基于 expect 工具实现 SSH 自动登录服务器，管理服务器 SSH 连接。
支持密码认证和密钥认证等多种方式，提供了交互式的终端界面。

## 1. ArchLinux/Manjaro 发行版打包

```shell
git clone https://github.com/quintin-lee/ssh-manager.git

cd ssh-manager
makepkg
```

## 2. 安装

```shell
sudo pacman -U 包名
```

## 3. 使用

首次运行 `sshm` 会在当前目录创建 `config.yaml` 配置文件。
在打包安装后，系统会提供一个默认配置模板位于 `/etc/ssh-manager/config.yaml.default`。

### 3.1 启动程序

```shell
sshm
```

### 3.2 指定配置文件路径

安装后，可通过以下方式指定配置文件路径：

1. **使用环境变量**：通过 `SSH_MANAGER_CONFIG` 环境变量指定配置文件路径

   ```shell
   SSH_MANAGER_CONFIG=/path/to/your/custom-config.yaml sshm
   ```

   您也可以将其添加到 shell 配置文件（如 `~/.bashrc` 或 `~/.zshrc`）中以永久生效：

   ```shell
   export SSH_MANAGER_CONFIG=~/.config/ssh-manager/config.yaml
   ```

2. **默认行为**：如未设置环境变量，程序会自动按照以下优先级查找配置文件：

   - 用户个人配置：`~/.config/ssh-manager/config.yaml`
   - 系统级配置：`/etc/ssh-manager/config.yaml`
   - 当前目录：`./config.yaml`

   首次运行时，如果用户配置不存在，会自动从系统配置复制到用户配置目录。

### 3.3 系统级配置

包管理器安装后，系统配置文件模板位于：

- `/etc/ssh-manager/config.yaml` - 系统级默认配置 (在更新时不会被覆盖)
- `/usr/bin/sshm` - 主程序位置
- `/usr/share/doc/ssh-manager/README` - 文档位置

### 3.4 交互式菜单操作

程序提供优化的交互式菜单，支持键盘快捷键：

| 快捷键   | 功能                            |
| -------- | ------------------------------- |
| **回车** | 节点列表与连接 (List & Connect) |
| **/**    | 快捷搜索节点 (Search)           |
| **a**    | 添加新节点 (Add)                |
| **d**    | 删除节点 (Delete)               |
| **e**    | 导出配置 (Base64 或 文件)       |
| **i**    | 导入配置 (Base64 或 文件)       |
| **h**    | 显示帮助 (Help)                 |
| **q**    | 退出程序 (Quit)                 |

### 3.5 配置文件格式

配置文件为 `config.yaml`，格式如下：

```yaml
nodes:
  - name: 服务器名称
    group: 分组名
    host: 主机IP或域名
    port: 端口
    user: 用户名
    type: 认证类型 (pass/key)
    pass: 密码或密钥短语
    keypath: 私钥路径 (仅当 type=key 时)
```

示例：

```yaml
nodes:
  - name: 生产服务器
    group: Production
    host: 192.168.1.100
    port: 22
    user: admin
    type: pass
    pass: "123456"
    keypath: ""
  - name: 测试服务器
    group: Test
    host: example.com
    port: 2222
    user: testuser
    type: key
    pass: "密钥短语（如果有）"
    keypath: "/home/user/.ssh/id_rsa"
```

## 4. 新特性

- **优化交互界面**：支持键盘快捷键操作，无需输入数字和回车
- **智能配置管理**：自动处理系统配置与用户配置，优先使用用户配置
- **文件导入导出**：支持直接从文件导入/导出配置，也支持原有的 Base64 方式
- **帮助系统**：内置帮助系统，按 `h` 键查看所有快捷键
- **配置文件保护**：在系统更新时保留用户自定义配置，不会被包管理器覆盖
- **交互式菜单**：直观的终端界面，支持节点列表、搜索、添加、删除等功能
- **多认证支持**：支持密码认证和密钥认证两种方式
- **分组管理**：支持将服务器按分组进行管理
- **状态显示**：实时显示服务器在线状态（绿点表示在线，红点表示离线）
- **搜索功能**：支持按关键词快速搜索服务器
- **安全存储**：配置文件权限自动设置为600，保护敏感信息

## 5. 配置导入导出

### 5.1 从文件导入配置

1. 按 `i` 键进入导入功能
2. 选择选项 `2` 从文件导入
3. 输入配置文件路径
4. 确认覆盖现有配置

### 5.2 从 Base64 字符串导入配置

1. 按 `i` 键进入导入功能
2. 选择选项 `1` 从 Base64 字符串导入
3. 粘贴 Base64 编码的配置内容

### 5.3 导出配置到文件

1. 按 `e` 键进入导出功能
2. 选择选项 `2` 保存到文件
3. 输入要保存的文件路径

### 5.4 导出 Base64 字符串

1. 按 `e` 键进入导出功能
2. 选择选项 `1` 屏幕输出 Base64

## 6. 依赖项

- expect
- ssh client
- bash
- sed
- awk
- ping
- base64

## 7. 安全建议

1. 对于生产环境，强烈推荐使用 SSH 密钥认证而不是密码认证
2. 如果必须使用密码认证，请确保配置文件有适当的权限保护
3. 定期更新和轮换认证凭据
4. 使用强密码或密码短语保护私钥文件
5. 检查 SSH 主机密钥指纹以防止中间人攻击
6. 在共享或公共计算机上使用时，注意清理配置文件

## 8. 故障排除

- **"目录不可写"错误**：这是正常的，程序会自动创建用户配置文件
- **找不到配置文件**：检查环境变量 `SSH_MANAGER_CONFIG` 或在当前目录创建 `config.yaml`
- **连接超时**：确认服务器IP、端口、用户名和认证信息正确
- **权限错误**：确保配置文件权限为 600 (`chmod 600 config.yaml`)
