#!/usr/bin/env bash
# 增量同步流程测试
#
# 用法: bash obsidian-code-reader/tests/test_sync_flow.sh
#
# 测试:
#   1. git diff 变更检测（M/A/D/R 四种类型）
#   2. 变更文件与映射表比对
#   3. 无变更时的处理
#   4. 影响范围分析（文件级 vs 目录级匹配）
#   5. commit 范围计算
#   6. 端到端：mock 仓库提交变更 → 检测 → 分类

set -euo pipefail

PASSED=0
FAILED=0
TOTAL=0
TEST_ROOT=""

setup() {
  TEST_ROOT=$(mktemp -d)
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

# ============ 辅助函数 ============

# 创建一个带初始提交的 mock 仓库
create_mock_repo() {
  local dir="$1"
  mkdir -p "$dir/src/auth" "$dir/src/utils" "$dir/src/models"

  cd "$dir"
  git init -q

  # 初始文件
  echo 'export function login() {}' > src/auth/login.ts
  echo 'export function verify() {}' > src/auth/verify.ts
  echo 'export function format() {}' > src/utils/format.ts
  echo 'export interface User {}' > src/models/user.ts
  echo '# Project' > README.md

  git add .
  git commit -q -m "init"
}

# 获取变更文件列表（模拟 SKILL.md 步骤 3）
detect_changes() {
  local repo_path="$1" base_commit="$2"
  cd "$repo_path"

  local current_commit
  current_commit=$(git rev-parse HEAD)

  if [[ "$base_commit" == "$current_commit" ]]; then
    echo "no_change"
    return
  fi

  git diff --name-status "${base_commit}..HEAD"
}

# 分类变更（M/A/D/R）
classify_changes() {
  local diff_output="$1"
  local modified="" added="" deleted="" renamed=""

  while IFS=$'\t' read -r status file rest; do
    case "$status" in
      M) modified="${modified}${file}|" ;;
      A) added="${added}${file}|" ;;
      D) deleted="${deleted}${file}|" ;;
      R*) renamed="${renamed}${file}->${rest}|" ;;
    esac
  done <<< "$diff_output"

  echo "M:${modified}A:${added}D:${deleted}R:${renamed}"
}

# 比对变更文件与映射表，找到受影响的笔记
find_affected_notes() {
  local changed_file="$1" mapping_file="$2"

  # 先精确匹配文件路径
  local match
  match=$(grep "| ${changed_file} |" "$mapping_file" 2>/dev/null | head -1 || true)

  if [[ -n "$match" ]]; then
    echo "$match" | sed 's/.*\[\[\(.*\)\]\].*/\1/'
    return
  fi

  # 再模糊匹配目录级（changed_file 的父目录在映射表中）
  local parent_dir
  parent_dir=$(dirname "$changed_file")
  match=$(grep "| ${parent_dir}/" "$mapping_file" 2>/dev/null | head -1 || true)

  if [[ -n "$match" ]]; then
    echo "$match" | sed 's/.*\[\[\(.*\)\]\].*/\1/'
    return
  fi

  echo "unmapped"
}

# 统计两个 commit 之间的提交数
count_commits_between() {
  local repo_path="$1" base="$2" head="$3"
  cd "$repo_path"
  git rev-list --count "${base}..${head}" 2>/dev/null || echo "0"
}

# ============ 测试用例 ============

test_1_detect_modifications() {
  echo "测试 1: 检测文件修改（M）"
  local repo="$TEST_ROOT/repo1"
  create_mock_repo "$repo"

  local base_commit
  base_commit=$(cd "$repo" && git rev-parse HEAD)

  # 修改文件
  echo 'export function login(user: string) {}' > "$repo/src/auth/login.ts"
  cd "$repo" && git add . && git commit -q -m "modify login"

  local diff_output
  diff_output=$(detect_changes "$repo" "$base_commit")
  assert_contains "检测到 login.ts 修改" "$diff_output" "src/auth/login.ts"

  local classified
  classified=$(classify_changes "$diff_output")
  assert_contains "分类为 M" "$classified" "M:src/auth/login.ts"
}

test_2_detect_additions() {
  echo "测试 2: 检测新增文件（A）"
  local repo="$TEST_ROOT/repo2"
  create_mock_repo "$repo"

  local base_commit
  base_commit=$(cd "$repo" && git rev-parse HEAD)

  # 新增文件
  mkdir -p "$repo/src/notification"
  echo 'export function sendEmail() {}' > "$repo/src/notification/email.ts"
  cd "$repo" && git add . && git commit -q -m "add notification"

  local diff_output
  diff_output=$(detect_changes "$repo" "$base_commit")
  assert_contains "检测到新增文件" "$diff_output" "src/notification/email.ts"

  local classified
  classified=$(classify_changes "$diff_output")
  assert_contains "分类为 A" "$classified" "A:src/notification/email.ts"
}

test_3_detect_deletions() {
  echo "测试 3: 检测删除文件（D）"
  local repo="$TEST_ROOT/repo3"
  create_mock_repo "$repo"

  local base_commit
  base_commit=$(cd "$repo" && git rev-parse HEAD)

  # 删除文件
  cd "$repo" && git rm -q src/utils/format.ts && git commit -q -m "remove format"

  local diff_output
  diff_output=$(detect_changes "$repo" "$base_commit")
  assert_contains "检测到删除文件" "$diff_output" "src/utils/format.ts"

  local classified
  classified=$(classify_changes "$diff_output")
  assert_contains "分类为 D" "$classified" "D:src/utils/format.ts"
}

test_4_detect_renames() {
  echo "测试 4: 检测重命名文件（R）"
  local repo="$TEST_ROOT/repo4"
  create_mock_repo "$repo"

  local base_commit
  base_commit=$(cd "$repo" && git rev-parse HEAD)

  # 重命名文件
  cd "$repo" && git mv src/utils/format.ts src/utils/formatter.ts && git commit -q -m "rename format"

  local diff_output
  diff_output=$(detect_changes "$repo" "$base_commit")
  # git diff --name-status 可能输出 R100 或 R+数字
  assert_contains "检测到重命名" "$diff_output" "formatter.ts"
}

test_5_no_changes() {
  echo "测试 5: 无变更 → no_change"
  local repo="$TEST_ROOT/repo5"
  create_mock_repo "$repo"

  local base_commit
  base_commit=$(cd "$repo" && git rev-parse HEAD)

  local result
  result=$(detect_changes "$repo" "$base_commit")
  assert_eq "无变更" "no_change" "$result"
}

test_6_affected_notes_file_level() {
  echo "测试 6: 文件级映射 → 精确匹配受影响笔记"
  local mapping_file="$TEST_ROOT/mapping.md"
  cat > "$mapping_file" << 'EOF'
| 源文件/目录 | 对应笔记 | 解读范围 |
|------------|---------|---------|
| src/auth/login.ts | [[30-模块/10-认证模块-登录]] | 文件级 |
| src/auth/verify.ts | [[30-模块/20-认证模块-验证]] | 文件级 |
| src/models/user.ts | [[50-数据模型/10-用户模型]] | 文件级 |
EOF

  local note
  note=$(find_affected_notes "src/auth/login.ts" "$mapping_file")
  assert_eq "精确匹配 login.ts" "30-模块/10-认证模块-登录" "$note"

  note=$(find_affected_notes "src/models/user.ts" "$mapping_file")
  assert_eq "精确匹配 user.ts" "50-数据模型/10-用户模型" "$note"
}

test_7_affected_notes_dir_level() {
  echo "测试 7: 目录级映射 → 子文件变更匹配到目录笔记"
  local mapping_file="$TEST_ROOT/mapping2.md"
  cat > "$mapping_file" << 'EOF'
| 源文件/目录 | 对应笔记 | 解读范围 |
|------------|---------|---------|
| src/auth/ | [[30-模块/10-认证模块-总览]] | 整个目录 |
| src/store/ | [[30-模块/20-状态管理-Pinia]] | 整个目录 |
EOF

  local note
  note=$(find_affected_notes "src/auth/jwt.ts" "$mapping_file")
  assert_eq "目录级匹配 auth 子文件" "30-模块/10-认证模块-总览" "$note"

  note=$(find_affected_notes "src/store/user.ts" "$mapping_file")
  assert_eq "目录级匹配 store 子文件" "30-模块/20-状态管理-Pinia" "$note"
}

test_8_unmapped_file() {
  echo "测试 8: 未映射的文件 → unmapped"
  local mapping_file="$TEST_ROOT/mapping3.md"
  cat > "$mapping_file" << 'EOF'
| 源文件/目录 | 对应笔记 | 解读范围 |
|------------|---------|---------|
| src/auth/login.ts | [[30-模块/10-认证模块-登录]] | 文件级 |
EOF

  local note
  note=$(find_affected_notes "src/new/feature.ts" "$mapping_file")
  assert_eq "未映射文件" "unmapped" "$note"
}

test_9_commit_count() {
  echo "测试 9: commit 范围计算"
  local repo="$TEST_ROOT/repo9"
  create_mock_repo "$repo"

  local base_commit
  base_commit=$(cd "$repo" && git rev-parse HEAD)

  # 连续提交 3 次
  cd "$repo"
  echo "change1" >> README.md && git add . && git commit -q -m "commit 1"
  echo "change2" >> README.md && git add . && git commit -q -m "commit 2"
  echo "change3" >> README.md && git add . && git commit -q -m "commit 3"

  local count
  count=$(count_commits_between "$repo" "$base_commit" "HEAD")
  assert_eq "3 次提交" "3" "$count"
}

test_10_mixed_changes() {
  echo "测试 10: 混合变更（M+A+D）同时存在"
  local repo="$TEST_ROOT/repo10"
  create_mock_repo "$repo"

  local base_commit
  base_commit=$(cd "$repo" && git rev-parse HEAD)

  cd "$repo"
  # 修改
  echo 'export function login(u: string) {}' > src/auth/login.ts
  # 新增
  mkdir -p src/cache
  echo 'export class CacheManager {}' > src/cache/manager.ts
  # 删除
  git rm -q src/utils/format.ts

  git add . && git commit -q -m "mixed changes"

  local diff_output
  diff_output=$(detect_changes "$repo" "$base_commit")

  local classified
  classified=$(classify_changes "$diff_output")
  assert_contains "包含修改" "$classified" "M:src/auth/login.ts"
  assert_contains "包含新增" "$classified" "A:src/cache/manager.ts"
  assert_contains "包含删除" "$classified" "D:src/utils/format.ts"
}

# ============ 执行 ============

main() {
  echo "========================================="
  echo " 增量同步流程测试"
  echo "========================================="
  echo ""

  setup
  trap teardown EXIT

  test_1_detect_modifications
  echo ""
  test_2_detect_additions
  echo ""
  test_3_detect_deletions
  echo ""
  test_4_detect_renames
  echo ""
  test_5_no_changes
  echo ""
  test_6_affected_notes_file_level
  echo ""
  test_7_affected_notes_dir_level
  echo ""
  test_8_unmapped_file
  echo ""
  test_9_commit_count
  echo ""
  test_10_mixed_changes
  echo ""

  echo "========================================="
  echo " 结果: $PASSED/$TOTAL 通过, $FAILED 失败"
  echo "========================================="

  [[ $FAILED -eq 0 ]]
}

main
