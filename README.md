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

2. **默认行为**：如未设置环境变量，程序将在当前工作目录查找或创建 `config.yaml`

### 3.3 系统级配置

包管理器安装后，系统配置文件模板位于：

- `/etc/ssh-manager/config.yaml.default` - 默认配置模板
- `/usr/bin/sshm` - 主程序位置
- `/usr/share/doc/ssh-manager/README` - 文档位置

### 3.2 功能操作

程序提供交互式菜单：

- 1. 节点列表与连接 (List & Connect)
- 2. 快捷搜索节点 (Search)
- 3. 添加新节点 (Add)
- 4. 删除旧节点 (Delete)
- 5. 导出配置 (Base64)
- 6. 导入配置 (Base64)

### 3.3 配置文件格式

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

## 4. 特性

- **交互式菜单**：直观的终端界面，支持节点列表、搜索、添加、删除等功能
- **多认证支持**：支持密码认证和密钥认证两种方式
- **分组管理**：支持将服务器按分组进行管理
- **状态显示**：实时显示服务器在线状态（绿点表示在线，红点表示离线）
- **搜索功能**：支持按关键词快速搜索服务器
- **配置导入导出**：支持Base64格式的配置导入导出
- **安全存储**：配置文件权限自动设置为600，保护敏感信息

## 5. 依赖项

- expect
- ssh client
- bash
- sed
- awk
- ping
- base64

## 6. 安全建议

1. 对于生产环境，强烈推荐使用 SSH 密钥认证而不是密码认证
2. 如果必须使用密码认证，请确保配置文件有适当的权限保护
3. 定期更新和轮换认证凭据
4. 使用强密码或密码短语保护私钥文件
5. 检查 SSH 主机密钥指纹以防止中间人攻击
