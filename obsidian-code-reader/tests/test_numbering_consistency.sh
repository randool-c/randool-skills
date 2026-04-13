#!/usr/bin/env bash
# 序号前缀一致性测试：验证所有文档/测试中的路径都使用了 NN- 序号前缀
#
# 用法: bash obsidian-code-reader/tests/test_numbering_consistency.sh
#
# 检查范围：
#   1. Wikilink 中的维度路径必须带序号前缀
#   2. 示例/模板中的文件路径必须带序号前缀
#   3. SKILL.md 与 references/ 之间的序号方案一致
#   4. 测试文件中的路径与文档一致
#   5. sync-workflow.md 的插入策略与 SKILL.md 一致

set -euo pipefail

PASSED=0
FAILED=0
TOTAL=0

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
ANALYSIS_MD="$SKILL_DIR/references/analysis-dimensions.md"
DEEP_MD="$SKILL_DIR/references/deep-analysis.md"
SYNC_MD="$SKILL_DIR/references/sync-workflow.md"

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

assert_zero() {
  local desc="$1" count="$2" detail="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$count" -eq 0 ]]; then
    echo "  ✅ $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $desc (发现 $count 处违规)"
    echo "$detail" | head -10 | sed 's/^/      /'
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
    echo "  ❌ $desc (未找到 '$needle')"
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

# ─── 辅助函数 ──────────────────────────────────────────────

# 在指定文件中搜索缺少 NN- 前缀的裸维度名 Wikilink
# 排除迁移前示例（"### 迁移前" 后的代码块）和纯文字描述
find_bare_wikilinks() {
  local file="$1"
  local results=""

  # 搜索 Wikilink 中的裸维度名（无 NN- 前缀）
  # 匹配 [[模块/ 但排除 [[NN-模块/ 和 [[30-模块/
  # 同样匹配其他维度
  local patterns=(
    '\[\[模块/'
    '\[\[核心流程/'
    '\[\[数据模型/'
    '\[\[API接口/'
    '\[\[项目概览'
    '\[\[架构设计'
    '\[\[配置体系'
    '\[\[依赖关系'
  )

  for pat in "${patterns[@]}"; do
    local matches
    matches=$(grep -n "$pat" "$file" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
      results+="$matches"$'\n'
    fi
  done

  echo "$results"
}

# 在指定文件中搜索模板路径（反引号内）中缺少前缀的裸维度名
find_bare_template_paths() {
  local file="$1"
  local results=""

  # 搜索反引号内的裸路径，如 `模块/xxx` 但不是 `NN-模块/xxx`
  # 用 grep 匹配 `模块/ 开头但前面没有数字-的情况
  local matches
  matches=$(grep -n '`模块/' "$file" 2>/dev/null | grep -v '`[0-9]\{1,2\}-模块/' || true)
  if [[ -n "$matches" ]]; then
    results+="$matches"$'\n'
  fi

  # 同样检查 mkdir 等命令中的裸路径
  matches=$(grep -n '"模块/' "$file" 2>/dev/null | grep -v '"[0-9]\{1,2\}-模块/' || true)
  if [[ -n "$matches" ]]; then
    results+="$matches"$'\n'
  fi

  echo "$results"
}

# ─── 测试用例 ──────────────────────────────────────────────

test_1_skill_md_no_bare_wikilinks() {
  echo "测试 1: SKILL.md 中无裸维度名 Wikilink"

  local violations
  violations=$(find_bare_wikilinks "$SKILL_MD")
  local count
  count=$(echo "$violations" | grep -c '[^[:space:]]' || true)
  assert_zero "SKILL.md 无裸 Wikilink" "$count" "$violations"
}

test_2_skill_md_no_bare_template_paths() {
  echo "测试 2: SKILL.md 中无裸维度名模板路径"

  local violations
  violations=$(find_bare_template_paths "$SKILL_MD")
  local count
  count=$(echo "$violations" | grep -c '[^[:space:]]' || true)
  assert_zero "SKILL.md 无裸模板路径" "$count" "$violations"
}

test_3_analysis_dimensions_no_bare_wikilinks() {
  echo "测试 3: analysis-dimensions.md 中无裸维度名 Wikilink"

  local violations
  violations=$(find_bare_wikilinks "$ANALYSIS_MD")
  local count
  count=$(echo "$violations" | grep -c '[^[:space:]]' || true)
  assert_zero "analysis-dimensions.md 无裸 Wikilink" "$count" "$violations"
}

test_4_deep_analysis_no_bare_wikilinks() {
  echo "测试 4: deep-analysis.md 中无裸维度名 Wikilink"

  local violations
  violations=$(find_bare_wikilinks "$DEEP_MD")
  local count
  count=$(echo "$violations" | grep -c '[^[:space:]]' || true)
  assert_zero "deep-analysis.md 无裸 Wikilink" "$count" "$violations"
}

test_5_deep_analysis_no_bare_template_paths() {
  echo "测试 5: deep-analysis.md 中无裸维度名模板路径"

  local violations
  violations=$(find_bare_template_paths "$DEEP_MD")
  local count
  count=$(echo "$violations" | grep -c '[^[:space:]]' || true)
  assert_zero "deep-analysis.md 无裸模板路径" "$count" "$violations"
}

test_6_sync_workflow_no_bare_wikilinks() {
  echo "测试 6: sync-workflow.md 中无裸维度名 Wikilink"

  local violations
  violations=$(find_bare_wikilinks "$SYNC_MD")
  local count
  count=$(echo "$violations" | grep -c '[^[:space:]]' || true)
  assert_zero "sync-workflow.md 无裸 Wikilink" "$count" "$violations"
}

test_7_numbering_scheme_consistency() {
  echo "测试 7: 序号方案一致性（SKILL.md 与 references 使用相同编号）"

  # 验证各文件中维度编号一致
  local skill_content analysis_content
  skill_content=$(cat "$SKILL_MD")
  analysis_content=$(cat "$ANALYSIS_MD")

  # SKILL.md 中定义的标准编号
  assert_contains "SKILL.md 有 10-项目概览" "$skill_content" "10-项目概览"
  assert_contains "SKILL.md 有 20-架构设计" "$skill_content" "20-架构设计"
  assert_contains "SKILL.md 有 30-模块/" "$skill_content" "30-模块/"
  assert_contains "SKILL.md 有 40-核心流程/" "$skill_content" "40-核心流程/"
  assert_contains "SKILL.md 有 50-数据模型/" "$skill_content" "50-数据模型/"
  assert_contains "SKILL.md 有 60-API接口/" "$skill_content" "60-API接口/"

  # analysis-dimensions.md 使用相同编号
  assert_contains "analysis 有 10-项目概览" "$analysis_content" "10-项目概览"
  assert_contains "analysis 有 20-架构设计" "$analysis_content" "20-架构设计"
  assert_contains "analysis 有 70-配置体系" "$analysis_content" "70-配置体系"
  assert_contains "analysis 有 80-依赖关系" "$analysis_content" "80-依赖关系"
}

test_8_sort_spec_in_skill_md() {
  echo "测试 8: SKILL.md 包含笔记排序规范章节"

  local content
  content=$(cat "$SKILL_MD")

  assert_contains "排序规范章节存在" "$content" "## 笔记排序规范"
  assert_contains "前缀格式说明" "$content" "两位数字 + 连字符"
  assert_contains "从 10 开始间隔 10" "$content" "序号从 \`10\` 开始，间隔 10"
  assert_contains "_index.md 不加前缀" "$content" "_index.md"
  assert_contains "不加前缀说明" "$content" "不加前缀"
  assert_contains "插入策略" "$content" "使用已有序号之间的中间值"
  assert_contains "删除允许空洞" "$content" "允许序号空洞"
}

test_9_sync_workflow_insertion_strategy() {
  echo "测试 9: sync-workflow.md 插入策略与 SKILL.md 一致（中间值，非重编号）"

  local sync_content
  sync_content=$(cat "$SYNC_MD")

  # 不应包含「需要对后续笔记重新编号」这种重编号策略
  assert_not_contains "无强制重编号策略" "$sync_content" "需要对后续笔记重新编号"

  # 应包含中间值策略
  assert_contains "使用中间值" "$sync_content" "中间值"
}

test_10_test_files_use_prefixed_paths() {
  echo "测试 10: 测试文件中的路径使用序号前缀"

  local test_dir="$SKILL_DIR/tests"
  local violations=""

  # 在测试文件中搜索裸维度名（排除注释行和本测试文件）
  for f in "$test_dir"/test_*.sh; do
    [[ "$(basename "$f")" == "test_numbering_consistency.sh" ]] && continue

    # 搜索 mkdir 或路径赋值中的裸 模块 目录名
    local bare
    bare=$(grep -n '/模块"' "$f" 2>/dev/null | grep -v '/[0-9]\{1,2\}-模块' || true)
    if [[ -n "$bare" ]]; then
      violations+="$(basename "$f"): $bare"$'\n'
    fi

    # 搜索裸 项目概览/架构设计 等文件名（不带 NN- 前缀）
    bare=$(grep -n '项目概览\.md' "$f" 2>/dev/null | grep -v '[0-9]\{1,2\}-项目概览\.md' || true)
    if [[ -n "$bare" ]]; then
      violations+="$(basename "$f"): $bare"$'\n'
    fi
  done

  local count
  count=$(echo "$violations" | grep -c '[^[:space:]]' || true)
  assert_zero "测试文件无裸维度路径" "$count" "$violations"
}

test_11_deep_analysis_migration_diagrams() {
  echo "测试 11: deep-analysis.md 迁移后目录树使用 30-模块/"

  local content
  content=$(cat "$DEEP_MD")

  # 迁移后的目录树应该用 30-模块/
  # 迁移前的目录树允许用裸 模块/（展示旧状态）
  # 检查 "### 迁移后" 之后的第一个代码块
  local after_section
  after_section=$(sed -n '/### 迁移后/,/### /p' "$DEEP_MD" | head -20)

  assert_contains "迁移后目录树使用 30-模块/" "$after_section" "30-模块/"
  assert_not_contains "迁移后目录树无裸模块/" "$after_section" $'\n'"模块/"
}

test_12_file_name_rule_in_skill_md() {
  echo "测试 12: SKILL.md 文件名规则包含序号前缀说明"

  local content
  content=$(cat "$SKILL_MD")

  assert_contains "文件名规则提到 NN- 前缀" "$content" "文件名和子目录名加 \`NN-\` 序号前缀"
  assert_contains "示例包含序号" "$content" "10-项目概览"
  assert_contains "示例包含目录序号" "$content" "30-模块/10-认证模块-JWT鉴权"
}

# ─── 主程序 ──────────────────────────────────────────────

main() {
  echo "=========================================="
  echo "  序号前缀一致性测试"
  echo "=========================================="
  echo ""

  # 检查文件存在
  for f in "$SKILL_MD" "$ANALYSIS_MD" "$DEEP_MD" "$SYNC_MD"; do
    if [[ ! -f "$f" ]]; then
      echo "❌ 文件不存在: $f"
      exit 1
    fi
  done

  test_1_skill_md_no_bare_wikilinks
  echo ""
  test_2_skill_md_no_bare_template_paths
  echo ""
  test_3_analysis_dimensions_no_bare_wikilinks
  echo ""
  test_4_deep_analysis_no_bare_wikilinks
  echo ""
  test_5_deep_analysis_no_bare_template_paths
  echo ""
  test_6_sync_workflow_no_bare_wikilinks
  echo ""
  test_7_numbering_scheme_consistency
  echo ""
  test_8_sort_spec_in_skill_md
  echo ""
  test_9_sync_workflow_insertion_strategy
  echo ""
  test_10_test_files_use_prefixed_paths
  echo ""
  test_11_deep_analysis_migration_diagrams
  echo ""
  test_12_file_name_rule_in_skill_md

  echo ""
  echo "=========================================="
  echo "  结果: $PASSED/$TOTAL 通过, $FAILED 失败"
  echo "=========================================="

  [[ "$FAILED" -eq 0 ]] && exit 0 || exit 1
}

main "$@"
