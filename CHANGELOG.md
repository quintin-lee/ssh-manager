# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
