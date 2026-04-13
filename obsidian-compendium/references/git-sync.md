# Git 自动同步

笔记或索引变更后，自动检测 vault 是否关联了远程 Git 仓库，如果是则自动提交并推送。这样用户无需手动管理版本，笔记修改即时同步到 GitHub。

## 检测条件

在 vault 根目录依次检查以下三个条件，**全部满足才执行同步**：

1. **是 git 仓库** — `git rev-parse --is-inside-work-tree` 返回 true
2. **存在 remote** — `git remote` 输出非空
3. **当前分支有上游跟踪分支** — `git rev-parse --abbrev-ref @{upstream}` 执行成功

任一条件不满足则**静默跳过**，不报错、不打断流程。检测失败不影响笔记的正常写入。

## 执行流程

检测通过后，在 vault 根目录执行：

1. **暂存变更** — `git add .`（使用 `.` 而非 `-A`，限定 vault 根目录，避免意外暂存非笔记文件）。执行前确认 vault 的 `.gitignore` 已排除 `.obsidian/` 目录，如果没有则先追加 `.obsidian/` 到 `.gitignore`。
2. **总结 commit message** — 执行 `git diff --cached --stat` 和 `git diff --cached` 查看暂存区的实际变更内容，从中总结出一条简洁的 commit message。message 应反映本次变更的实质（新增了什么笔记、更新了哪些索引、修改了什么内容），而不是套用固定模板。遵循 `<type>: <description>` 格式（如 `docs:`, `chore:` 等）。
3. **提交** — `git commit -m "<总结出的 message>"`
4. **推送** — `git push`
5. **告知用户** — 一行简要结果，如 `已同步到 GitHub`

## 无变更处理

`git diff --cached` 为空（暂存区无实际变更）时，静默跳过 commit 和 push，不提示。

## Push 失败自主恢复

push 不一定总能成功——可能远端有新提交、可能网络抖动、可能权限变更。发生 push 失败时，不要只报错就放弃，而是**像一个熟练的开发者一样自主排查和解决问题**：

- 阅读 `git push` 的错误输出，理解失败原因
- 根据错误类型采取对应措施（比如远端领先就先 pull，有冲突就解决冲突，网络问题就重试）
- 解决后重新 push
- 如果尝试后仍然无法解决（如权限不足、remote 不存在），告知用户具体原因和建议，笔记已保存到本地不会丢失
