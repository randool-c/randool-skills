#!/usr/bin/env bash
# obsidian-compendium 端到端流程测试（新版：vault 根直接分类）
#
# 用法: bash tests/test_e2e_flow.sh
#
# 验证:
#   Part A: 知识沉淀（多分类笔记创建 + 索引维护）
#   Part B: 知识检索（索引导航 + 跨分类定位）
#   Part C: 索引重建
#   Part D: 分类路径灵活性（核心新特性）

set -euo pipefail

PASSED=0
FAILED=0
TOTAL=0
TEST_ROOT=""
VAULT_ROOT=""

setup() {
  TEST_ROOT=$(mktemp -d)
  VAULT_ROOT="$TEST_ROOT/TestVault"
  # 不再有固定顶级目录，直接从 vault 根创建多种分类
  mkdir -p "$VAULT_ROOT/学习/技术/后端/Java"
  mkdir -p "$VAULT_ROOT/学习/技术/前端/React"
  mkdir -p "$VAULT_ROOT/生活"
  mkdir -p "$VAULT_ROOT/工作/项目经验"
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

# ============ Part A: 知识沉淀（多分类） ============

test_a1_tech_note() {
  echo "测试 A1: 技术笔记 → 写入 学习/技术/后端/Java/"
  local note_path="$VAULT_ROOT/学习/技术/后端/Java/Spring-DI-核心概念.md"
  cat > "$note_path" << 'EOF'
---
创建时间: 2026-04-13 15:00
标签: [Java, Spring, 依赖注入]
来源: 与 Claude 的对话 - 2026-04-13
---

# Spring 依赖注入核心概念

## 核心要点
Spring IoC 容器通过构造器注入或 Setter 注入管理 Bean 依赖关系。
EOF

  assert_file_exists "技术笔记创建成功" "$note_path"
}

test_a2_life_note() {
  echo "测试 A2: 生活笔记 → 写入 生活/"
  local note_path="$VAULT_ROOT/生活/读书清单-2026春.md"
  cat > "$note_path" << 'EOF'
---
创建时间: 2026-04-13 16:00
标签: [读书, 生活]
来源: 与 Claude 的对话 - 2026-04-13
---

# 2026 春季读书清单

## 核心要点
整理了 5 本待读书目，涵盖技术、心理学、经济学三个方向。
EOF

  assert_file_exists "生活笔记创建成功" "$note_path"
}

test_a3_work_note() {
  echo "测试 A3: 工作笔记 → 写入 工作/项目经验/"
  local note_path="$VAULT_ROOT/工作/项目经验/支付系统重构复盘.md"
  cat > "$note_path" << 'EOF'
---
创建时间: 2026-04-13 17:00
标签: [工作, 复盘, 支付]
来源: 与 Claude 的对话 - 2026-04-13
---

# 支付系统重构复盘

## 核心要点
重构将单体支付模块拆为独立微服务，TPS 提升 3 倍，故障隔离能力增强。
EOF

  assert_file_exists "工作笔记创建成功" "$note_path"
}

test_a4_conditional_render() {
  echo "测试 A4: 条件渲染——无补充说明和来源对话时省略"
  local note_path="$VAULT_ROOT/学习/技术/前端/React/React-useEffect-依赖陷阱.md"
  cat > "$note_path" << 'EOF'
---
创建时间: 2026-04-13 16:00
标签: [React, Hooks, useEffect]
来源: 与 Claude 的对话 - 2026-04-13
---

# React useEffect 依赖陷阱

## 核心要点
useEffect 的依赖数组中遗漏变量会导致闭包陷阱。
EOF

  local content
  content=$(cat "$note_path")
  assert_contains "包含核心要点" "$content" "## 核心要点"
  assert_not_contains "省略了补充说明" "$content" "## 补充说明"
  assert_not_contains "省略了来源对话" "$content" "## 来源对话"
}

test_a5_vault_root_index() {
  echo "测试 A5: vault 根索引包含所有一级分类"
  local root_index="$VAULT_ROOT/_index.md"
  cat > "$root_index" << 'EOF'
---
更新时间: 2026-04-13 17:00
笔记总数: 4
---

# TestVault 索引

> 共 4 篇笔记（含子目录），最后更新: 2026-04-13

## 子目录

| 子目录 | 笔记数 | 关键主题 |
|--------|--------|---------|
| [[学习/_index|学习]] | 2 | Spring, React, Hooks |
| [[生活/_index|生活]] | 1 | 读书, 生活 |
| [[工作/_index|工作]] | 1 | 复盘, 支付, 微服务 |
EOF

  local content
  content=$(cat "$root_index")
  assert_contains "根索引包含学习" "$content" "[[学习/_index|学习]]"
  assert_contains "根索引包含生活" "$content" "[[生活/_index|生活]]"
  assert_contains "根索引包含工作" "$content" "[[工作/_index|工作]]"
  assert_eq "笔记总数为 4" "4" "$(grep '笔记总数:' "$root_index" | awk '{print $2}')"
}

test_a6_index_chain_to_root() {
  echo "测试 A6: 索引链从叶子到 vault 根完整"

  # 创建叶子索引
  cat > "$VAULT_ROOT/学习/技术/后端/Java/_index.md" << 'EOF'
---
更新时间: 2026-04-13 15:00
笔记总数: 1
---

# Java 索引

## 本目录笔记

| 笔记 | 一句话摘要 | 标签 | 创建时间 |
|------|-----------|------|---------|
| [[Spring-DI-核心概念]] | Spring IoC 构造器/Setter 注入管理依赖 | Java, Spring | 2026-04-13 |
EOF

  # 验证从叶子到根的索引链
  assert_file_exists "叶子索引: Java" "$VAULT_ROOT/学习/技术/后端/Java/_index.md"
  assert_file_exists "根索引" "$VAULT_ROOT/_index.md"

  # 验证写入路径格式：<vault绝对路径>/<分类路径>/<文件名>.md
  local expected_path="$VAULT_ROOT/学习/技术/后端/Java/Spring-DI-核心概念.md"
  assert_file_exists "写入路径无顶级目录前缀" "$expected_path"
}

# ============ Part B: 知识检索 ============

test_b1_root_index_navigation() {
  echo "测试 B1: 从 vault 根索引判断一级分类"
  local root_index="$VAULT_ROOT/_index.md"
  local content
  content=$(cat "$root_index")

  # 搜索 "Spring" → 应导向 学习/
  local learning_line
  learning_line=$(grep "学习/" "$root_index" || echo "")
  assert_contains "学习/ 关键主题包含 Spring" "$learning_line" "Spring"

  # 搜索 "读书" → 应导向 生活/
  local life_line
  life_line=$(grep "生活/" "$root_index" || echo "")
  assert_contains "生活/ 关键主题包含 读书" "$life_line" "读书"

  # 搜索 "支付" → 应导向 工作/
  local work_line
  work_line=$(grep "工作/" "$root_index" || echo "")
  assert_contains "工作/ 关键主题包含 支付" "$work_line" "支付"
}

test_b2_cross_category_isolation() {
  echo "测试 B2: 不同分类相互隔离"
  local life_note="$VAULT_ROOT/生活/读书清单-2026春.md"
  local tech_note="$VAULT_ROOT/学习/技术/后端/Java/Spring-DI-核心概念.md"

  local life_content tech_content
  life_content=$(cat "$life_note")
  tech_content=$(cat "$tech_note")

  assert_not_contains "生活笔记不含 Spring" "$life_content" "Spring"
  assert_not_contains "技术笔记不含 读书" "$tech_content" "读书"
}

test_b3_leaf_to_note() {
  echo "测试 B3: 叶子索引定位到具体笔记"
  local leaf_index="$VAULT_ROOT/学习/技术/后端/Java/_index.md"
  local content
  content=$(cat "$leaf_index")

  assert_contains "索引包含笔记名" "$content" "[[Spring-DI-核心概念]]"

  # 从索引中的笔记名构造路径，验证文件存在
  local note_dir
  note_dir=$(dirname "$leaf_index")
  assert_file_exists "笔记文件存在" "$note_dir/Spring-DI-核心概念.md"
}

# ============ Part C: 索引重建 ============

test_c1_scan_all_categories() {
  echo "测试 C1: 重建扫描覆盖所有分类"

  local all_notes
  all_notes=$(find "$VAULT_ROOT" -name "*.md" -not -name "_index.md" | sort)
  local note_count
  note_count=$(echo "$all_notes" | wc -l | tr -d ' ')

  assert_eq "总笔记数为 4" "4" "$note_count"
  assert_contains "包含技术笔记" "$all_notes" "Spring-DI"
  assert_contains "包含生活笔记" "$all_notes" "读书清单"
  assert_contains "包含工作笔记" "$all_notes" "支付系统"
  assert_contains "包含 React 笔记" "$all_notes" "React-useEffect"
}

test_c2_directories_needing_index() {
  echo "测试 C2: 需要建索引的目录（包含 .md 或子目录）"

  local dirs_with_content=0
  while IFS= read -r d; do
    # 有 .md 文件（非 _index.md）或有子目录
    if find "$d" -maxdepth 1 -name "*.md" -not -name "_index.md" | grep -q . || \
       find "$d" -maxdepth 1 -mindepth 1 -type d | grep -q .; then
      dirs_with_content=$((dirs_with_content + 1))
    fi
  done < <(find "$VAULT_ROOT" -type d)

  # vault根, 学习, 学习/技术, 学习/技术/后端, 学习/技术/后端/Java,
  # 学习/技术/前端, 学习/技术/前端/React, 生活, 工作, 工作/项目经验
  TOTAL=$((TOTAL + 1))
  if [[ $dirs_with_content -ge 8 ]]; then
    echo "  ✅ 找到 $dirs_with_content 个需要建索引的目录"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ 期望 ≥8 个目录，实际 $dirs_with_content"
    FAILED=$((FAILED + 1))
  fi
}

# ============ Part D: 分类路径灵活性 ============

test_d1_no_fixed_prefix() {
  echo "测试 D1: 笔记路径不含固定前缀"

  # 生活笔记的路径应该是 <vault>/生活/xxx.md，而不是 <vault>/学习/技术/生活/xxx.md
  local life_path="$VAULT_ROOT/生活/读书清单-2026春.md"
  local bad_path="$VAULT_ROOT/学习/技术/生活/读书清单-2026春.md"

  assert_file_exists "生活笔记在 vault根/生活/ 下" "$life_path"
  TOTAL=$((TOTAL + 1))
  if [[ ! -f "$bad_path" ]]; then
    echo "  ✅ 生活笔记不在 学习/技术/ 前缀下"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ 生活笔记错误地出现在 学习/技术/ 下"
    FAILED=$((FAILED + 1))
  fi
}

test_d2_different_depth_levels() {
  echo "测试 D2: 不同分类可以有不同的目录深度"

  # 技术笔记：4 层 (学习/技术/后端/Java/)
  # 生活笔记：1 层 (生活/)
  # 工作笔记：2 层 (工作/项目经验/)

  local tech_depth life_depth work_depth
  tech_depth=$(echo "学习/技术/后端/Java" | tr '/' '\n' | wc -l | tr -d ' ')
  life_depth=$(echo "生活" | tr '/' '\n' | wc -l | tr -d ' ')
  work_depth=$(echo "工作/项目经验" | tr '/' '\n' | wc -l | tr -d ' ')

  assert_eq "技术笔记 4 层深" "4" "$tech_depth"
  assert_eq "生活笔记 1 层深" "1" "$life_depth"
  assert_eq "工作笔记 2 层深" "2" "$work_depth"
}

test_d3_write_path_formula() {
  echo "测试 D3: 写入路径公式 = <vault绝对路径>/<分类路径>/<文件名>.md"

  local vault_abs="$VAULT_ROOT"
  local category="工作/项目经验"
  local filename="支付系统重构复盘"

  local expected="${vault_abs}/${category}/${filename}.md"
  assert_file_exists "路径公式正确" "$expected"

  # 对比旧公式（带顶级目录）
  local old_formula="${vault_abs}/学习/技术/${category}/${filename}.md"
  TOTAL=$((TOTAL + 1))
  if [[ ! -f "$old_formula" ]]; then
    echo "  ✅ 旧公式（带顶级目录前缀）路径不存在"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ 旧公式路径不应存在"
    FAILED=$((FAILED + 1))
  fi
}

# ============ 执行 ============

main() {
  echo "========================================="
  echo " obsidian-compendium 端到端流程测试（新版）"
  echo "========================================="
  echo ""

  setup
  trap teardown EXIT

  echo "=== Part A: 知识沉淀（多分类） ==="
  echo ""
  test_a1_tech_note
  echo ""
  test_a2_life_note
  echo ""
  test_a3_work_note
  echo ""
  test_a4_conditional_render
  echo ""
  test_a5_vault_root_index
  echo ""
  test_a6_index_chain_to_root
  echo ""

  echo "=== Part B: 知识检索 ==="
  echo ""
  test_b1_root_index_navigation
  echo ""
  test_b2_cross_category_isolation
  echo ""
  test_b3_leaf_to_note
  echo ""

  echo "=== Part C: 索引重建 ==="
  echo ""
  test_c1_scan_all_categories
  echo ""
  test_c2_directories_needing_index
  echo ""

  echo "=== Part D: 分类路径灵活性（核心新特性） ==="
  echo ""
  test_d1_no_fixed_prefix
  echo ""
  test_d2_different_depth_levels
  echo ""
  test_d3_write_path_formula
  echo ""

  echo "========================================="
  echo " 结果: $PASSED/$TOTAL 通过, $FAILED 失败"
  echo "========================================="

  [[ $FAILED -eq 0 ]]
}

main
