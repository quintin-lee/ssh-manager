# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.4] - 2026-07-15


### Added
- Module split: extracted `lib/config.sh`, `lib/util.sh`, `lib/ssh.sh`, `lib/tui.sh`, `lib/node_cmd.sh`
- `lib/ssh_connect.tcl`: externalized expect SSH template
- `--list` and `--format json` machine-readable output
- Environment variable password references: `pass: (env:NAME)` or `pass: ${NAME}`
- `_sshm_resolve_pass()` helper for env-based password resolution
- `CHANGELOG.md` for tracking versioned changes

### Changed
- `bin/sshm.sh` reduced from ~1322 lines to entry-point-only loader
- `lib/ssh.sh`: `ssh_connect()` now reads TCL template from `lib/ssh_connect.tcl`
- `lib/node_cmd.sh`: consolidated add/edit/delete/import/export commands

### Fixed
- `--validate` now checks file existence, readability, and `nodes:` header
- Version management unified to `VERSION` file only
- Removed hardcoded `v0.2` from `show_help` and header comments
- CI: `lint-and-test` 安装 `expect`/`iputils-ping`，修复 ShellCheck 警告
  （`lib/tui.sh` 分离声明与赋值、`lib/yaml_parser.sh` 导出 `NODE_*` 全局变量）
- `--validate` 在 `init_env` 自动创建配置之前先检测缺失文件并报告
- `bin/sshm.sh` 在被 source（如测试）时不执行主逻辑（BASH_SOURCE 守卫）
- `get_all_nodes` 对缺失配置文件返回空列表而非报错
- tarball `install.sh` 卸载脚本 heredoc 加引号，避免 `set -u` 下未绑定变量 `_f` 报错

## [0.5.3] - 2026-01-10

### Added
- Node tags field with `#tag` filtering in interactive list
- Live theme preview with 5 palettes (dark/light/ocean/sunset/forest)
- Undo delete (`u`) with `_SSHM_DELETED_YAML` buffer
- Scroll indicators and auto-scroll in TUI
- 1-9 quick connect shortcuts
- Connection history (`r`) with recent 20 entries
- `--import-ssh-config` / `--export-ssh-config` support
- Base64 export/import with interactive menu

### Changed
- `sanitize_yaml_value` expanded to handle colons, hashes, quotes, backslashes
- Config backup before every mutation (`.bak.<timestamp>`)
- Auto `chmod 600` on config writes

### Fixed
- Strip quotes from tags in parser for backward compatibility
- Fix `sed_i` portability between GNU and BSD sed
