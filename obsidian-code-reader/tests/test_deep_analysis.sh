#!/usr/bin/env bash
# 模块深剖功能测试
#
# 用法: bash obsidian-code-reader/tests/test_deep_analysis.sh
#
# 测试:
#   1. 从笔记名解析目标（笔记名 → 源码路径）
#   2. 从源码路径解析目标（源码路径 → 笔记名）
#   3. 未映射路径 → unmapped
#   4. 扁平笔记 → 目录迁移（文件移动、内容保留）
#   5. 目录已存在时的迁移（幂等性）
#   6. _repo_meta.md 映射展开（粗 → 细）
#   7. 展开后的映射查询
#   8. Wikilink 路径批量更新
#   9. 索引转换（笔记表 → 子目录表）
#  10. 独立运行（无已有解读时自动初始化）

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

assert_file_not_exists() {
  local desc="$1" filepath="$2"
  TOTAL=$((TOTAL + 1))
  if [[ ! -f "$filepath" ]]; then
    echo "  ✅ $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $desc (文件不应存在但存在: $filepath)"
    FAILED=$((FAILED + 1))
  fi
}

assert_dir_exists() {
  local desc="$1" dirpath="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -d "$dirpath" ]]; then
    echo "  ✅ $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $desc (目录不存在: $dirpath)"
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

# ============ 辅助函数 ============

# 从笔记名解析目标：在 _repo_meta.md 映射表中查找笔记名对应的源码路径
# 返回 "ok:<source_path>" 或 "not_found"
resolve_target_from_note() {
  local note_name="$1" meta_file="$2"

  if [[ ! -f "$meta_file" ]]; then
    echo "not_found"
    return
  fi

  # 在映射表中搜索包含该笔记名的行，提取源文件/目录列
  local match
  match=$(grep "\[\[.*${note_name}" "$meta_file" | head -1 || true)

  if [[ -z "$match" ]]; then
    echo "not_found"
    return
  fi

  # 提取源文件/目录（第一个 | 和第二个 | 之间的内容）
  local source_path
  source_path=$(echo "$match" | awk -F'|' '{print $2}' | sed 's/^ *//;s/ *$//')

  if [[ -n "$source_path" ]]; then
    echo "ok:${source_path}"
  else
    echo "not_found"
  fi
}

# 从源码路径解析目标：在 _repo_meta.md 映射表中查找源码路径对应的笔记名
# 返回笔记名或 "unmapped"
resolve_target_from_path() {
  local source_path="$1" meta_file="$2"

  if [[ ! -f "$meta_file" ]]; then
    echo "unmapped"
    return
  fi

  # 精确匹配源文件路径
  local match
  match=$(grep "| ${source_path} |" "$meta_file" 2>/dev/null | head -1 || true)

  if [[ -z "$match" ]]; then
    # 尝试目录级匹配（源路径以 / 结尾）
    match=$(grep "| ${source_path}" "$meta_file" 2>/dev/null | head -1 || true)
  fi

  if [[ -z "$match" ]]; then
    echo "unmapped"
    return
  fi

  echo "$match" | sed 's/.*\[\[\(.*\)\]\].*/\1/'
}

# 将扁平笔记迁移为目录结构
# migrate_flat_to_dir <模块目录> <原笔记文件名（不含.md）> <模块名>
migrate_flat_to_dir() {
  local module_dir="$1" note_filename="$2" module_name="$3"

  local source_file="${module_dir}/${note_filename}.md"
  local target_dir="${module_dir}/${module_name}"
  local target_file="${target_dir}/_index.md"

  # 创建目录
  mkdir -p "$target_dir"

  # 如果原笔记存在，迁移内容
  if [[ -f "$source_file" ]]; then
    cp "$source_file" "$target_file"
    rm "$source_file"
  fi
}

# 展开 _repo_meta.md 中的粗粒度映射为精细映射
# expand_mapping <meta_file> <原笔记路径（如 模块/认证模块-权限校验）> <新目录路径（如 模块/认证模块）> <文件列表（换行分隔：file|note_name）>
expand_mapping() {
  local meta_file="$1" old_note="$2" new_dir="$3" file_mappings="$4"

  # 1. 删除所有指向原笔记的映射行
  local escaped_old
  escaped_old=$(printf '%s' "$old_note" | sed 's/[/&]/\\&/g')
  sed -i '' "/\[\[${escaped_old}\]\]/d" "$meta_file"

  # 2. 找到映射表表头分隔线的位置，在其后插入新行
  # 新增总览行
  local overview_row="| ${new_dir}/ | [[${new_dir}/_index]] | 深剖总览 |"
  sed -i '' "/^|------------|---------|---------|$/a\\
${overview_row}
" "$meta_file"

  # 3. 新增每个文件的精细映射行
  while IFS='|' read -r file note_name; do
    [[ -z "$file" ]] && continue
    local row="| ${file} | [[${new_dir}/${note_name}]] | 文件级 |"
    sed -i '' "/^|------------|---------|---------|$/a\\
${row}
" "$meta_file"
  done <<< "$file_mappings"
}

# 批量更新 Wikilink 路径
# update_wikilinks <目录> <旧链接> <新链接> <显示文本>
update_wikilinks() {
  local search_dir="$1" old_link="$2" new_link="$3" display_text="$4"

  # 替换 [[旧路径]] → [[新路径|显示文本]]
  local escaped_old
  escaped_old=$(printf '%s' "$old_link" | sed 's/[/&]/\\&/g')
  local escaped_new
  escaped_new=$(printf '%s' "$new_link" | sed 's/[/&]/\\&/g')
  local escaped_display
  escaped_display=$(printf '%s' "$display_text" | sed 's/[/&]/\\&/g')

  find "$search_dir" -name "*.md" -type f -exec \
    sed -i '' "s/\[\[${escaped_old}\]\]/\[\[${escaped_new}|${escaped_display}\]\]/g" {} +

  # 替换带显示文本的形式 [[旧路径|文本]] → [[新路径|文本]]
  find "$search_dir" -name "*.md" -type f -exec \
    sed -i '' "s/\[\[${escaped_old}|\([^]]*\)\]\]/\[\[${escaped_new}|\1\]\]/g" {} +
}

# 转换索引条目：将笔记表中的条目移至子目录表
# transform_index_entry <index_file> <笔记名> <子目录名> <笔记数> <关键主题>
transform_index_entry() {
  local index_file="$1" note_name="$2" subdir_name="$3" note_count="$4" topics="$5"

  # 从本目录笔记表中删除该笔记
  local escaped_note
  escaped_note=$(printf '%s' "$note_name" | sed 's/[/&]/\\&/g')
  sed -i '' "/${escaped_note}/d" "$index_file"

  # 检查是否已有子目录表，没有则创建
  if ! grep -q "## 子目录" "$index_file"; then
    # 在 "## 本目录笔记" 之前插入子目录表
    sed -i '' "/## 本目录笔记/i\\
## 子目录\\
\\
| 子目录 | 笔记数 | 关键主题 |\\
|--------|--------|---------|\\
\\
" "$index_file"
  fi

  # 在子目录表表头分隔线后插入新行
  local subdir_row="| ${subdir_name}/ | ${note_count} | ${topics} |"
  sed -i '' "/^|--------|--------|---------|$/a\\
${subdir_row}
" "$index_file"
}

# 初始化仓库解读目录（独立运行时）
# init_repo_dir <vault_root> <repo_name> <repo_path>
init_repo_dir() {
  local vault_root="$1" repo_name="$2" repo_path="$3"
  local repo_dir="${vault_root}/代码解读/${repo_name}"

  mkdir -p "${repo_dir}/模块"

  # 生成初始 _repo_meta.md
  local now
  now=$(date "+%Y-%m-%d %H:%M")
  local branch="main"
  local commit="unknown"

  if [[ -d "${repo_path}/.git" ]]; then
    branch=$(cd "$repo_path" && git branch --show-current 2>/dev/null || echo "main")
    commit=$(cd "$repo_path" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  fi

  cat > "${repo_dir}/_repo_meta.md" << EOF
---
仓库名称: ${repo_name}
仓库路径: ${repo_path}
远程地址: none
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

  # 生成轻量项目概览
  cat > "${repo_dir}/项目概览.md" << EOF
---
创建时间: ${now}
更新时间: ${now}
标签: [${repo_name}]
来源仓库: ${repo_name}
源码路径: /
---

# ${repo_name} - 项目概览

## 定位与职责

> 待补充。

## 技术栈

- 待分析

## 目录结构

待扫描。
EOF

  echo "ok:${repo_dir}"
}

# ============ 测试用例 ============

test_1_resolve_from_note() {
  echo "测试 1: 从笔记名解析目标 → 源码路径"

  local meta_file="$TEST_ROOT/meta.md"
  cat > "$meta_file" << 'EOF'
| 源文件/目录 | 对应笔记 | 解读范围 |
|------------|---------|---------|
| src/auth/ | [[模块/认证模块-权限校验]] | 整个目录 |
| src/store/ | [[模块/状态管理-Pinia]] | 整个目录 |
| src/utils/format.ts | [[模块/工具函数-格式化]] | 文件级 |
EOF

  local result
  result=$(resolve_target_from_note "认证模块-权限校验" "$meta_file")
  assert_eq "找到认证模块的源码路径" "ok:src/auth/" "$result"

  result=$(resolve_target_from_note "状态管理-Pinia" "$meta_file")
  assert_eq "找到状态管理的源码路径" "ok:src/store/" "$result"

  result=$(resolve_target_from_note "不存在的笔记" "$meta_file")
  assert_eq "不存在的笔记返回 not_found" "not_found" "$result"
}

test_2_resolve_from_path() {
  echo "测试 2: 从源码路径解析目标 → 笔记名"

  local meta_file="$TEST_ROOT/meta2.md"
  cat > "$meta_file" << 'EOF'
| 源文件/目录 | 对应笔记 | 解读范围 |
|------------|---------|---------|
| src/auth/ | [[模块/认证模块-权限校验]] | 整个目录 |
| src/utils/format.ts | [[模块/工具函数-格式化]] | 文件级 |
EOF

  local note
  note=$(resolve_target_from_path "src/auth/" "$meta_file")
  assert_eq "路径 → 笔记名" "模块/认证模块-权限校验" "$note"

  note=$(resolve_target_from_path "src/utils/format.ts" "$meta_file")
  assert_eq "文件级路径 → 笔记名" "模块/工具函数-格式化" "$note"
}

test_3_unmapped_path() {
  echo "测试 3: 未映射路径 → unmapped"

  local meta_file="$TEST_ROOT/meta3.md"
  cat > "$meta_file" << 'EOF'
| 源文件/目录 | 对应笔记 | 解读范围 |
|------------|---------|---------|
| src/auth/ | [[模块/认证模块-权限校验]] | 整个目录 |
EOF

  local note
  note=$(resolve_target_from_path "src/new/feature.ts" "$meta_file")
  assert_eq "未映射文件" "unmapped" "$note"

  note=$(resolve_target_from_path "src/store/" "$meta_file")
  assert_eq "未映射目录" "unmapped" "$note"

  # meta 文件不存在
  note=$(resolve_target_from_path "src/auth/" "$TEST_ROOT/nonexistent.md")
  assert_eq "meta 文件不存在" "unmapped" "$note"
}

test_4_migrate_flat_to_dir() {
  echo "测试 4: 扁平笔记 → 目录迁移"

  local module_dir="$TEST_ROOT/vault/代码解读/repo/模块"
  mkdir -p "$module_dir"

  # 创建原扁平笔记
  cat > "$module_dir/认证模块-权限校验.md" << 'EOF'
---
创建时间: 2026-04-13 10:00
更新时间: 2026-04-13 10:00
标签: [repo, Python, 认证]
来源仓库: repo
源码路径: src/auth/
---

# 认证模块

## 定位与职责

> 负责用户认证和权限管理。

## 核心实现

### JWT 验证

```python
# src/auth/jwt.py:15-32
def verify_token(token):
    pass
```

## 依赖关系

- 上游：被 API 路由调用
- 下游：依赖数据库模块
EOF

  # 执行迁移
  migrate_flat_to_dir "$module_dir" "认证模块-权限校验" "认证模块"

  # 验证
  assert_dir_exists "模块目录已创建" "$module_dir/认证模块"
  assert_file_exists "总览 _index.md 已生成" "$module_dir/认证模块/_index.md"
  assert_file_not_exists "原扁平笔记已删除" "$module_dir/认证模块-权限校验.md"

  # 验证内容保留
  local content
  content=$(cat "$module_dir/认证模块/_index.md")
  assert_contains "frontmatter 保留" "$content" "创建时间: 2026-04-13 10:00"
  assert_contains "标签保留" "$content" "标签: [repo, Python, 认证]"
  assert_contains "来源仓库保留" "$content" "来源仓库: repo"
  assert_contains "正文内容保留" "$content" "负责用户认证和权限管理"
  assert_contains "代码片段保留" "$content" "verify_token"
}

test_5_migrate_dir_already_exists() {
  echo "测试 5: 目录已存在时的迁移（幂等性）"

  local module_dir="$TEST_ROOT/vault2/代码解读/repo/模块"
  mkdir -p "$module_dir/认证模块"

  # 目录下已有一个子模块笔记
  cat > "$module_dir/认证模块/已有笔记.md" << 'EOF'
# 已有的子模块笔记
不应被覆盖。
EOF

  # 创建原扁平笔记
  cat > "$module_dir/认证模块-权限校验.md" << 'EOF'
---
创建时间: 2026-04-13 10:00
来源仓库: repo
---

# 认证模块总览
EOF

  # 执行迁移
  migrate_flat_to_dir "$module_dir" "认证模块-权限校验" "认证模块"

  # 验证：不丢失已有笔记
  assert_file_exists "已有笔记未被删除" "$module_dir/认证模块/已有笔记.md"
  assert_file_exists "总览已生成" "$module_dir/认证模块/_index.md"
  assert_file_not_exists "原笔记已删除" "$module_dir/认证模块-权限校验.md"

  local existing_content
  existing_content=$(cat "$module_dir/认证模块/已有笔记.md")
  assert_contains "已有笔记内容完整" "$existing_content" "不应被覆盖"
}

test_6_expand_mapping() {
  echo "测试 6: _repo_meta.md 映射展开（粗 → 细）"

  local meta_file="$TEST_ROOT/meta_expand.md"
  cat > "$meta_file" << 'EOF'
---
仓库名称: repo
---

# 仓库元数据

## 文件-笔记映射

| 源文件/目录 | 对应笔记 | 解读范围 |
|------------|---------|---------|
| src/auth/ | [[模块/认证模块-权限校验]] | 整个目录 |
| src/auth/jwt.py | [[模块/认证模块-权限校验]] | 文件级 |
| src/store/ | [[模块/状态管理-Pinia]] | 整个目录 |

## 解读覆盖统计
EOF

  # 展开映射
  local file_mappings="src/auth/jwt.py|JWT鉴权
src/auth/password.py|密码处理
src/auth/rbac.py|权限控制"

  expand_mapping "$meta_file" "模块/认证模块-权限校验" "模块/认证模块" "$file_mappings"

  local content
  content=$(cat "$meta_file")

  # 验证旧映射已删除
  assert_not_contains "旧映射行已删除" "$content" "[[模块/认证模块-权限校验]]"

  # 验证新映射已添加
  assert_contains "深剖总览行存在" "$content" "深剖总览"
  assert_contains "总览指向 _index" "$content" "[[模块/认证模块/_index]]"
  assert_contains "JWT 精细映射" "$content" "[[模块/认证模块/JWT鉴权]]"
  assert_contains "密码处理精细映射" "$content" "[[模块/认证模块/密码处理]]"
  assert_contains "权限控制精细映射" "$content" "[[模块/认证模块/权限控制]]"

  # 验证不影响其他映射
  assert_contains "状态管理映射不变" "$content" "[[模块/状态管理-Pinia]]"

  # 验证映射行数（状态管理 1 + 总览 1 + 精细 3 = 5）
  local mapping_count
  mapping_count=$(grep -c '\[\[' "$meta_file" 2>/dev/null || echo "0")
  assert_eq "映射总行数" "5" "$mapping_count"
}

test_7_lookup_after_expand() {
  echo "测试 7: 展开后的映射查询"

  # 复用测试 6 生成的文件
  local meta_file="$TEST_ROOT/meta_expand.md"
  if [[ ! -f "$meta_file" ]]; then
    echo "  ⏭️ 跳过（依赖测试 6 生成的文件）"
    return
  fi

  local note
  note=$(resolve_target_from_path "src/auth/jwt.py" "$meta_file")
  assert_eq "jwt.py → JWT鉴权" "模块/认证模块/JWT鉴权" "$note"

  note=$(resolve_target_from_path "src/auth/password.py" "$meta_file")
  assert_eq "password.py → 密码处理" "模块/认证模块/密码处理" "$note"

  note=$(resolve_target_from_path "src/auth/rbac.py" "$meta_file")
  assert_eq "rbac.py → 权限控制" "模块/认证模块/权限控制" "$note"

  # 总览查询
  note=$(resolve_target_from_path "模块/认证模块/" "$meta_file")
  assert_eq "模块目录 → 总览" "模块/认证模块/_index" "$note"

  # 不受影响的映射
  note=$(resolve_target_from_path "src/store/" "$meta_file")
  assert_eq "store 映射不变" "模块/状态管理-Pinia" "$note"
}

test_8_update_wikilinks() {
  echo "测试 8: Wikilink 路径批量更新"

  local vault_dir="$TEST_ROOT/vault_wikilink/代码解读/repo"
  mkdir -p "$vault_dir/核心流程" "$vault_dir/模块"

  # 创建引用旧路径的笔记
  cat > "$vault_dir/架构设计.md" << 'EOF'
# 架构设计

认证由 [[模块/认证模块-权限校验]] 处理。
详见 [[模块/认证模块-权限校验|认证模块]] 的实现。
状态管理用 [[模块/状态管理-Pinia]]。
EOF

  cat > "$vault_dir/核心流程/用户登录.md" << 'EOF'
# 用户登录流程

1. 请求到达 → [[模块/认证模块-权限校验]]
2. 验证 token → [[模块/认证模块-权限校验]]
EOF

  # 执行 Wikilink 更新
  update_wikilinks "$vault_dir" "模块/认证模块-权限校验" "模块/认证模块/_index" "认证模块"

  # 验证架构设计笔记
  local arch_content
  arch_content=$(cat "$vault_dir/架构设计.md")
  assert_not_contains "旧链接已清除（架构设计）" "$arch_content" "[[模块/认证模块-权限校验]]"
  assert_contains "新链接已替换" "$arch_content" "[[模块/认证模块/_index|认证模块]]"
  # 带显示文本的链接保留原显示文本
  assert_contains "显示文本保留" "$arch_content" "[[模块/认证模块/_index|认证模块]]"

  # 验证不影响其他链接
  assert_contains "Pinia 链接不变" "$arch_content" "[[模块/状态管理-Pinia]]"

  # 验证流程笔记
  local flow_content
  flow_content=$(cat "$vault_dir/核心流程/用户登录.md")
  assert_not_contains "旧链接已清除（流程）" "$flow_content" "[[模块/认证模块-权限校验]]"
  assert_contains "流程中的新链接" "$flow_content" "[[模块/认证模块/_index|认证模块]]"
}

test_9_index_transform() {
  echo "测试 9: 索引转换（笔记表 → 子目录表）"

  local index_file="$TEST_ROOT/module_index.md"
  cat > "$index_file" << 'EOF'
---
更新时间: 2026-04-13 15:30
笔记总数: 3
---

# 模块 索引

> 共 3 篇笔记（含子目录），最后更新: 2026-04-13

## 本目录笔记

| 笔记 | 一句话摘要 | 标签 | 创建时间 |
|------|-----------|------|---------|
| 认证模块-权限校验 | JWT 认证与 RBAC 权限 | 认证, JWT | 2026-04-13 |
| 用户管理-CRUD | 用户增删改查 | 用户, CRUD | 2026-04-13 |
| 数据处理-ETL | ETL 数据管道 | ETL, 数据 | 2026-04-13 |
EOF

  # 执行转换：认证模块从笔记表移至子目录表
  transform_index_entry "$index_file" "认证模块-权限校验" "认证模块" "3" "JWT, 密码, 权限"

  local content
  content=$(cat "$index_file")

  # 验证子目录表已创建并包含新条目
  assert_contains "子目录表存在" "$content" "## 子目录"
  assert_contains "子目录条目" "$content" "认证模块/"
  assert_contains "子目录笔记数" "$content" "| 3 |"
  assert_contains "子目录主题" "$content" "JWT, 密码, 权限"

  # 验证原笔记条目已从笔记表删除
  assert_not_contains "原笔记条目已删除" "$content" "认证模块-权限校验"

  # 验证不影响其他笔记
  assert_contains "用户管理不变" "$content" "用户管理-CRUD"
  assert_contains "数据处理不变" "$content" "数据处理-ETL"
}

test_10_independent_run() {
  echo "测试 10: 独立运行（无已有解读时自动初始化）"

  # 创建 mock git 仓库
  local repo_path="$TEST_ROOT/mock_repo"
  mkdir -p "$repo_path"
  cd "$repo_path"
  git init -q
  mkdir -p src/auth
  echo 'def login(): pass' > src/auth/login.py
  git add . && git commit -q -m "init"

  # 空 vault
  local vault_root="$TEST_ROOT/empty_vault"
  mkdir -p "$vault_root"

  # 执行初始化
  local result
  result=$(init_repo_dir "$vault_root" "mock_repo" "$repo_path")

  local status
  status=$(echo "$result" | cut -d: -f1)
  assert_eq "初始化成功" "ok" "$status"

  local repo_dir="${vault_root}/代码解读/mock_repo"

  # 验证目录结构
  assert_dir_exists "仓库目录已创建" "$repo_dir"
  assert_dir_exists "模块目录已创建" "$repo_dir/模块"

  # 验证 _repo_meta.md
  assert_file_exists "_repo_meta.md 已生成" "$repo_dir/_repo_meta.md"
  local meta_content
  meta_content=$(cat "$repo_dir/_repo_meta.md")
  assert_contains "仓库名称正确" "$meta_content" "仓库名称: mock_repo"
  assert_contains "仓库路径正确" "$meta_content" "仓库路径: $repo_path"
  assert_contains "包含映射表" "$meta_content" "文件-笔记映射"

  # 验证 commit 信息（来自真实 git 仓库）
  assert_not_contains "commit 不是 unknown" "$meta_content" "上次解读commit: unknown"

  # 验证项目概览
  assert_file_exists "项目概览已生成" "$repo_dir/项目概览.md"
  local overview_content
  overview_content=$(cat "$repo_dir/项目概览.md")
  assert_contains "概览包含仓库名" "$overview_content" "mock_repo"
  assert_contains "概览包含来源仓库" "$overview_content" "来源仓库: mock_repo"
}

# ============ 执行 ============

main() {
  echo "========================================="
  echo " 模块深剖功能测试"
  echo "========================================="
  echo ""

  setup
  trap teardown EXIT

  test_1_resolve_from_note
  echo ""
  test_2_resolve_from_path
  echo ""
  test_3_unmapped_path
  echo ""
  test_4_migrate_flat_to_dir
  echo ""
  test_5_migrate_dir_already_exists
  echo ""
  test_6_expand_mapping
  echo ""
  test_7_lookup_after_expand
  echo ""
  test_8_update_wikilinks
  echo ""
  test_9_index_transform
  echo ""
  test_10_independent_run
  echo ""

  echo "========================================="
  echo " 结果: $PASSED/$TOTAL 通过, $FAILED 失败"
  echo "========================================="

  [[ $FAILED -eq 0 ]]
}

main
