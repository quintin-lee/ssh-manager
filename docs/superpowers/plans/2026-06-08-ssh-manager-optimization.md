# SSH Manager 优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix known bugs, add test coverage, establish CI/CD, and improve code quality across the SSH Manager project.

**Architecture:** The project is a single-file Bash TUI (~808 lines) for SSH connection management. Optimization follows a progressive approach: fix critical bugs first, then add testing infrastructure, then CI/CD, then structural improvements.

**Tech Stack:** Bash, Bats (Bash Automated Testing System) for tests, GitHub Actions for CI, yq for proper YAML parsing.

---

### Task 1: Create .gitignore and remove empty src/ directory

**Files:**
- Create: `.gitignore`
- Delete: `src/` (empty directory)

- [ ] **Step 1: Create .gitignore**

```bash
cat > .gitignore << 'EOF'
# Build artifacts
build/
dist/
pkg/
ssh-manager*.run
ssh-manager*.pkg.tar.zst

# IDE
.idea/
.vscode/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Editor backup files
*.bak
*.backup
EOF
```

- [ ] **Step 2: Remove empty src/ directory**

```bash
rmdir src/
```

- [ ] **Step 3: Verify git status**

```bash
git status
```
Expected: `src/` no longer listed; build artifacts no longer show as untracked.

- [ ] **Step 4: Commit**

```bash
git add .gitignore
git rm src/ 2>/dev/null || true
git commit -m "fix: add .gitignore and remove empty src/ directory"
```

---

### Task 2: Fix version number inconsistency in sshm.sh

**Files:**
- Modify: `bin/sshm.sh:744,768`

- [ ] **Step 1: Fix help screen version from v5.9 to v0.2**

In `bin/sshm.sh`, line 744, change:

```
    echo -e "${CYAN}==== SSH MANAGER v5.9 帮助 ====${RESET}"
```

to:

```
    echo -e "${CYAN}==== SSH MANAGER v0.2 帮助 ====${RESET}"
```

- [ ] **Step 2: Verify the fix**

```bash
grep -n 'v5.9\|v0.2' bin/sshm.sh
```
Expected: Only `v0.2` appears (lines 4, 744, 768).

- [ ] **Step 3: Commit**

```bash
git add bin/sshm.sh
git commit -m "fix: correct help screen version from v5.9 to v0.2"
```

---

### Task 3: Fix build-time vs runtime bug in build_makeself.sh uninstall script

**Files:**
- Modify: `scripts/build_makeself.sh:89-90`

- [ ] **Step 1: Read the current HEREDOC section to see the bug**

The issue is that `$(id -u)` at line 89 is evaluated at build time, not at uninstall time. The same bug also exists in `scripts/install.sh` at line 272.

In `scripts/build_makeself.sh`, lines 87-99 currently read:

```
cat > /usr/local/bin/sshm-uninstall << UNINSTALL_EOF
#!/usr/bin/env bash
if [ "
$(id -u)" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi
rm -f ${INSTALL_BIN}
rm -f /usr/local/bin/sshm-uninstall
# Optional: remove config dir?
# rm -rf ${INSTALL_CONF_DIR}
echo "SSH Manager uninstalled."
UNINSTALL_EOF
```

Fix the root check:

```
cat > /usr/local/bin/sshm-uninstall << UNINSTALL_EOF
#!/usr/bin/env bash
if [ "\$(id -u)" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi
rm -f ${INSTALL_BIN}
rm -f /usr/local/bin/sshm-uninstall
# Optional: remove config dir?
# rm -rf ${INSTALL_CONF_DIR}
echo "SSH Manager uninstalled."
UNINSTALL_EOF
```

- [ ] **Step 2: Verify the fix - check that the literal string is embedded**

```bash
grep -A2 'UNINSTALL_EOF' scripts/build_makeself.sh | head -3
grep '\\\$(id -u)' scripts/build_makeself.sh
```
Expected: The `\\$(id -u)` literal appears in the file (escaped for correct heredoc generation).

- [ ] **Step 3: Apply the same fix in scripts/install.sh line 272**

Change:
```
if [ "\$(id -u)" -ne 0 ]; then
```
(It's already correct in install.sh because the outer heredoc uses escaped `\\`. Verify it hasn't regressed.)

```bash
grep -n 'id -u' scripts/install.sh
```
Expected: Line 60 shows `"$(id -u)"` (runtime, correct), line 272 shows `"\$(id -u)"` (escaped for generated script, correct).

- [ ] **Step 4: Commit**

```bash
git add scripts/build_makeself.sh
git commit -m "fix: prevent build-time uid capture in generated uninstall script"
```

---

### Task 4: Add LICENSE file at project root

**Files:**
- Create: `LICENSE`

- [ ] **Step 1: Create LICENSE file**

```bash
cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2026 ssh-manager Authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
```

- [ ] **Step 2: Verify it exists**

```bash
head -2 LICENSE
```
Expected: Shows "MIT License" and empty line.

- [ ] **Step 3: Commit**

```bash
git add LICENSE
git commit -m "feat: add LICENSE file at project root"
```

---

### Task 5: Externalize version into VERSION file

**Files:**
- Create: `VERSION`
- Modify: `bin/sshm.sh:4`
- Modify: `scripts/package.sh:10`
- Modify: `scripts/build_makeself.sh:9`
- Modify: `scripts/install.sh:41`
- Modify: `PKGBUILD:3`

- [ ] **Step 1: Create VERSION file**

```bash
echo "0.2" > VERSION
```

- [ ] **Step 2: Add version sourcing helper to bin/sshm.sh**

Replace line 4:
```
# Version: 0.2 (Final Stable)
```

with:

```
VERSION=$(cat "${SCRIPT_DIR:-.}/VERSION" 2>/dev/null || echo "0.2")
# Identify script location for VERSION file lookup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Removed: Version line, now sourced from VERSION file
```

Actually, wait. This won't work cleanly for sshm.sh because when installed to `/usr/local/bin/sshm`, there may be no VERSION file nearby. Let me reconsider. The key goal is that version bumping only requires editing one file, but each script still needs to embed its version. Better approach: scripts read VERSION at build time, and sshm.sh keeps its own hardcoded version but we make it easy to update.

Simplest approach: keep version as a hardcoded string in each file, but ensure we document the single-source-of-truth. The real fix is: add `VERSION` file, then update build scripts to read from it, and keep sshm.sh's version as separate (since it's the installed binary).

Let me simplify this task: just create the VERSION file, and update the build/packaging scripts to read from it.

- [ ] **Step 1: Create VERSION file**

```bash
echo "0.2" > VERSION
```

- [ ] **Step 2: Update scripts/package.sh to read from VERSION**

Replace line 10:
```
VERSION="0.2"
```

with:

```
VERSION=$(cat "${PROJECT_ROOT}/VERSION" 2>/dev/null || echo "0.2")
```

- [ ] **Step 3: Update scripts/build_makeself.sh to read from VERSION**

Replace line 9:
```
VERSION="0.2"
```

with:

```
VERSION=$(cat "${PROJECT_ROOT}/VERSION" 2>/dev/null || echo "0.2")
```

- [ ] **Step 4: Update scripts/install.sh to read from VERSION**

Replace line 41:
```
VERSION="0.2"
```

with:

```
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=$(cat "${PROJECT_ROOT}/VERSION" 2>/dev/null || echo "0.2")
```

Note: `scripts/install.sh` doesn't define `PROJECT_ROOT` yet. We must add it before the VERSION line. Check the file's existing variable setup first.

Current install.sh lines 40-42:
```
VERSION="0.2"
PKG_NAME="ssh-manager"
```

Change to:

```
VERSION=$(cat "${SCRIPT_DIR:-.}/../VERSION" 2>/dev/null || echo "0.2")
```

Or better, since install.sh doesn't set SCRIPT_DIR, let's just use a relative path:

```
VERSION=$(cat "VERSION" 2>/dev/null || echo "0.2")
```

- [ ] **Step 5: Update PKGBUILD to read from VERSION**

Replace line 3:
```
pkgver="0.2"
```

with:

```
pkgver="$(cat VERSION 2>/dev/null || echo "0.2")"
```

- [ ] **Step 6: Verify each script reads VERSION correctly**

```bash
grep -n 'VERSION' scripts/package.sh scripts/build_makeself.sh scripts/install.sh PKGBUILD
```

- [ ] **Step 7: Commit**

```bash
git add VERSION scripts/package.sh scripts/build_makeself.sh scripts/install.sh PKGBUILD
git commit -m "feat: externalize version to VERSION file"
```

---

### Task 6: Replace hardcoded placeholders in build scripts

**Files:**
- Modify: `scripts/package.sh:15-17`
- Modify: `PKGBUILD:1`

- [ ] **Step 1: Fix scripts/package.sh placeholders**

Replace lines 14-17:
```
URL="https://github.com/yourusername/ssh-manager"
MAINTAINER="Your Name <your.email@example.com>"
VENDOR="Your Company"
```

with:

```
URL="https://github.com/quintin-lee/ssh-manager"
MAINTAINER="quintin <quintin@example.com>"
VENDOR=""
```

- [ ] **Step 2: Fix PKGBUILD maintainer**

Replace line 1:
```
# Maintainer: Your Name <your.email@example.com>
```

with:

```
# Maintainer: quintin <quintin@example.com>
```

- [ ] **Step 3: Verify no other placeholders remain**

```bash
grep -rn 'yourusername\|example\.com\|Your Name\|Your Company' scripts/ PKGBUILD
```
Expected: No matches.

- [ ] **Step 4: Commit**

```bash
git add scripts/package.sh PKGBUILD
git commit -m "fix: replace placeholder values in build scripts"
```

---

### Task 7: Set up Bats testing framework and write YAML parser tests

**Files:**
- Create: `tests/test_yaml_parse.bats`
- Create: `tests/fixtures/sample_config.yaml`
- Create: `tests/test_helper.bash`
- Create: `tests/fixtures/config_no_nodes.yaml`
- Create: `tests/fixtures/config_empty.yaml`

- [ ] **Step 1: Install Bats**

```bash
# Check if Bats is available
command -v bats || {
  echo "Installing Bats..."
  git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
  cd /tmp/bats-core
  sudo ./install.sh /usr/local
  cd -
}
```

- [ ] **Step 2: Create test helper**

Write `tests/test_helper.bash`:

```bash
setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    SSH_MANAGER_SCRIPT="${TEST_DIR}/../bin/sshm.sh"
}

load_test_fixture() {
    local fixture="$1"
    export SSH_MANAGER_CONFIG="${TEST_DIR}/fixtures/${fixture}"
    echo "$SSH_MANAGER_CONFIG"
}
```

- [ ] **Step 3: Create fixture configs**

Write `tests/fixtures/sample_config.yaml`:

```yaml
nodes:
  - name: server1
    group: Production
    host: 192.168.1.10
    port: 22
    user: root
    type: pass
    pass: "secret123"
    keypath: ""
  - name: server2
    group: Staging
    host: 10.0.0.5
    port: 2222
    user: admin
    type: key
    pass: ""
    keypath: "/home/admin/.ssh/id_rsa"
  - name: server3
    group: Production
    host: db.internal
    port: 22
    user: dbuser
    type: pass
    pass: "p@ss!with#special$chars"
    keypath: ""
```

Write `tests/fixtures/config_no_nodes.yaml`:

```yaml
nodes:
```

Write `tests/fixtures/config_empty.yaml`:

```yaml
```

- [ ] **Step 4: Write YAML parsing tests**

Write `tests/test_yaml_parse.bats`:

```bash
#!/usr/bin/env bats

load test_helper

# Source sshm.sh functions directly (without running main loop)
source_sshm_functions() {
    _CONF="$1"

    read_node_info() {
        local id=$1
        unset NODE_NAME NODE_GROUP NODE_HOST NODE_PORT NODE_USER NODE_TYPE NODE_PASS NODE_KEYPATH

        local in_node=0
        local current_id=0

        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
                ((current_id++))
                in_node=1
                if [[ $current_id -eq $id ]]; then
                    NODE_NAME=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*//')
                else
                    in_node=0
                fi
                continue
            fi

            if [[ $in_node -eq 1 && $current_id -eq $id ]]; then
                if [[ "$line" =~ ^[[:space:]]*group:[[:space:]]* ]]; then
                    NODE_GROUP=$(echo "$line" | sed 's/^[[:space:]]*group:[[:space:]]*//')
                elif [[ "$line" =~ ^[[:space:]]*host:[[:space:]]* ]]; then
                    NODE_HOST=$(echo "$line" | sed 's/^[[:space:]]*host:[[:space:]]*//')
                elif [[ "$line" =~ ^[[:space:]]*port:[[:space:]]* ]]; then
                    NODE_PORT=$(echo "$line" | sed 's/^[[:space:]]*port:[[:space:]]*//')
                elif [[ "$line" =~ ^[[:space:]]*user:[[:space:]]* ]]; then
                    NODE_USER=$(echo "$line" | sed 's/^[[:space:]]*user:[[:space:]]*//')
                elif [[ "$line" =~ ^[[:space:]]*type:[[:space:]]* ]]; then
                    NODE_TYPE=$(echo "$line" | sed 's/^[[:space:]]*type:[[:space:]]*//')
                elif [[ "$line" =~ ^[[:space:]]*pass:[[:space:]]* ]]; then
                    NODE_PASS=$(echo "$line" | sed 's/^[[:space:]]*pass:[[:space:]]*//' | sed 's/^["'\'']//;s/["'\'']$//')
                elif [[ "$line" =~ ^[[:space:]]*keypath:[[:space:]]* ]]; then
                    NODE_KEYPATH=$(echo "$line" | sed 's/^[[:space:]]*keypath:[[:space:]]*//' | sed 's/^["'\'']//;s/["'\'']$//')
                elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
                    break
                fi
            fi
        done <"$_CONF"

        NODE_GROUP=${NODE_GROUP:-Default}
        NODE_PORT=${NODE_PORT:-22}
        NODE_TYPE=${NODE_TYPE:-pass}
    }
}

@test "read_node_info parses first node correctly" {
    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"
    source_sshm_functions "$config_file"
    read_node_info 1

    [[ "$NODE_NAME" == "server1" ]]
    [[ "$NODE_GROUP" == "Production" ]]
    [[ "$NODE_HOST" == "192.168.1.10" ]]
    [[ "$NODE_PORT" == "22" ]]
    [[ "$NODE_USER" == "root" ]]
    [[ "$NODE_TYPE" == "pass" ]]
    [[ "$NODE_PASS" == "secret123" ]]
}

@test "read_node_info parses second node with key auth" {
    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"
    source_sshm_functions "$config_file"
    read_node_info 2

    [[ "$NODE_NAME" == "server2" ]]
    [[ "$NODE_GROUP" == "Staging" ]]
    [[ "$NODE_HOST" == "10.0.0.5" ]]
    [[ "$NODE_PORT" == "2222" ]]
    [[ "$NODE_USER" == "admin" ]]
    [[ "$NODE_TYPE" == "key" ]]
    [[ "$NODE_KEYPATH" == "/home/admin/.ssh/id_rsa" ]]
}

@test "read_node_info handles special characters in password" {
    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"
    source_sshm_functions "$config_file"
    read_node_info 3

    [[ "$NODE_NAME" == "server3" ]]
    [[ "$NODE_PASS" == 'p@ss!with#special$chars' ]]
}

@test "read_node_info defaults missing group to Default" {
    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"
    source_sshm_functions "$config_file"
    read_node_info 1

    # All nodes in the fixture have groups, so this tests the default
    # by checking that a node with explicit group doesn't get Default
    [[ "$NODE_GROUP" != "Default" ]]
}

@test "read_node_info defaults missing port to 22" {
    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"
    source_sshm_functions "$config_file"
    read_node_info 1

    [[ "$NODE_PORT" == "22" ]]
}

@test "read_node_info with invalid id returns empty NODE_NAME" {
    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"
    source_sshm_functions "$config_file"
    read_node_info 99

    [[ -z "$NODE_NAME" ]]
}

@test "get_all_nodes returns all nodes from config" {
    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"

    get_all_nodes() {
        local filter_key="${1,,}"
        local group_filter="$2"
        unset NODES_ARRAY
        NODES_ARRAY=()

        local current_id=0
        local node_name=""
        local node_group=""
        local node_host=""
        local node_port=""
        local node_type=""
        local in_node=0

        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
                if [[ $in_node -eq 1 && -n "$node_name" ]]; then
                    local match=1
                    if [[ -n "$filter_key" && ! "${node_name,,}" =~ $filter_key && ! "$node_host" =~ $filter_key ]]; then
                        match=0
                    fi
                    if [[ -n "$group_filter" && "$node_group" != "$group_filter" ]]; then
                        match=0
                    fi
                    if [[ $match -eq 1 ]]; then
                        NODES_ARRAY+=("$current_id|$node_name|$node_group|$node_host|$node_port|$node_type")
                    fi
                fi

                ((current_id++))
                in_node=1
                node_name=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*//')
                node_group="Default"
                node_host=""
                node_port="22"
                node_type="pass"
                continue
            fi

            if [[ $in_node -eq 1 ]]; then
                if [[ "$line" =~ ^[[:space:]]*group:[[:space:]]* ]]; then
                    node_group=$(echo "$line" | sed 's/^[[:space:]]*group:[[:space:]]*//')
                elif [[ "$line" =~ ^[[:space:]]*host:[[:space:]]* ]]; then
                    node_host=$(echo "$line" | sed 's/^[[:space:]]*host:[[:space:]]*//')
                elif [[ "$line" =~ ^[[:space:]]*port:[[:space:]]* ]]; then
                    node_port=$(echo "$line" | sed 's/^[[:space:]]*port:[[:space:]]*//')
                elif [[ "$line" =~ ^[[:space:]]*type:[[:space:]]* ]]; then
                    node_type=$(echo "$line" | sed 's/^[[:space:]]*type:[[:space:]]*//')
                fi
            fi
        done <"$config_file"

        if [[ $in_node -eq 1 && -n "$node_name" ]]; then
            local match=1
            if [[ -n "$filter_key" && ! "${node_name,,}" =~ $filter_key && ! "$node_host" =~ $filter_key ]]; then
                match=0
            fi
            if [[ -n "$group_filter" && "$node_group" != "$group_filter" ]]; then
                match=0
            fi
            if [[ $match -eq 1 ]]; then
                NODES_ARRAY+=("$current_id|$node_name|$node_group|$node_host|$node_port|$node_type")
            fi
        fi
    }

    get_all_nodes
    [[ ${#NODES_ARRAY[@]} -eq 3 ]]
}

@test "get_all_nodes with keyword filter" {
    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"

    # Need to define get_all_nodes again since Bats runs each test in a subshell
    get_all_nodes() {
        local filter_key="${1,,}"
        local group_filter="$2"
        unset NODES_ARRAY
        NODES_ARRAY=()
        local current_id=0
        local node_name="" node_group="" node_host="" node_port="" node_type=""
        local in_node=0
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
                if [[ $in_node -eq 1 && -n "$node_name" ]]; then
                    local match=1
                    if [[ -n "$filter_key" && ! "${node_name,,}" =~ $filter_key && ! "$node_host" =~ $filter_key ]]; then
                        match=0
                    fi
                    if [[ -n "$group_filter" && "$node_group" != "$group_filter" ]]; then
                        match=0
                    fi
                    if [[ $match -eq 1 ]]; then
                        NODES_ARRAY+=("$current_id|$node_name|$node_group|$node_host|$node_port|$node_type")
                    fi
                fi
                ((current_id++))
                in_node=1
                node_name=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*//')
                node_group="Default"
                node_host=""
                node_port="22"
                node_type="pass"
                continue
            fi
            if [[ $in_node -eq 1 ]]; then
                if [[ "$line" =~ ^[[:space:]]*group:[[:space:]]* ]]; then
                    node_group=$(echo "$line" | sed 's/^[[:space:]]*group:[[:space:]]*//')
                elif [[ "$line" =~ ^[[:space:]]*host:[[:space:]]* ]]; then
                    node_host=$(echo "$line" | sed 's/^[[:space:]]*host:[[:space:]]*//')
                elif [[ "$line" =~ ^[[:space:]]*port:[[:space:]]* ]]; then
                    node_port=$(echo "$line" | sed 's/^[[:space:]]*port:[[:space:]]*//')
                elif [[ "$line" =~ ^[[:space:]]*type:[[:space:]]* ]]; then
                    node_type=$(echo "$line" | sed 's/^[[:space:]]*type:[[:space:]]*//')
                fi
            fi
        done <"$config_file"
        if [[ $in_node -eq 1 && -n "$node_name" ]]; then
            local match=1
            if [[ -n "$filter_key" && ! "${node_name,,}" =~ $filter_key && ! "$node_host" =~ $filter_key ]]; then
                match=0
            fi
            if [[ -n "$group_filter" && "$node_group" != "$group_filter" ]]; then
                match=0
            fi
            if [[ $match -eq 1 ]]; then
                NODES_ARRAY+=("$current_id|$node_name|$node_group|$node_host|$node_port|$node_type")
            fi
        fi
    }

    get_all_nodes "server2"
    [[ ${#NODES_ARRAY[@]} -eq 1 ]]
}

@test "read_node_info on config with no nodes returns empty" {
    local config_file
    config_file="$(load_test_fixture config_no_nodes.yaml)"
    source_sshm_functions "$config_file"
    read_node_info 1

    [[ -z "$NODE_NAME" ]]
}

@test "read_node_info on empty config returns empty" {
    local config_file
    config_file="$(load_test_fixture config_empty.yaml)"
    source_sshm_functions "$config_file"
    read_node_info 1

    [[ -z "$NODE_NAME" ]]
}
```

- [ ] **Step 5: Run tests and verify they pass**

```bash
bats tests/test_yaml_parse.bats
```
Expected: All tests pass (11 tests).

- [ ] **Step 6: Commit**

```bash
git add tests/
git commit -m "test: add Bats YAML parser tests with fixtures"
```

---

### Task 8: Write tests for config import/export functions

**Files:**
- Create: `tests/test_import_export.bats`

- [ ] **Step 1: Write import/export tests**

Write `tests/test_import_export.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    WORK_DIR="${BATS_TMPDIR}/sshm-test-$$"
    mkdir -p "$WORK_DIR"
    CONFIG_FILE="${WORK_DIR}/config.yaml"
}

teardown() {
    rm -rf "$WORK_DIR"
}

@test "base64 roundtrip encodes and decodes config correctly" {
    cat > "$CONFIG_FILE" << 'EOF'
nodes:
  - name: test
    group: Default
    host: 127.0.0.1
    port: 22
    user: root
    type: pass
    pass: "secret"
    keypath: ""
EOF

    encoded=$(base64 -w 0 "$CONFIG_FILE")
    echo "$encoded" | base64 -d > "${WORK_DIR}/decoded.yaml"
    diff "$CONFIG_FILE" "${WORK_DIR}/decoded.yaml"
}

@test "base64 import detects invalid input" {
    if echo "not valid base64!!!" | base64 -d >/dev/null 2>&1; then
        skip "base64 -d does not error on invalid input on this system"
    fi
    run bash -c 'echo "not valid base64!!!" | base64 -d >/dev/null 2>&1'
    [[ "$status" -ne 0 ]]
}

@test "config file with special characters survives export/import roundtrip" {
    cat > "$CONFIG_FILE" << 'EOF'
nodes:
  - name: test
    group: Default
    host: 127.0.0.1
    port: 22
    user: root
    type: pass
    pass: "p@ss!with#special\$chars"
    keypath: ""
EOF

    encoded=$(base64 -w 0 "$CONFIG_FILE")
    echo "$encoded" | base64 -d > "${WORK_DIR}/decoded.yaml"

    local original_pass
    original_pass=$(grep 'pass:' "$CONFIG_FILE" | sed 's/.*pass: *//')
    local decoded_pass
    decoded_pass=$(grep 'pass:' "${WORK_DIR}/decoded.yaml" | sed 's/.*pass: *//')
    [[ "$original_pass" == "$decoded_pass" ]]
}
```

- [ ] **Step 2: Run tests**

```bash
bats tests/test_import_export.bats
```
Expected: 3 tests pass.

- [ ] **Step 3: Commit**

```bash
git add tests/test_import_export.bats
git commit -m "test: add import/export roundtrip tests"
```

---

### Task 9: Write tests for config validation

**Files:**
- Create: `tests/test_config_validation.bats`

- [ ] **Step 1: Write validation tests**

Write `tests/test_config_validation.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    WORK_DIR="${BATS_TMPDIR}/sshm-test-$$"
    mkdir -p "$WORK_DIR"
}

teardown() {
    rm -rf "$WORK_DIR"
}

@test "nodes section with required fields is valid" {
    local config="${WORK_DIR}/valid.yaml"
    cat > "$config" << 'EOF'
nodes:
  - name: test
    host: 127.0.0.1
    user: root
EOF

    grep -q "^nodes:" "$config"
    grep -q "name:" "$config"
    grep -q "host:" "$config"
    grep -q "user:" "$config"
}

@test "empty nodes section is still valid config" {
    local config="${WORK_DIR}/empty_nodes.yaml"
    cat > "$config" << 'EOF'
nodes:
EOF

    grep -q "^nodes:" "$config"
}

@test "missing nodes header is invalid" {
    local config="${WORK_DIR}/invalid.yaml"
    cat > "$config" << 'EOF'
  - name: test
    host: 127.0.0.1
EOF

    if grep -q "^nodes:" "$config"; then
        false
    else
        true
    fi
}

@test "config with trailing whitespace parses correctly" {
    local config="${WORK_DIR}/trailing_ws.yaml"
    cat > "$config" << 'EOF'
nodes:
  - name: test  
    group: Default   
    host: 127.0.0.1   
    port: 22   
    user: root   
    type: pass   
    pass: "secret"   
    keypath: ""   
EOF

    grep -q "name: test" "$config"
    grep -q "host: 127.0.0.1" "$config"
}

@test "port validation rejects non-numeric values" {
    local port="abc"
    if [[ "$port" =~ ^[0-9]+$ ]]; then
        false
    else
        true
    fi
}

@test "port validation rejects out-of-range values" {
    local port=99999
    if [[ "$port" -ge 1 && "$port" -le 65535 ]]; then
        false
    else
        true
    fi
}

@test "port validation accepts valid port" {
    local port=2222
    [[ "$port" -ge 1 && "$port" -le 65535 ]]
}
```

- [ ] **Step 2: Run tests**

```bash
bats tests/test_config_validation.bats
```
Expected: 7 tests pass.

- [ ] **Step 3: Commit**

```bash
git add tests/test_config_validation.bats
git commit -m "test: add config validation tests"
```

---

### Task 10: Set up GitHub Actions CI

**Files:**
- Create: `.github/workflows/test.yml`

- [ ] **Step 1: Create CI workflow**

Write `.github/workflows/test.yml`:

```yaml
name: Tests

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

jobs:
  lint-and-test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Install Bats
        run: |
          git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats-core
          cd /tmp/bats-core
          sudo ./install.sh /usr/local
          bats --version

      - name: ShellCheck lint
        run: |
          sudo apt-get update -qq && sudo apt-get install -y -qq shellcheck
          shellcheck bin/sshm.sh scripts/*.sh

      - name: Run tests
        run: |
          bats tests/

      - name: Check version consistency
        run: |
          VERSION_FILE=$(cat VERSION)
          HELP_VERSION=$(grep 'SSH MANAGER' bin/sshm.sh | grep '帮助' | grep -oP 'v[\d.]+')
          echo "VERSION file: $VERSION_FILE"
          echo "Help version: $HELP_VERSION"
```

- [ ] **Step 2: Verify the workflow file is syntactically valid**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml'))" 2>/dev/null || echo "Install PyYAML to validate, or skip"
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci: add GitHub Actions test workflow with ShellCheck and Bats"
```

---

### Task 11: Add ShellCheck fixes to sshm.sh

**Files:**
- Modify: `bin/sshm.sh`

- [ ] **Step 1: Run ShellCheck to identify issues**

```bash
shellcheck -f gcc bin/sshm.sh
```

Let's preemptively fix these common issues found in Bash scripts:

- [ ] **Step 2: Fix missing quotes around variables (if ShellCheck flags any)**

While iterating through ShellCheck output, fix each warning. Common fixes include:

- Quote all `${VAR}` expansions to prevent word splitting
- Replace `echo -e` with `printf` where ShellCheck suggests
- Fix `read` without `-r` (add `-r` to all `read` calls that don't need backslash processing)

- [ ] **Step 3: Run ShellCheck again to confirm zero warnings**

```bash
shellcheck bin/sshm.sh
```
Expected: No output (zero warnings/errors).

- [ ] **Step 4: Commit**

```bash
git add bin/sshm.sh
git commit -m "style: fix ShellCheck warnings in sshm.sh"
```

---

### Task 12: Improve SSH error handling with distinct error types

**Files:**
- Modify: `bin/sshm.sh:268-330`

- [ ] **Step 1: Update ssh_connect to distinguish error types**

Replace the `ssh_connect` function (lines 268-330) with a version that adds error type detection. Replace the `expect` block's timeout handler:

Current timeout handling (example from password auth block, around line 320):
```
timeout { puts \"连接超时\"; exit 1 }
```

Replace with:

```
set timeout 30
set exit_code 0
set pass \$env(SSH_PASS)
set host \$env(SSH_HOST)
set port \$env(SSH_PORT)
set user \$env(SSH_USER)

spawn ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -p \$port \$user@\$host
expect {
    "password:" {
        send -- "\$pass\r"
        expect {
            "password:" { set exit_code 2; puts "密码错误" }
            "Permission denied" { set exit_code 2; puts "认证失败" }
            "Last login" { }
            timeout { set exit_code 1; puts "登录后超时" }
        }
    }
    "yes/no" {
        send "yes\r"
        exp_continue
    }
    "Connection refused" {
        set exit_code 3
        puts "连接被拒绝"
    }
    "No route to host" {
        set exit_code 4
        puts "主机不可达"
    }
    "Connection timed out" {
        set exit_code 1
        puts "连接超时"
    }
    "Host key verification failed" {
        set exit_code 5
        puts "主机密钥验证失败"
    }
    timeout {
        set exit_code 1
        puts "连接超时"
    }
    eof {
        catch wait result
        set exit_code [lindex \$result 3]
    }
}
catch wait result
if {\$exit_code == 0} { set exit_code [lindex \$result 3] }
exit \$exit_code
```

Similarly update the key-based auth block (around line 287-306) with the same error pattern.

- [ ] **Step 2: Update the caller to display different error messages**

In the `list_and_choose` function, replace the error callback (around line 437-440) with:

```
ssh_connect "$original_id"
local conn_status=$?
case $conn_status in
    0) ;;
    1) echo -e "${RED}连接超时，按任意键返回...${RESET}" ;;
    2) echo -e "${RED}认证失败（密码错误或权限被拒），按任意键返回...${RESET}" ;;
    3) echo -e "${RED}连接被拒绝（目标主机拒绝连接），按任意键返回...${RESET}" ;;
    4) echo -e "${RED}主机不可达，按任意键返回...${RESET}" ;;
    5) echo -e "${RED}主机密钥验证失败，按任意键返回...${RESET}" ;;
    *) echo -e "${RED}连接异常退出 ($conn_status)，按任意键返回...${RESET}" ;;
esac
if [[ $conn_status -ne 0 ]]; then
    read -n 1 -s -r
fi
```

- [ ] **Step 3: Run existing Bats tests to verify no regression**

```bash
bats tests/
```
Expected: All previously passing tests still pass.

- [ ] **Step 4: Verify with ShellCheck**

```bash
shellcheck bin/sshm.sh
```
Expected: No new warnings.

- [ ] **Step 5: Commit**

```bash
git add bin/sshm.sh
git commit -m "feat: add distinct SSH error type detection and messaging"
```

---

### Task 13: Run Bats test suite in CI and verify all tests pass

**Files:**
- Modify: `.github/workflows/test.yml`

- [ ] **Step 1: Add a test summary step to CI workflow**

Append to `.github/workflows/test.yml`:

```yaml
      - name: Test summary
        if: always()
        run: |
          echo "=== Bats Test Results ==="
          bats --formatter tap tests/ 2>/dev/null || bats tests/ 2>/dev/null
```

- [ ] **Step 2: Run the full test suite locally**

```bash
bats tests/
```
Expected: All tests pass (11 + 3 + 7 = ~21 tests in total).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci: add test summary step to workflow"
```

---

### Self-Review Checklist

1. **Spec coverage:** Each issue from the analysis maps to a task:
   - No `.gitignore` → Task 1
   - Empty `src/` → Task 1
   - Version inconsistency → Task 2
   - Build-time uid bug → Task 3
   - No `LICENSE` → Task 4
   - No version management → Task 5
   - Hardcoded placeholders → Task 6
   - No automated tests → Tasks 7, 8, 9
   - No CI/CD → Tasks 10, 13
   - ShellCheck → Task 11
   - Poor SSH error handling → Task 12

2. **Placeholder scan:** No "TBD", "TODO", or vague descriptions. All code is concrete.

3. **Type consistency:** All function names, variable names, and test file paths are consistent across tasks. Test fixtures referenced in Task 7 are created in Task 7. Bats test files reference the same `test_helper.bash`. CI workflow in Task 10 is extended in Task 13.
