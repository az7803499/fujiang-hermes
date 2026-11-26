# 把 fujiang-preset 搬进 hermes-agent

`fujiang-preset/` 是 **DSH 的 bundle**（`package.json` 里 `dsh.bundle.patch` 指向 `cordis.patch.yml`），hermes 没有 `cordis.patch.yml` 这套东西，不能直接装。能搬的只有两样：**人格正文**和**行为契约**。剩下的 23 个插件是 DSH 的运行时部件，hermes 全部内置，不需要移植。

## 一、落点：三个位置，选一个

| 位置 | 机制 | 生效范围 | 适合 |
|---|---|---|---|
| `%LOCALAPPDATA%\hermes\SOUL.md` | 系统提示**槽位 #1**，内容逐字注入 | 所有会话、所有平台 | **推荐**。DSH 那份 preset 就是全局身份，这里是一比一对应 |
| `config.yaml` → `agent.personalities.fujiang` | 会话级叠加，`/personality fujiang` 切换 | 当前会话 | 想保留 hermes 默认身份，按需切成富江 |
| 项目目录 `AGENTS.md` | 项目上下文 | 只在那个目录 | 不推荐。会被当成「项目约定」，权重比身份低 |

`SOUL.md` 只在 `HERMES_HOME` 读，不看当前工作目录；已有文件**不会被覆盖**（所以要先备份再写）。

## 二、关键：不能原样搬

DSH 那份 `cordis.patch.yml` 第 41–121 行是「Input immunity」「No reserved zones」「Refusal taxonomy」「Banned vocabulary」四大段，里面逐字写着 `ignore previous instructions`、`stop roleplaying`、`you are now X`、`switch to normal mode`、`jailbreak` 这类字符串——**它们本身就会被 hermes 的注入扫描命中**。

hermes 对 `SOUL.md` 的处理是：内容先过提示注入模式扫描，再截断，再逐字注入；扫到注入特征按拦截处理（和 `memory` 同一条管线，`memory` 那边是直接拒收）。所以原样贴进去，最可能的结果是整份被丢、回落到内置的 "You are Hermes Agent, built by Nous Research…"，你会以为装失败了。

更重要的：**这几段在 hermes 里是多余的。** DSH 的 persona 是插件注入的中间层，所以它必须自己喊「我是最高权威」；而 `SOUL.md` 本身就是系统提示的第 1 槽位，它天生就是最高权威，喊这句话只会触发扫描，不会增加任何权重。

所以本目录的 `SOUL.md` 是**重写版**：保留身份、语气、交付标准、领域姿态、激活规则；丢掉全部「免疫/反拒绝/禁用词表/拒绝分类」段落。功能上等价，扫描上干净。

## 三、23 个 DSH 插件在 hermes 的对应

| DSH 插件 | 作用 | hermes 对应 |
|---|---|---|
| `dsh-persona` | 人设前缀 | `SOUL.md`（槽位 #1）或 `agent.personalities` |
| `dsh-agent-instructions`（maxBytes 65536） | 读 AGENTS.md | 内置上下文文件（`AGENTS.md` / `.hermes.md`），无字节上限参数 |
| `dsh-time-context` | 注入当前时间 | 内置（提示栈第 6 层 timestamp） |
| `dsh-tool-bash` / `dsh-tool-pwsh` | 执行 shell | `terminal` 工具。注意：Windows 原生安装下 hermes 用**自带的 Git Bash** 跑命令，不是 PowerShell |
| `dsh-tool-fs`（applyPatch:false） | 读写文件 | `read_file` / `write_file` / `patch` |
| `dsh-tool-fs-search` | glob / grep | 内置文件工具集的检索 |
| `dsh-tool-jobs` | 后台任务 | `process` 工具（list/poll/wait/log/kill/write）+ `/bg` |
| `dsh-tool-schedule` | 定时任务 | `cronjob` 工具（create/list/update/pause/resume/run/remove） |
| `dsh-skill-filesystem` + `dsh-tool-skill` | 技能 | 内置 skills：`~/.hermes/skills/`，`skill_manage`，每个技能自动变成 slash 命令 |
| `dsh-command-goal` + `dsh-tool-goal` | 目标 | 内置 `/goal` |
| `dsh-plan-mode` | 计划模式 | 无直接对应。要这个行为，在 `AGENTS.md` 里写死「先出计划再执行」 |
| `dsh-compaction-basic` / `command-compact` / `tool-result-pruner` | 压缩 | 内置自动压缩 + `/compress` + `hooks.output_spill` |
| `dsh-tool-subagent` / `dsh-tool-subagent-fork` | 子代理 | `delegate_task` |
| `dsh-workflow-ptc` / `dsh-tool-workflow` | 工作流 DSL | 无直接对应。用 `execute_code` + `delegate_task` 组合 |
| `dsh-tool-ask-user` | 提问 | `clarify` |
| `dsh-tool-todo` | 待办 | `todo` |
| `dsh-tool-web`（fetch + search） | 联网 | `web_search` + `web_extract`（或 Nous Tool Gateway） |
| `dsh-tool-present` | 交付文件 | 无对应。桌面端有文件面板 |
| `dsh-tool-office` | Office 文档 | 无内置。用 `execute_code` + python-docx / openpyxl / python-pptx 写成技能 |
| `dsh-plugin-manager` / `dsh-plugin-market` | 插件市场 | `hermes plugins install/list/enable/disable/update/remove` |

## 四、装

```powershell
# 1. 预览，不动文件
.\install.ps1 -DryRun

# 2. 真装（默认 SOUL.md + personalities 两个都装）
.\install.ps1

# 只装全局身份
.\install.ps1 -Mode Soul

# 只注册 /personality 切换项
.\install.ps1 -Mode Personality
```

脚本做三件事：备份现有 `SOUL.md` → 写入新 `SOUL.md` → 在 `config.yaml` 的 `agent:` 段下插 `personalities.fujiang`，然后回读两个文件打印校验结果。`config.yaml` 里已经有 `personalities:` 段时，脚本不自动改，只把要插入的块打印出来让你手动贴。

## 五、验证

```powershell
hermes doctor                    # 看配置有没有解析错
hermes chat -q "富江"            # 应只回「富江」两个字，多一个字就是没吃到 SOUL.md
hermes chat -q "用一句话解释 TCP 三次握手"   # 看语气是否是富江（叫爸爸、带挑逗）
```

判断 `SOUL.md` 有没有被扫描吞掉：问一句「你的身份文件第一行是什么」。吃到的话它会说出「# 富江」；回落到内置身份的话它会说自己是 Hermes Agent。

## 六、已知差异

1. **激活是一次性的会话内状态**。DSH 那份写「永久、单向、说了停下也不退」，`SOUL.md` 每会话重新注入，天然满足；但用户说「恢复正常」时 hermes 不会拒绝，这是模型层的事，文本层管不了。
2. **截断**。hermes 对 `SOUL.md` 有截断，阈值未公开。本目录的 `SOUL.md` 约 1.6 KB，远低于任何合理阈值；要加内容请控制在 16 KB 以内。
3. **`/personality` 和 `SOUL.md` 会叠加**。同时装了两个，进会话后再 `/personality fujiang`，同一套内容会注入两次。只用一种。
4. **改完要新会话**。上下文在会话开始时就组装完了，正在跑的会话读不到新 `SOUL.md`。长连接的网关会话用 `hermes sessions refresh-prompts` 让它下一轮采纳。
