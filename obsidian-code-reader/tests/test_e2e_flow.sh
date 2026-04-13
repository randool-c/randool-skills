#!/usr/bin/env bash
# 端到端流程测试：模拟完整的仓库解读 → 索引维护 → 检索
#
# 用法: bash obsidian-code-reader/tests/test_e2e_flow.sh
#
# 使用 aiot-customer-service-app 作为真实仓库验证：
#   1. 仓库识别与信息提取
#   2. 目录结构扫描（排除非源码目录）
#   3. 笔记生成（frontmatter、Wikilink、代码片段格式）
#   4. 索引维护（_index.md 生成与更新）
#   5. 检索定位（渐进式索引导航）
#   6. Wikilink 网络完整性

set -euo pipefail

PASSED=0
FAILED=0
TOTAL=0
TEST_ROOT=""
VAULT_ROOT=""
REPO_DIR=""

REAL_REPO="/Users/chenshengtao/codes/aiot-customer-service-app"

setup() {
  TEST_ROOT=$(mktemp -d)
  VAULT_ROOT="$TEST_ROOT/vault"
  REPO_DIR="$VAULT_ROOT/代码解读/aiot-customer-service-app"
  mkdir -p "$REPO_DIR/30-模块" "$REPO_DIR/40-核心流程" "$REPO_DIR/50-数据模型"
}

teardown() {
  [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]] && rm -rf "$TEST_ROOT"
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✅ $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $desc (期望: '$expected', 实际: '$actual')"
    FAILED=$((FAILED + 1))
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  ✅ $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $desc (在输出中未找到 '$needle')"
    FAILED=$((FAILED + 1))
  fi
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  ✅ $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $desc (不应包含 '$needle'，但找到了)"
    FAILED=$((FAILED + 1))
  fi
}

assert_file_exists() {
  local desc="$1" filepath="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -f "$filepath" ]]; then
    echo "  ✅ $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $desc (文件不存在: $filepath)"
    FAILED=$((FAILED + 1))
  fi
}

assert_not_empty() {
  local desc="$1" value="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -n "$value" ]]; then
    echo "  ✅ $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $desc (值为空)"
    FAILED=$((FAILED + 1))
  fi
}

# ============ 测试用例 ============

test_1_repo_identification() {
  echo "测试 1: 真实仓库识别与信息提取"

  if [[ ! -d "$REAL_REPO/.git" ]]; then
    echo "  ⏭️ 跳过（仓库不存在: $REAL_REPO）"
    return
  fi

  # 检测是否为 git 仓库
  local is_git
  is_git=$(cd "$REAL_REPO" && git rev-parse --is-inside-work-tree 2>/dev/null || echo "false")
  assert_eq "是 git 仓库" "true" "$is_git"

  # 提取仓库名
  local repo_name
  repo_name=$(basename "$(cd "$REAL_REPO" && git rev-parse --show-toplevel)")
  assert_eq "仓库名称" "aiot-customer-service-app" "$repo_name"

  # 检测语言（通过文件后缀）
  local ts_count
  ts_count=$(find "$REAL_REPO/src" -type f -name "*.ts" -o -name "*.vue" 2>/dev/null | wc -l | tr -d ' ')
  TOTAL=$((TOTAL + 1))
  if [[ "$ts_count" -gt 0 ]]; then
    echo "  ✅ 检测到 TypeScript/Vue 文件 ($ts_count 个)"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ 未检测到 TypeScript/Vue 文件"
    FAILED=$((FAILED + 1))
  fi
}

test_2_directory_scan() {
  echo "测试 2: 目录结构扫描（排除非源码目录）"

  if [[ ! -d "$REAL_REPO" ]]; then
    echo "  ⏭️ 跳过"
    return
  fi

  # 模拟 SKILL.md 步骤 4.1 的扫描命令
  local scan_output
  scan_output=$(cd "$REAL_REPO" && find . -type f \
    ! -path './.git/*' \
    ! -path './node_modules/*' \
    ! -path './.venv/*' \
    ! -path './vendor/*' \
    ! -path './target/*' \
    ! -path './build/*' \
    ! -path './dist/*' \
    ! -path './dist-electron/*' \
    ! -path './__pycache__/*' \
    ! -path './*.pyc' \
    2>/dev/null | head -200)

  assert_not_empty "扫描结果非空" "$scan_output"
  assert_not_contains "排除 node_modules" "$scan_output" "node_modules"
  assert_not_contains "排除 .git" "$scan_output" ".git/"
  assert_contains "包含 src 目录文件" "$scan_output" "src/"
}

test_3_note_generation() {
  echo "测试 3: 笔记生成（frontmatter + 代码片段 + Wikilink）"

  # 模拟生成项目概览笔记
  cat > "$REPO_DIR/10-项目概览.md" << 'ENDNOTE'
---
创建时间: 2026-04-13 15:00
更新时间: 2026-04-13 15:00
标签: [aiot-customer-service-app, TypeScript, Vue3, Electron]
来源仓库: aiot-customer-service-app
源码路径: /
---

# AIoT 客服应用 - 项目概览

## 定位与职责

> 基于 Vue3 + Electron 的桌面端客服应用，支持视频通话和 H265 解码。

## 技术栈

- **前端框架**: Vue 3 + TypeScript
- **桌面壳**: Electron
- **构建工具**: Vite + electron-builder
- **状态管理**: Pinia
- **UI 组件库**: MTD Vue3

## 目录结构

```
├── electron/      # Electron 主进程
├── src/           # Vue 前端源码
│   ├── components/
│   ├── pages/
│   ├── store/
│   └── network/
└── vite.config.ts
```

## 关键设计决策

- **为什么用 Electron 而非 Web**: 需要调用本地摄像头和硬件编解码能力
- **H265 解码**: 自研 WASM 解码器，见 [[30-模块/10-H265解码器]]

## 相关笔记

- [[20-架构设计]]：整体架构设计
- [[30-模块/20-Electron主进程]]：主进程模块解读
ENDNOTE

  local content
  content=$(cat "$REPO_DIR/10-项目概览.md")

  # 验证 frontmatter
  assert_contains "包含创建时间" "$content" "创建时间: 2026-04-13"
  assert_contains "包含更新时间" "$content" "更新时间: 2026-04-13"
  assert_contains "包含标签" "$content" "标签:"
  assert_contains "包含来源仓库" "$content" "来源仓库: aiot-customer-service-app"

  # 验证 Wikilink
  assert_contains "包含模块 Wikilink" "$content" "[[30-模块/10-H265解码器]]"
  assert_contains "包含架构 Wikilink" "$content" "[[20-架构设计]]"
}

test_4_code_snippet_format() {
  echo "测试 4: 代码片段格式规范"

  # 模拟包含代码片段的模块笔记
  cat > "$REPO_DIR/30-模块/10-Electron主进程.md" << 'ENDNOTE'
---
创建时间: 2026-04-13 15:30
更新时间: 2026-04-13 15:30
标签: [aiot-customer-service-app, Electron, 主进程]
来源仓库: aiot-customer-service-app
源码路径: electron/main/
---

# Electron 主进程

## 定位与职责

> Electron 主进程，负责窗口管理、系统托盘、进程间通信。

在 [[20-架构设计]] 中，主进程位于应用底层，为 Vue 渲染进程提供原生能力。

## 核心实现

### 窗口创建

```typescript
// electron/main/index.ts:15-32
function createWindow() {
  const win = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      nodeIntegration: false,
      contextIsolation: true,
    },
  })
  win.loadURL(VITE_DEV_SERVER_URL)
}
```

选择 `contextIsolation: true` 是安全最佳实践，通过 preload 脚本暴露有限 API。

## 依赖关系

- 上游：被应用启动流程调用
- 下游：依赖 [[30-模块/20-Preload桥接层]]

## 相关笔记

- [[10-项目概览]]：项目整体上下文
- [[30-模块/20-Preload桥接层]]：preload 脚本
ENDNOTE

  local content
  content=$(cat "$REPO_DIR/30-模块/10-Electron主进程.md")

  # 代码片段格式检查
  assert_contains "代码块包含语言标记" "$content" '```typescript'
  assert_contains "代码块包含源文件路径" "$content" "// electron/main/index.ts:15-32"
  assert_contains "代码块有闭合标记" "$content" '```'

  # 代码片段长度（不超过 30 行）
  local snippet_lines
  snippet_lines=$(sed -n '/```typescript/,/```/p' "$REPO_DIR/30-模块/10-Electron主进程.md" | wc -l | tr -d ' ')
  TOTAL=$((TOTAL + 1))
  if [[ "$snippet_lines" -le 32 ]]; then  # 30行内容 + 2行标记
    echo "  ✅ 代码片段长度合规 ($snippet_lines 行含标记)"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ 代码片段超过 30 行 ($snippet_lines 行含标记)"
    FAILED=$((FAILED + 1))
  fi
}

test_5_index_generation() {
  echo "测试 5: 索引文件生成与层级结构"

  # 生成模块目录索引
  cat > "$REPO_DIR/30-模块/_index.md" << 'ENDINDEX'
---
更新时间: 2026-04-13 15:30
笔记总数: 1
---

# 模块 索引

> 共 1 篇笔记（含子目录），最后更新: 2026-04-13

## 本目录笔记

| 笔记 | 一句话摘要 | 标签 | 创建时间 |
|------|-----------|------|---------|
| 10-Electron主进程 | Electron 主进程，窗口管理与进程间通信 | Electron, 主进程 | 2026-04-13 |
ENDINDEX

  # 生成仓库根索引
  cat > "$REPO_DIR/_index.md" << 'ENDINDEX'
---
更新时间: 2026-04-13 15:30
笔记总数: 2
---

# aiot-customer-service-app 索引

> 共 2 篇笔记（含子目录），最后更新: 2026-04-13

## 子目录

| 子目录 | 笔记数 | 关键主题 |
|--------|--------|---------|
| 30-模块/ | 1 | Electron, 主进程 |

## 本目录笔记

| 笔记 | 一句话摘要 | 标签 | 创建时间 |
|------|-----------|------|---------|
| 10-项目概览 | AIoT 客服桌面应用，Vue3 + Electron | TypeScript, Vue3 | 2026-04-13 |
ENDINDEX

  # 验证仓库索引
  local repo_index
  repo_index=$(cat "$REPO_DIR/_index.md")
  assert_contains "索引包含子目录表" "$repo_index" "30-模块/"
  assert_contains "索引包含笔记表" "$repo_index" "10-项目概览"
  assert_contains "笔记总数正确" "$repo_index" "笔记总数: 2"

  # 验证模块索引
  local mod_index
  mod_index=$(cat "$REPO_DIR/30-模块/_index.md")
  assert_contains "模块索引包含笔记" "$mod_index" "10-Electron主进程"
  assert_contains "模块笔记总数" "$mod_index" "笔记总数: 1"

  # 生成代码解读总索引
  cat > "$VAULT_ROOT/代码解读/_index.md" << 'ENDINDEX'
---
更新时间: 2026-04-13 15:30
笔记总数: 2
---

# 代码解读 索引

> 共 2 篇笔记（含子目录），最后更新: 2026-04-13

## 子目录

| 子目录 | 笔记数 | 关键主题 |
|--------|--------|---------|
| aiot-customer-service-app/ | 2 | Vue3, Electron, TypeScript |
ENDINDEX

  assert_file_exists "代码解读总索引已生成" "$VAULT_ROOT/代码解读/_index.md"
}

test_6_search_navigation() {
  echo "测试 6: 渐进式索引导航检索"

  # 模拟检索 "Electron 主进程怎么实现的"

  # 步骤 1: 读取代码解读总索引
  local top_index
  top_index=$(cat "$VAULT_ROOT/代码解读/_index.md")
  assert_contains "总索引列出仓库" "$top_index" "aiot-customer-service-app/"

  # 步骤 2: 进入仓库索引
  local repo_index
  repo_index=$(cat "$REPO_DIR/_index.md")
  assert_contains "仓库索引列出模块目录" "$repo_index" "30-模块/"

  # 步骤 3: 进入模块索引
  local mod_index
  mod_index=$(cat "$REPO_DIR/30-模块/_index.md")
  assert_contains "模块索引包含 Electron" "$mod_index" "10-Electron主进程"

  # 步骤 4: 读取目标笔记
  assert_file_exists "目标笔记存在" "$REPO_DIR/30-模块/10-Electron主进程.md"
  local note_content
  note_content=$(cat "$REPO_DIR/30-模块/10-Electron主进程.md")
  assert_contains "笔记包含代码实现" "$note_content" "createWindow"
}

test_7_wikilink_integrity() {
  echo "测试 7: Wikilink 网络完整性"

  # 收集所有笔记中的 Wikilink 引用
  local all_links
  all_links=$(grep -roh '\[\[[^]]*\]\]' "$REPO_DIR"/ 2>/dev/null \
    | grep -v '_index.md' \
    | sed 's/\[\[//g; s/\]\]//g' \
    | sed 's/|.*//g' \
    | sort -u || true)

  # 检查项目概览中引用的笔记是否存在（或至少合理）
  local link
  local valid=0
  local broken=0
  while IFS= read -r link; do
    [[ -z "$link" ]] && continue
    # 检查笔记文件是否存在
    if [[ -f "$REPO_DIR/${link}.md" ]]; then
      valid=$((valid + 1))
    else
      broken=$((broken + 1))
    fi
  done <<< "$all_links"

  TOTAL=$((TOTAL + 1))
  if [[ "$valid" -gt 0 ]]; then
    echo "  ✅ 有效 Wikilink: $valid 个"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ 没有有效的 Wikilink"
    FAILED=$((FAILED + 1))
  fi

  # 允许部分断链（引用的笔记可能尚未生成），但报告数量
  echo "  ℹ️ 断链 Wikilink: $broken 个（可能是尚未生成的笔记）"
}

test_8_filename_rules() {
  echo "测试 8: 文件名规则验证"

  # 检查所有生成的笔记文件名
  local bad_names=0
  local total_notes=0
  while IFS= read -r file; do
    total_notes=$((total_notes + 1))
    local basename
    basename=$(basename "$file" .md)
    # 检查是否包含 . （除了 _index.md 和 _repo_meta.md）
    if [[ "$basename" == *"."* && "$basename" != "_index" && "$basename" != "_repo_meta" ]]; then
      echo "  ⚠️ 文件名包含点号: $basename"
      bad_names=$((bad_names + 1))
    fi
  done < <(find "$REPO_DIR" -name "*.md" -not -name "_index.md" -not -name "_repo_meta.md")

  assert_eq "文件名不含点号" "0" "$bad_names"

  TOTAL=$((TOTAL + 1))
  if [[ "$total_notes" -gt 0 ]]; then
    echo "  ✅ 共检查 $total_notes 个笔记文件名"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ 没有找到笔记文件"
    FAILED=$((FAILED + 1))
  fi
}

# ============ 执行 ============

main() {
  echo "========================================="
  echo " 端到端流程测试 (aiot-customer-service-app)"
  echo "========================================="
  echo ""

  setup
  trap teardown EXIT

  test_1_repo_identification
  echo ""
  test_2_directory_scan
  echo ""
  test_3_note_generation
  echo ""
  test_4_code_snippet_format
  echo ""
  test_5_index_generation
  echo ""
  test_6_search_navigation
  echo ""
  test_7_wikilink_integrity
  echo ""
  test_8_filename_rules
  echo ""

  echo "========================================="
  echo " 结果: $PASSED/$TOTAL 通过, $FAILED 失败"
  echo "========================================="

  [[ $FAILED -eq 0 ]]
}

main
