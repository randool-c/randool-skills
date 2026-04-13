#!/usr/bin/env bash
# Vault 配置读取测试（与 obsidian-compendium 共享配置规范）
#
# 用法: bash obsidian-code-reader/tests/test_vault_config.sh
#
# 测试:
#   1. 标准格式正确读取
#   2. 文件不存在处理
#   3. 空文件处理
#   4. 只有名称没有路径
#   5. 中文路径支持
#   6. 实际配置文件验证

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

# 读取 vault 配置
# 返回: "ok:<vault_name>|<abs_path>" 或 "not_found"
read_vault_config() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    echo "not_found"
    return
  fi

  local vault_name abs_path
  vault_name=$(sed -n '1p' "$config_file")
  abs_path=$(sed -n '2p' "$config_file")

  if [[ -z "$vault_name" || -z "$abs_path" ]]; then
    echo "not_found"
    return
  fi

  echo "ok:${vault_name}|${abs_path}"
}

# ============ 测试用例 ============

test_1_standard_format() {
  echo "测试 1: 标准格式（2 行：名称 + 绝对路径）→ 直接可用"
  local config="$TEST_ROOT/obsidian_vault.txt"
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

test_2_file_not_exists() {
  echo "测试 2: 配置文件不存在 → not_found"
  local result
  result=$(read_vault_config "$TEST_ROOT/nonexistent.txt")
  assert_eq "结果为 not_found" "not_found" "$result"
}

test_3_empty_file() {
  echo "测试 3: 空文件 → not_found"
  local config="$TEST_ROOT/obsidian_vault_empty.txt"
  touch "$config"

  local result
  result=$(read_vault_config "$config")
  assert_eq "结果为 not_found" "not_found" "$result"
}

test_4_only_name_no_path() {
  echo "测试 4: 只有名称没有路径 → not_found"
  local config="$TEST_ROOT/obsidian_vault_partial.txt"
  printf 'MyVault\n' > "$config"

  local result
  result=$(read_vault_config "$config")
  assert_eq "结果为 not_found" "not_found" "$result"
}

test_5_chinese_paths() {
  echo "测试 5: 中文 vault 名称 + 中文路径"
  local config="$TEST_ROOT/obsidian_vault_cn.txt"
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

test_6_actual_config() {
  echo "测试 6: 实际配置文件 ~/.agents/config/obsidian_vault.txt"
  local config="$HOME/.agents/config/obsidian_vault.txt"

  if [[ ! -f "$config" ]]; then
    echo "  ⏭️ 跳过（配置文件不存在）"
    return
  fi

  local result
  result=$(read_vault_config "$config")
  local status
  status=$(echo "$result" | cut -d: -f1)

  assert_eq "配置格式正确" "ok" "$status"

  local abs_path
  abs_path=$(echo "$result" | cut -d'|' -f2)
  TOTAL=$((TOTAL + 1))
  if [[ -d "$abs_path" ]]; then
    echo "  ✅ vault 目录存在: $abs_path"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ vault 目录不存在: $abs_path"
    FAILED=$((FAILED + 1))
  fi
}

# ============ 执行 ============

main() {
  echo "========================================="
  echo " Vault 配置读取测试 (obsidian-code-reader)"
  echo "========================================="
  echo ""

  setup
  trap teardown EXIT

  test_1_standard_format
  echo ""
  test_2_file_not_exists
  echo ""
  test_3_empty_file
  echo ""
  test_4_only_name_no_path
  echo ""
  test_5_chinese_paths
  echo ""
  test_6_actual_config
  echo ""

  echo "========================================="
  echo " 结果: $PASSED/$TOTAL 通过, $FAILED 失败"
  echo "========================================="

  [[ $FAILED -eq 0 ]]
}

main
