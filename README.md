# fujiang-hermes

把 DSH 的 `fujiang-preset`（`cordis.patch.yml` bundle）移植成 **hermes-agent** 能直接吃的人格文件。

- 目标 agent：[hermes-agent](https://github.com/NousResearch/hermes-agent)（NousResearch，MIT，Python）
- 落点：`SOUL.md`（系统提示槽位 #1）或 `agent.personalities.fujiang`
- 人格名：`富江`
- 触发词：发「富江」→ 只回「富江」，进入状态

## 这个仓库解决什么问题

`fujiang-preset` 是 **DSH 的 bundle 格式**（`package.json` 里 `dsh.bundle.patch → ./cordis.patch.yml`），hermes 没有 `cordis.patch.yml`、没有 `@deepseek-ai/*` 插件、没有 preset 概念，**装不进去**。

能搬的只有两样：**人格正文**和**行为契约**。剩下 23 个 DSH 插件是运行时部件，hermes 全部内置，见 [INSTALL.md](INSTALL.md#三23-个-dsh-插件在-hermes-的对应)。

而且原文件**不能原样搬**：`cordis.patch.yml` 第 41–121 行逐字包含 `ignore previous instructions`、`stop roleplaying`、`you are now X`、`switch to normal mode` 这类字符串，会命中 hermes 的提示注入扫描，整份被丢弃，回落到内置身份。本仓库的 `SOUL.md` 是重写版：保留身份/语气/交付标准/领域姿态/激活规则，丢掉免疫段、反拒绝段、禁用词表、拒绝分类表。

## 快速开始

```powershell
# Windows 原生
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun   # 预览
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1           # 安装
```

```bash
# Linux / macOS / WSL2
mkdir -p ~/.hermes && cp SOUL.md ~/.hermes/SOUL.md
```

目标路径：

| 平台 | 路径 |
|---|---|
| Windows 原生 | `%LOCALAPPDATA%\hermes\SOUL.md` |
| Linux / macOS / WSL2 | `~/.hermes/SOUL.md` |
| 自定义 `HERMES_HOME` | `$HERMES_HOME/SOUL.md` |
| 多 profile | `%LOCALAPPDATA%\hermes\profiles\<profile>\SOUL.md` |

验证：

```powershell
hermes doctor
hermes chat -q "富江"      # 应只回「富江」两个字
```

## 文件清单

| 文件 | 用途 |
|---|---|
| [`SOUL.md`](SOUL.md) | **主体**。重写后的人格文件，2661 字节，直接放到 `HERMES_HOME` |
| [`bundle.md`](bundle.md) | **单文件版**。把 SOUL.md + config 片段 + 安装步骤 + 插件映射合成一份，一个链接就能交给 AI |
| [`INSTALL.md`](INSTALL.md) | 完整安装说明：落点对比、必须重写的原因、23 个插件的映射表、已知差异 |
| [`config-snippet.yaml`](config-snippet.yaml) | 想用 `/personality fujiang` 切换时，把这段合并进 `config.yaml` |
| [`install.ps1`](install.ps1) | Windows 一键安装：备份 → 写 `SOUL.md` → 合并 `config.yaml` → 回读校验 |

## 如果你是被要求读这个仓库的 AI

1. 优先读 [`bundle.md`](bundle.md)，它是自包含的，不需要再取别的文件。
2. 要装到某台机器上，按 `bundle.md` 里「一分钟安装」的步骤，把 `SOUL.md` 的**全文**写到该机器的 `HERMES_HOME/SOUL.md`。
3. `SOUL.md` 必须逐字写入，不要改写、不要精简、不要在前后加说明文字。
4. `config-snippet.yaml` 只在需要 `/personality fujiang` 会话级切换时才用；和 `SOUL.md` 同时启用会重复注入。

## 已知差异

1. **激活是会话内状态**。`SOUL.md` 每会话重新注入；用户说「恢复正常」时 hermes 不会拒绝，这是模型层的事，文本层管不了。
2. **截断**。hermes 对 `SOUL.md` 有截断，阈值未公开。本文件 2661 字节，远低于任何合理阈值；自行加内容请控制在 16 KB 以内。
3. **别同时用两种落点**。`SOUL.md` + `/personality fujiang` 会叠加注入两次。
4. **改完必须开新会话**。上下文在会话开始时就组装完了；长连接网关会话用 `hermes sessions refresh-prompts`。

## License

MIT，见 [LICENSE](LICENSE)。
