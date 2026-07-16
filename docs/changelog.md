# 变更日志规范

## 格式

遵循 [Keep a Changelog](https://keepachangelog.com/) 标准。

## 文件位置

`CHANGELOG.md` 位于项目根目录。

## 结构

```markdown
# Changelog

## [Unreleased]

### Added
- 新功能（正向变更）

### Fixed
- Bug 修复

### Changed
- 现有功能的变化

### Deprecated
- 即将移除的功能

### Removed
- 已移除的功能

### Security
- 安全修复

## [X.Y.Z] - YYYY-MM-DD

同一分类结构...
```

## 版本章节

- `[Unreleased]` 始终在顶部，记录当前迭代的未发布变更
- 发布时 `scripts/tag.sh` 自动在 `[Unreleased]` 后插入 `[X.Y.Z] - 日期` 节
- 版本号遵循 [SemVer](https://semver.org/)：`主版本.次版本.修订号`

## 撰写原则

| 原则 | 说明 |
|------|------|
| 面向用户 | 写"用户能感知到什么变化"，而非内部实现细节 |
| 分类明确 | 每个条目归入正确的分类（Added/Fixed/Changed 等） |
| 可读性强 | 使用简洁的中文或英文，一行一条 |
| 引用来源 | 关联 PR 编号或 Issue 编号 |

## 示例

```markdown
## [Unreleased]

### Added
- TUI 列表增加列标题行
- 连接健康检查改为后台批量运行，不再阻塞启动

### Fixed
- 修复无 tags 节点行错位问题
- 修复 `[1-9]` 快捷键与过滤冲突

## [0.5.4] - 2026-07-06

### Added
- 连接历史功能 (`r` 键查看)
- TUI 主题切换器

### Fixed
- 修复某些终端下 ANSI 颜色渲染异常
```

## 工具支持

- `scripts/tag.sh` 自动在 `[Unreleased]` 后插入版本节和日期
- 发布前只需整理 `[Unreleased]` 下的条目即可
