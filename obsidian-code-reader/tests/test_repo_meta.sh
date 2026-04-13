#!/usr/bin/env bash
# _repo_meta.md 生成与解析测试
#
# 用法: bash obsidian-code-reader/tests/test_repo_meta.sh
#
# 测试:
#   1. 从真实仓库提取元数据（使用 aiot-customer-service-app）
#   2. _repo_meta.md frontmatter 生成与解析
#   3. 文件-笔记映射表生成
#   4. 映射表查询（给定源文件找到对应笔记）
#   5. 解读覆盖统计计算
#   6. 映射表更新（新增/删除条目）

set -euo pipefail

PASSED=0
FAILED=0
TOTAL=0
TEST_ROOT=""

# 测试用真实仓库路径
REAL_REPO="/Users/chenshengtao/codes/aiot-customer-service-app"

setup() {
  TEST_ROOT=$(mktemp -d)
  mkdir -p "$TEST_ROOT/vault/代码解读/aiot-customer-service-app"
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

# ============ 辅助函数 ============

# 从真实仓库提取元数据
extract_repo_info() {
  local repo_path="$1"

  if [[ ! -d "$repo_path/.git" ]]; then
    echo "error:not_git"
    return
  fi

  local repo_name remote_url current_branch latest_commit
  repo_name=$(basename "$repo_path")
  remote_url=$(cd "$repo_path" && git remote get-url origin 2>/dev/null || echo "none")
  current_branch=$(cd "$repo_path" && git branch --show-current 2>/dev/null || echo "unknown")
  latest_commit=$(cd "$repo_path" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")

  echo "ok:${repo_name}|${remote_url}|${current_branch}|${latest_commit}"
}

# 生成 _repo_meta.md 内容
generate_repo_meta() {
  local repo_name="$1" repo_path="$2" remote_url="$3" branch="$4" commit="$5"
  local now
  now=$(date "+%Y-%m-%d %H:%M")

  cat << EOF
---
仓库名称: ${repo_name}
仓库路径: ${repo_path}
远程地址: ${remote_url}
默认分支: ${branch}
上次解读commit: ${commit}
上次解读时间: ${now}
解读分支: ${branch}
---

# 仓库元数据

## 文件-笔记映射

| 源文件/目录 | 对应笔记 | 解读范围 |
|------------|---------|---------|

## 解读覆盖统计

- 已解读文件数: 0
- 仓库总文件数: 0
- 覆盖率: 0/0
EOF
}

# 解析 _repo_meta.md 的 frontmatter 字段
parse_meta_field() {
  local file="$1" field="$2"
  sed -n "/^---$/,/^---$/p" "$file" | grep "^${field}:" | sed "s/^${field}: *//"
}

# 向映射表追加一行
append_mapping() {
  local meta_file="$1" source="$2" note="$3" scope="$4"
  local new_row="| ${source} | [[${note}]] | ${scope} |"
  # 在映射表表头后插入新行
  sed -i '' "/^|------------|---------|---------|$/a\\
${new_row}
" "$meta_file"
}

# 查询映射表：给定源文件，返回对应笔记
lookup_mapping() {
  local meta_file="$1" source_pattern="$2"
  grep "$source_pattern" "$meta_file" | head -1 | sed 's/.*\[\[\(.*\)\]\].*/\1/' || echo "not_found"
}

# 删除映射表中匹配的行
remove_mapping() {
  local meta_file="$1" source_pattern="$2"
  # 转义斜杠，避免 sed 分隔符冲突
  local escaped
  escaped=$(printf '%s' "$source_pattern" | sed 's/[/&]/\\&/g')
  sed -i '' "/${escaped}/d" "$meta_file"
}

# 计算覆盖统计（只计包含 [[ 的行，排除表头）
count_mappings() {
  local meta_file="$1"
  grep -c '\[\[' "$meta_file" 2>/dev/null || echo "0"
}

# ============ 测试用例 ============

test_1_extract_real_repo() {
  echo "测试 1: 从真实仓库 (aiot-customer-service-app) 提取元数据"

  if [[ ! -d "$REAL_REPO/.git" ]]; then
    echo "  ⏭️ 跳过（仓库不存在: $REAL_REPO）"
    return
  fi

  local result
  result=$(extract_repo_info "$REAL_REPO")
  local status
  status=$(echo "$result" | cut -d: -f1)
  assert_eq "提取成功" "ok" "$status"

  local repo_name
  repo_name=$(echo "$result" | cut -d: -f2 | cut -d'|' -f1)
  assert_eq "仓库名称" "aiot-customer-service-app" "$repo_name"

  local branch
  branch=$(echo "$result" | cut -d'|' -f3)
  assert_not_empty "分支非空" "$branch"

  local commit
  commit=$(echo "$result" | cut -d'|' -f4)
  assert_not_empty "commit 非空" "$commit"
}

test_2_extract_non_git() {
  echo "测试 2: 非 git 目录 → error:not_git"
  local dir="$TEST_ROOT/not_git"
  mkdir -p "$dir"

  local result
  result=$(extract_repo_info "$dir")
  assert_eq "返回 error" "error:not_git" "$result"
}

test_3_generate_meta() {
  echo "测试 3: 生成 _repo_meta.md 并验证 frontmatter"
  local meta_file="$TEST_ROOT/vault/代码解读/aiot-customer-service-app/_repo_meta.md"

  generate_repo_meta \
    "aiot-customer-service-app" \
    "/Users/chenshengtao/codes/aiot-customer-service-app" \
    "git@github.com:user/aiot-customer-service-app.git" \
    "master" \
    "9bef59a" \
    > "$meta_file"

  assert_file_exists "文件已生成" "$meta_file"

  local content
  content=$(cat "$meta_file")
  assert_contains "包含仓库名称" "$content" "仓库名称: aiot-customer-service-app"
  assert_contains "包含仓库路径" "$content" "仓库路径: /Users/chenshengtao/codes/aiot-customer-service-app"
  assert_contains "包含远程地址" "$content" "远程地址: git@github.com:user/aiot-customer-service-app.git"
  assert_contains "包含默认分支" "$content" "默认分支: master"
  assert_contains "包含 commit" "$content" "上次解读commit: 9bef59a"
  assert_contains "包含映射表表头" "$content" "文件-笔记映射"
  assert_contains "包含覆盖统计" "$content" "解读覆盖统计"
}

test_4_parse_meta_fields() {
  echo "测试 4: 解析 _repo_meta.md frontmatter 各字段"
  local meta_file="$TEST_ROOT/vault/代码解读/aiot-customer-service-app/_repo_meta.md"

  # 确保文件存在（测试 3 已生成）
  if [[ ! -f "$meta_file" ]]; then
    echo "  ⏭️ 跳过（依赖测试 3 生成的文件）"
    return
  fi

  assert_eq "解析仓库名称" "aiot-customer-service-app" "$(parse_meta_field "$meta_file" "仓库名称")"
  assert_eq "解析默认分支" "master" "$(parse_meta_field "$meta_file" "默认分支")"
  assert_eq "解析 commit" "9bef59a" "$(parse_meta_field "$meta_file" "上次解读commit")"
  assert_eq "解析解读分支" "master" "$(parse_meta_field "$meta_file" "解读分支")"
}

test_5_mapping_crud() {
  echo "测试 5: 映射表增删查"
  local meta_file="$TEST_ROOT/vault/代码解读/aiot-customer-service-app/_repo_meta.md"

  if [[ ! -f "$meta_file" ]]; then
    echo "  ⏭️ 跳过（依赖测试 3 生成的文件）"
    return
  fi

  # 追加映射
  append_mapping "$meta_file" "src/main.ts" "30-模块/10-应用入口" "文件级"
  append_mapping "$meta_file" "electron/main/" "30-模块/20-Electron主进程" "整个目录"
  append_mapping "$meta_file" "src/store/" "30-模块/30-状态管理-Pinia" "整个目录"

  # 查询映射
  local note
  note=$(lookup_mapping "$meta_file" "src/main.ts")
  assert_eq "查询 src/main.ts → 应用入口" "30-模块/10-应用入口" "$note"

  note=$(lookup_mapping "$meta_file" "electron/main/")
  assert_eq "查询 electron/main/ → Electron主进程" "30-模块/20-Electron主进程" "$note"

  # 统计映射数
  local count
  count=$(count_mappings "$meta_file")
  assert_eq "映射条目数为 3" "3" "$count"

  # 删除映射
  remove_mapping "$meta_file" "src/main.ts"
  count=$(count_mappings "$meta_file")
  assert_eq "删除后映射条目数为 2" "2" "$count"

  # 查询已删除的映射
  note=$(lookup_mapping "$meta_file" "src/main.ts")
  assert_eq "已删除的映射查询返回 not_found" "not_found" "$note"
}

test_6_coverage_stats() {
  echo "测试 6: 解读覆盖统计计算"
  local meta_file="$TEST_ROOT/vault/代码解读/aiot-customer-service-app/_repo_meta.md"

  if [[ ! -f "$meta_file" ]]; then
    echo "  ⏭️ 跳过（依赖测试 3 生成的文件）"
    return
  fi

  # 测试 5 中删除了 1 条，剩余 2 条映射
  local mapped_count
  mapped_count=$(count_mappings "$meta_file")
  assert_eq "已映射文件数" "2" "$mapped_count"

  # 模拟仓库总文件数
  local total_files=84
  local coverage
  coverage="${mapped_count}/${total_files}"
  assert_eq "覆盖率格式" "2/84" "$coverage"
}

# ============ 执行 ============

main() {
  echo "========================================="
  echo " _repo_meta.md 生成与解析测试"
  echo "========================================="
  echo ""

  setup
  trap teardown EXIT

  test_1_extract_real_repo
  echo ""
  test_2_extract_non_git
  echo ""
  test_3_generate_meta
  echo ""
  test_4_parse_meta_fields
  echo ""
  test_5_mapping_crud
  echo ""
  test_6_coverage_stats
  echo ""

  echo "========================================="
  echo " 结果: $PASSED/$TOTAL 通过, $FAILED 失败"
  echo "========================================="

  [[ $FAILED -eq 0 ]]
}

main
