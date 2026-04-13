# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

个人 Claude Code Skills 仓库，包含 Obsidian 知识管理相关的技能集。每个技能是一个独立目录，核心文件为 `SKILL.md`。

## 仓库结构

```
obsidian-compendium/   # Obsidian 知识沉淀与检索（知识沉淀、知识检索、索引重建）
obsidian-code-reader/  # Git 仓库深度解读并写入 Obsidian（仓库解读、仓库同步、索引重建）
```

两个技能共享：
- **渐进式索引**：目录级 `_index.md` 表格索引，支持层级导航
- **Git 自动同步**：vault 有 remote 时自动 commit + push，push 失败自动 rebase 重试
- **Vault 配置**：统一读取 `~/.agents/config/obsidian_vault.txt`（2行格式：vault名 + 绝对路径）

## Skill 开发规范

### 文件结构

```
skill-name/
├── SKILL.md              # 技能定义（必须），含 YAML frontmatter
├── references/           # 参考文档，供 SKILL.md 引用
├── tests/                # Shell 测试脚本
└── .gitignore
```

### SKILL.md frontmatter

```yaml
---
name: skill-name
description: 详细描述，包含触发关键词列表
compatibility:
  requires:
    - tool-name
  platforms:
    - macOS
---
```

`description` 字段需包含所有触发场景和关键词，Claude Code 依据此字段判断是否激活技能。

## 测试

```bash
# 运行 obsidian-compendium 测试
bash obsidian-compendium/tests/test_vault_config.sh
bash obsidian-compendium/tests/test_git_sync.sh
bash obsidian-compendium/tests/test_e2e_flow.sh

# 运行 obsidian-code-reader 测试
bash obsidian-code-reader/tests/test_vault_config.sh
bash obsidian-code-reader/tests/test_repo_meta.sh
bash obsidian-code-reader/tests/test_sync_flow.sh
bash obsidian-code-reader/tests/test_e2e_flow.sh
```

测试为独立 Shell 脚本，无外部测试框架依赖。

## 关键约定

- 笔记文件名：2-4个关键词用 `-` 连接，禁用 `.`（如 `React-useEffect-依赖陷阱`）
- 索引文件固定命名 `_index.md`，含 frontmatter 元数据 + 子目录表 + 笔记表
- `_repo_meta.md`（仅 code-reader）：记录上次分析的 commit、文件-笔记映射，用于增量同步
