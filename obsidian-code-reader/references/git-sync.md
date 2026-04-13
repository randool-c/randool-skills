# Git 自动同步

笔记或索引变更后，自动检测 vault 是否关联了远程 Git 仓库，如果是则自动提交并推送。

## 检测条件

在 vault 根目录依次检查以下三个条件，**全部满足才执行同步**：

1. **是 git 仓库** — `git rev-parse --is-inside-work-tree` 返回 true
2. **存在 remote** — `git remote` 输出非空
3. **当前分支有上游跟踪分支** — `git rev-parse --abbrev-ref @{upstream}` 执行成功

任一条件不满足则**静默跳过**，不报错、不打断流程。

## 执行流程

1. **暂存变更** — `git add .`。执行前确认 `.gitignore` 已排除 `.obsidian/`，没有则追加。
2. **总结 commit message** — 执行 `git diff --cached --stat` 和 `git diff --cached` 查看变更，总结简洁的 commit message。遵循 `<type>: <description>` 格式。
3. **提交** — `git commit -m "<message>"`
4. **推送** — `git push`
5. **告知用户** — 一行简要结果

## 无变更处理

`git diff --cached` 为空时，静默跳过。

## Push 失败自主恢复

- 阅读错误输出，理解失败原因
- 根据错误类型采取对应措施（远端领先就先 pull，有冲突就解决，网络问题就重试）
- 解决后重新 push
- 仍无法解决则告知用户具体原因，笔记已保存到本地不会丢失
