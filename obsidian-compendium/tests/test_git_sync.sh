#!/usr/bin/env bash
# obsidian-compendium Git 自动同步 测试用例
#
# 用法: bash tests/test_git_sync.sh
# 依赖: git
#
# 测试策略:
#   1. 检测条件（非 git / 无 remote / 无 upstream / 全满足）
#   2. Commit（从 diff 总结 message / 无变更跳过）
#   3. Push（成功 / 失败后自主恢复）
#   4. 端到端完整流程

set -euo pipefail

PASSED=0
FAILED=0
TOTAL=0
TEST_ROOT=""

# ============ 工具函数 ============

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

# 断言字符串包含子串
assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  ✅ $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $desc (在 '$haystack' 中未找到 '$needle')"
    FAILED=$((FAILED + 1))
  fi
}

# 断言字符串不为空
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

# 模拟 skill 中的同步检测逻辑
check_sync_conditions() {
  local dir="$1"
  cd "$dir"

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "skip:not_git"
    return
  fi

  if [[ -z "$(git remote 2>/dev/null)" ]]; then
    echo "skip:no_remote"
    return
  fi

  if ! git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    echo "skip:no_upstream"
    return
  fi

  echo "sync"
}

# 模拟 skill 的新 commit 逻辑：从 diff 中总结 message
# 返回 "nothing" 或 commit message
summarize_and_commit() {
  local dir="$1"
  cd "$dir"
  git add -A

  if git diff --cached --quiet; then
    echo "nothing"
    return
  fi

  # 模拟 skill 行为：读取 diff stat 总结 message
  local stat
  stat=$(git diff --cached --stat)

  # 从变更文件名中提取关键信息来组装 message
  # 实际场景由 Claude 阅读 diff 自行总结，这里模拟该过程
  # 用 -z 避免中文路径被转义为八进制
  local changed_files
  changed_files=$(git diff --cached --name-only -z | tr '\0' '\n')

  local msg=""
  local has_index=false
  local has_note=false
  local note_name=""

  while IFS= read -r f; do
    case "$f" in
      *_index.md) has_index=true ;;
      *.md)
        has_note=true
        note_name=$(basename "$f" .md)
        ;;
    esac
  done <<< "$changed_files"

  # 模拟 Claude 从变更中总结 message 的行为
  if $has_note && $has_index; then
    msg="docs: 新增 ${note_name} 笔记并更新索引"
  elif $has_note; then
    msg="docs: 新增 ${note_name} 笔记"
  elif $has_index; then
    msg="chore: 更新知识库索引"
  else
    msg="chore: 更新知识库文件"
  fi

  git commit -m "$msg" >/dev/null 2>&1
  echo "$msg"
}

# 模拟 push 并在失败时尝试自主恢复
# 返回: "pushed" / "recovered_and_pushed" / "unrecoverable:<reason>"
do_push_with_recovery() {
  local dir="$1"
  cd "$dir"

  # 第一次尝试 push
  if git push 2>/dev/null; then
    echo "pushed"
    return
  fi

  # push 失败，尝试自主恢复
  local push_err
  push_err=$(git push 2>&1 || true)

  # 判断是否为远端领先（rejected, non-fast-forward）
  if echo "$push_err" | grep -qE "(rejected|non-fast-forward|fetch first)"; then
    # 尝试 pull --rebase 后重新 push
    if git pull --rebase 2>/dev/null && git push 2>/dev/null; then
      echo "recovered_and_pushed"
      return
    fi
  fi

  # 判断是否为网络/权限等不可恢复问题
  echo "unrecoverable"
}

# 创建带有 remote + upstream 的标准测试仓库
create_synced_repo() {
  local dir="$1"
  local bare="$2"

  git init -q --bare "$bare"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git commit --allow-empty -m "init" -q
  git remote add origin "$bare"
  git push -u origin "$(git branch --show-current)" -q 2>/dev/null
}

# ============ 测试用例 ============

test_1_not_a_git_repo() {
  echo "测试 1: 非 git 仓库 → 静默跳过"
  local dir="$TEST_ROOT/not_git"
  mkdir -p "$dir"
  echo "# test" > "$dir/note.md"

  local result
  result=$(check_sync_conditions "$dir")
  assert_eq "检测结果为 skip:not_git" "skip:not_git" "$result"
}

test_2_git_repo_no_remote() {
  echo "测试 2: git 仓库但无 remote → 静默跳过"
  local dir="$TEST_ROOT/no_remote"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git commit --allow-empty -m "init" -q

  local result
  result=$(check_sync_conditions "$dir")
  assert_eq "检测结果为 skip:no_remote" "skip:no_remote" "$result"
}

test_3_git_repo_remote_no_upstream() {
  echo "测试 3: 有 remote 但当前分支无上游跟踪 → 静默跳过"
  local dir="$TEST_ROOT/no_upstream"
  local bare="$TEST_ROOT/bare_remote.git"

  git init -q --bare "$bare"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git commit --allow-empty -m "init" -q
  git remote add origin "$bare"

  local result
  result=$(check_sync_conditions "$dir")
  assert_eq "检测结果为 skip:no_upstream" "skip:no_upstream" "$result"
}

test_4_full_sync_conditions_met() {
  echo "测试 4: 有 remote + 有 upstream → 应执行同步"
  local dir="$TEST_ROOT/full_sync"
  local bare="$TEST_ROOT/bare_full.git"

  create_synced_repo "$dir" "$bare"

  local result
  result=$(check_sync_conditions "$dir")
  assert_eq "检测结果为 sync" "sync" "$result"
}

test_5_commit_message_from_diff_single_note() {
  echo "测试 5: 单篇笔记变更 → message 应包含笔记名"
  local dir="$TEST_ROOT/single_note"
  local bare="$TEST_ROOT/bare_single.git"

  create_synced_repo "$dir" "$bare"

  echo "# React Hooks 入门" > "$dir/React-Hooks-入门.md"

  local msg
  msg=$(summarize_and_commit "$dir")
  assert_not_empty "commit message 非空" "$msg"
  assert_contains "message 包含笔记名" "$msg" "React-Hooks"
}

test_6_commit_message_from_diff_note_and_index() {
  echo "测试 6: 笔记+索引变更 → message 应同时反映笔记和索引"
  local dir="$TEST_ROOT/note_index"
  local bare="$TEST_ROOT/bare_ni.git"

  create_synced_repo "$dir" "$bare"

  mkdir -p "$dir/后端"
  echo "# Spring DI" > "$dir/后端/Spring-DI.md"
  echo "# 索引" > "$dir/后端/_index.md"

  local msg
  msg=$(summarize_and_commit "$dir")
  assert_not_empty "commit message 非空" "$msg"
  assert_contains "message 包含笔记名" "$msg" "Spring-DI"
  assert_contains "message 提及索引" "$msg" "索引"
}

test_7_commit_nothing_to_commit() {
  echo "测试 7: 无文件变更 → 静默跳过 commit"
  local dir="$TEST_ROOT/nothing"

  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git commit --allow-empty -m "init" -q

  local result
  result=$(summarize_and_commit "$dir")
  assert_eq "结果为 nothing" "nothing" "$result"
}

test_8_push_success() {
  echo "测试 8: push 到本地 bare repo → 直接推送成功"
  local dir="$TEST_ROOT/push_ok"
  local bare="$TEST_ROOT/bare_push_ok.git"

  create_synced_repo "$dir" "$bare"

  echo "# push test" > "$dir/push-note.md"
  summarize_and_commit "$dir" >/dev/null

  local result
  result=$(do_push_with_recovery "$dir")
  assert_eq "push 结果为 pushed" "pushed" "$result"

  # 验证远端收到了 commit
  local remote_count local_count
  remote_count=$(cd "$bare" && git rev-list --count HEAD)
  local_count=$(cd "$dir" && git rev-list --count HEAD)
  assert_eq "远端 commit 数与本地一致" "$local_count" "$remote_count"
}

test_9_push_behind_remote_then_recover() {
  echo "测试 9: 远端领先（有新 commit）→ 自主 pull rebase 后 push 成功"
  local dir="$TEST_ROOT/behind"
  local bare="$TEST_ROOT/bare_behind.git"
  local other="$TEST_ROOT/other_clone"

  create_synced_repo "$dir" "$bare"

  # 用另一个 clone 往远端推一个 commit，制造"远端领先"
  git clone -q "$bare" "$other"
  cd "$other"
  echo "# from other" > "other-note.md"
  git add -A && git commit -m "other commit" -q
  git push -q 2>/dev/null

  # 本地也产生一个 commit
  cd "$dir"
  echo "# local note" > "local-note.md"
  summarize_and_commit "$dir" >/dev/null

  # 此时 push 应该失败，然后自主恢复
  local result
  result=$(do_push_with_recovery "$dir")
  assert_eq "恢复后推送成功" "recovered_and_pushed" "$result"

  # 验证两个 commit 都到了远端
  local remote_files
  remote_files=$(cd "$bare" && git ls-tree -r HEAD --name-only -z | tr '\0' '\n')
  assert_contains "远端包含 other-note" "$remote_files" "other-note.md"
  assert_contains "远端包含 local-note" "$remote_files" "local-note.md"
}

test_10_push_unrecoverable() {
  echo "测试 10: 不可达 remote → 标记为不可恢复"
  local dir="$TEST_ROOT/unrecoverable"

  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git commit --allow-empty -m "init" -q
  git remote add origin "ssh://invalid-host/nonexistent.git"
  git config "branch.$(git branch --show-current).remote" origin
  git config "branch.$(git branch --show-current).merge" "refs/heads/$(git branch --show-current)"

  echo "# fail" > "$dir/fail-note.md"
  summarize_and_commit "$dir" >/dev/null

  local result
  result=$(do_push_with_recovery "$dir")
  assert_eq "结果为 unrecoverable" "unrecoverable" "$result"
}

test_11_end_to_end() {
  echo "测试 11: 端到端完整流程（检测 → 从 diff 总结 commit → push）"
  local dir="$TEST_ROOT/e2e"
  local bare="$TEST_ROOT/bare_e2e.git"

  create_synced_repo "$dir" "$bare"

  mkdir -p "$dir/学习/技术/后端"

  cat > "$dir/学习/技术/后端/Java-Spring-DI.md" << 'EOF'
---
创建时间: 2026-04-13 15:00
标签: [Java, Spring, 依赖注入]
---

# Spring 依赖注入核心概念

## 核心要点
Spring IoC 容器通过构造器注入或 Setter 注入管理 Bean 依赖关系。
EOF

  cat > "$dir/学习/技术/后端/_index.md" << 'EOF'
---
更新时间: 2026-04-13 15:00
笔记总数: 1
---

# 后端 索引

## 本目录笔记

| 笔记 | 一句话摘要 | 标签 | 创建时间 |
|------|-----------|------|---------|
| Java-Spring-DI | Spring IoC 通过构造器/Setter 注入管理依赖 | Java, Spring | 2026-04-13 |
EOF

  # 检测
  local check_result
  check_result=$(check_sync_conditions "$dir")
  assert_eq "检测条件满足" "sync" "$check_result"

  # 从 diff 总结并 commit
  local msg
  msg=$(summarize_and_commit "$dir")
  assert_not_empty "commit message 非空" "$msg"
  assert_contains "message 包含笔记名" "$msg" "Java-Spring-DI"

  # push
  local push_result
  push_result=$(do_push_with_recovery "$dir")
  assert_eq "push 成功" "pushed" "$push_result"

  # 验证远端包含笔记
  local file_in_remote
  file_in_remote=$(cd "$bare" && git ls-tree -r HEAD --name-only -z | tr '\0' '\n' | grep "Java-Spring-DI" || echo "not_found")
  assert_eq "远端包含笔记文件" "学习/技术/后端/Java-Spring-DI.md" "$file_in_remote"
}

test_12_only_index_changes() {
  echo "测试 12: 仅索引变更（无笔记）→ message 应反映索引更新"
  local dir="$TEST_ROOT/index_only"
  local bare="$TEST_ROOT/bare_index.git"

  create_synced_repo "$dir" "$bare"

  mkdir -p "$dir/学习"
  echo "# 索引内容" > "$dir/学习/_index.md"

  local msg
  msg=$(summarize_and_commit "$dir")
  assert_not_empty "commit message 非空" "$msg"
  assert_contains "message 提及索引" "$msg" "索引"
}

# ============ 执行 ============

main() {
  echo "========================================="
  echo " obsidian-compendium Git 自动同步测试"
  echo "========================================="
  echo ""

  setup
  trap teardown EXIT

  test_1_not_a_git_repo
  echo ""
  test_2_git_repo_no_remote
  echo ""
  test_3_git_repo_remote_no_upstream
  echo ""
  test_4_full_sync_conditions_met
  echo ""
  test_5_commit_message_from_diff_single_note
  echo ""
  test_6_commit_message_from_diff_note_and_index
  echo ""
  test_7_commit_nothing_to_commit
  echo ""
  test_8_push_success
  echo ""
  test_9_push_behind_remote_then_recover
  echo ""
  test_10_push_unrecoverable
  echo ""
  test_11_end_to_end
  echo ""
  test_12_only_index_changes
  echo ""

  echo "========================================="
  echo " 结果: $PASSED/$TOTAL 通过, $FAILED 失败"
  echo "========================================="

  [[ $FAILED -eq 0 ]]
}

main
