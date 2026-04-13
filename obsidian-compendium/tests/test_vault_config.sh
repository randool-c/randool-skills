#!/usr/bin/env bash
# vault_path.txt 配置格式兼容性测试（新版：2 行格式）
#
# 用法: bash tests/test_vault_config.sh
#
# 测试:
#   1. 新格式（2 行：名称 + 绝对路径）正确读取
#   2. 旧格式 A（3 行：名称 + 顶级目录 + 绝对路径）→ 忽略第 2 行
#   3. 旧格式 B（2 行：名称 + 顶级目录，无绝对路径）→ 需要 find 重写
#   4. 空文件 / 不存在处理
#   5. 中文路径
#   6. 实际 vault_path.txt 验证

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

# 模拟 skill 读取 vault_path.txt 的逻辑（新版）
# 返回:
#   "ok:<vault_name>|<abs_path>"         → 新格式，可直接使用
#   "compat_3line:<vault_name>|<abs_path>" → 旧 3 行格式，忽略第 2 行
#   "need_rewrite:<vault_name>"          → 最早格式，需要 find 后重写
#   "not_found"                          → 配置不存在或为空
read_vault_config() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    echo "not_found"
    return
  fi

  local vault_name line2 line3
  vault_name=$(sed -n '1p' "$config_file")
  line2=$(sed -n '2p' "$config_file")
  line3=$(sed -n '3p' "$config_file")

  if [[ -z "$vault_name" ]]; then
    echo "not_found"
    return
  fi

  # 有第 3 行 → 旧 3 行格式（名称 + 顶级目录 + 绝对路径）
  if [[ -n "$line3" ]]; then
    echo "compat_3line:${vault_name}|${line3}"
    return
  fi

  # 只有 2 行，判断第 2 行是否为绝对路径
  if [[ -n "$line2" ]]; then
    if [[ "$line2" == /* ]]; then
      # 新格式：名称 + 绝对路径
      echo "ok:${vault_name}|${line2}"
    else
      # 最早格式：名称 + 顶级目录（非绝对路径），需要 find 重写
      echo "need_rewrite:${vault_name}"
    fi
    return
  fi

  # 只有 1 行（只有 vault 名称）
  echo "need_rewrite:${vault_name}"
}

# ============ 测试用例 ============

test_1_new_format_2_lines() {
  echo "测试 1: 新格式（2 行：名称 + 绝对路径）→ 直接可用"
  local config="$TEST_ROOT/config_new.txt"
  cat > "$config" << 'EOF'
MyVault
/Users/someone/Documents/MyVault
EOF

  local result
  result=$(read_vault_config "$config")
  assert_eq "状态为 ok" "ok" "$(echo "$result" | cut -d: -f1)"
  assert_eq "vault 名称" "MyVault" "$(echo "$result" | cut -d: -f2 | cut -d'|' -f1)"
  assert_eq "绝对路径" "/Users/someone/Documents/MyVault" "$(echo "$result" | cut -d'|' -f2)"
}

test_2_old_format_3_lines() {
  echo "测试 2: 旧 3 行格式（名称 + 顶级目录 + 绝对路径）→ 忽略第 2 行"
  local config="$TEST_ROOT/config_old3.txt"
  cat > "$config" << 'EOF'
Compendium
学习/技术
/Users/test/Documents/Compendium
EOF

  local result
  result=$(read_vault_config "$config")
  assert_eq "状态为 compat_3line" "compat_3line" "$(echo "$result" | cut -d: -f1)"
  assert_eq "vault 名称" "Compendium" "$(echo "$result" | cut -d: -f2 | cut -d'|' -f1)"
  assert_eq "绝对路径取第 3 行" "/Users/test/Documents/Compendium" "$(echo "$result" | cut -d'|' -f2)"
}

test_3_oldest_format_2_lines_no_abspath() {
  echo "测试 3: 最早格式（名称 + 顶级目录，无绝对路径）→ 需要重写"
  local config="$TEST_ROOT/config_oldest.txt"
  cat > "$config" << 'EOF'
Compendium
学习/技术
EOF

  local result
  result=$(read_vault_config "$config")
  assert_eq "状态为 need_rewrite" "need_rewrite" "$(echo "$result" | cut -d: -f1)"
  assert_eq "vault 名称" "Compendium" "$(echo "$result" | cut -d: -f2)"
}

test_4_file_not_exists() {
  echo "测试 4: 配置文件不存在 → not_found"
  local result
  result=$(read_vault_config "$TEST_ROOT/nonexistent.txt")
  assert_eq "结果为 not_found" "not_found" "$result"
}

test_5_empty_file() {
  echo "测试 5: 空文件 → not_found"
  local config="$TEST_ROOT/config_empty.txt"
  touch "$config"

  local result
  result=$(read_vault_config "$config")
  assert_eq "结果为 not_found" "not_found" "$result"
}

test_6_chinese_paths() {
  echo "测试 6: 中文 vault 名称 + 中文绝对路径"
  local config="$TEST_ROOT/config_cn.txt"
  cat > "$config" << 'EOF'
我的知识库
/Users/test/Documents/我的知识库
EOF

  local result
  result=$(read_vault_config "$config")
  assert_eq "状态为 ok" "ok" "$(echo "$result" | cut -d: -f1)"
  assert_eq "中文名称" "我的知识库" "$(echo "$result" | cut -d: -f2 | cut -d'|' -f1)"
  assert_eq "中文路径" "/Users/test/Documents/我的知识库" "$(echo "$result" | cut -d'|' -f2)"
}

test_7_actual_vault_path() {
  echo "测试 7: 当前实际 vault_path.txt → 应为新格式"
  local skill_dir
  skill_dir="$(cd "$(dirname "$0")/.." && pwd)"
  local config="$skill_dir/vault_path.txt"

  if [[ ! -f "$config" ]]; then
    echo "  ⏭️ 跳过（vault_path.txt 不存在）"
    return
  fi

  local result
  result=$(read_vault_config "$config")
  local status
  status=$(echo "$result" | cut -d: -f1)

  assert_eq "实际配置为新格式 ok" "ok" "$status"

  # 验证绝对路径目录存在
  local abs_path
  abs_path=$(echo "$result" | cut -d'|' -f2)
  TOTAL=$((TOTAL + 1))
  if [[ -d "$abs_path" ]]; then
    echo "  ✅ 绝对路径目录存在: $abs_path"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ 绝对路径目录不存在: $abs_path"
    FAILED=$((FAILED + 1))
  fi
}

test_8_path_detection_boundary() {
  echo "测试 8: 边界 — 第 2 行以 / 开头视为绝对路径"

  # /开头 → 新格式
  local config_abs="$TEST_ROOT/config_abs.txt"
  printf 'TestVault\n/tmp/vault\n' > "$config_abs"
  local r1
  r1=$(read_vault_config "$config_abs")
  assert_eq "/tmp/vault 识别为新格式" "ok" "$(echo "$r1" | cut -d: -f1)"

  # 非/开头 → 旧格式需重写
  local config_rel="$TEST_ROOT/config_rel.txt"
  printf 'TestVault\nnotes/tech\n' > "$config_rel"
  local r2
  r2=$(read_vault_config "$config_rel")
  assert_eq "notes/tech 识别为旧格式" "need_rewrite" "$(echo "$r2" | cut -d: -f1)"
}

# ============ 执行 ============

main() {
  echo "========================================="
  echo " vault_path.txt 配置兼容性测试（新版）"
  echo "========================================="
  echo ""

  setup
  trap teardown EXIT

  test_1_new_format_2_lines
  echo ""
  test_2_old_format_3_lines
  echo ""
  test_3_oldest_format_2_lines_no_abspath
  echo ""
  test_4_file_not_exists
  echo ""
  test_5_empty_file
  echo ""
  test_6_chinese_paths
  echo ""
  test_7_actual_vault_path
  echo ""
  test_8_path_detection_boundary
  echo ""

  echo "========================================="
  echo " 结果: $PASSED/$TOTAL 通过, $FAILED 失败"
  echo "========================================="

  [[ $FAILED -eq 0 ]]
}

main
