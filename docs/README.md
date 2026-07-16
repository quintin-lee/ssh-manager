# 文档索引

| 文档 | 说明 |
|------|------|
| [README.md](../README.md) | 项目主页 — 安装、使用、配置、CI/CD、安全 |
| [release.md](release.md) | 发布流程 — 版本规范、发布步骤、CI 自动构建说明 |

## 模块参考

| 模块 | 文件 | 说明 |
|------|------|------|
| 入口点 | [`bin/sshm.sh`](../bin/sshm.sh) | CLI 参数解析，TUI/CLI 模式调度 |
| TUI 界面 | [`lib/tui.sh`](../lib/tui.sh) | 全屏终端列表、预览、输入表单 |
| 节点操作 | [`lib/node_cmd.sh`](../lib/node_cmd.sh) | 添加/编辑/删除/克隆节点 |
| SSH 连接 | [`lib/ssh.sh`](../lib/ssh.sh) | 凭据解析、expect 自动登录 |
| 配置加载 | [`lib/config.sh`](../lib/config.sh) | 配置文件路径解析、版本载入 |
| YAML 解析 | [`lib/yaml_parser.sh`](../lib/yaml_parser.sh) | 配置文件 YAML → 全局数组 |
| YAML 生成 | [`lib/yaml_ops.sh`](../lib/yaml_ops.sh) | 节点 YAML 块序列化 |
| 工具函数 | [`lib/util.sh`](../lib/util.sh) | 终端尺寸、文本填充、连接历史 |

## 脚本参考

| 脚本 | 说明 |
|------|------|
| [`scripts/tag.sh`](../scripts/tag.sh) | 版本更新 + git tag |
| [`scripts/package.sh`](../scripts/package.sh) | 构建 .deb/.rpm/.tar.gz 包 |
| [`scripts/build_makeself.sh`](../scripts/build_makeself.sh) | 构建 .run 自解压安装包 |
| [`scripts/install.sh`](../scripts/install.sh) | 从源码安装到系统路径 |
| [`scripts/release.sh`](../scripts/release.sh) | （旧版）版本发布脚本 |

## CI/CD

| 工作流 | 文件 | 触发条件 |
|--------|------|----------|
| 测试 | `.github/workflows/test.yml` | 每次 push |
| 发布 | `.github/workflows/release.yml` | 推送 v* tag |
