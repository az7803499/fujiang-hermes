# fujiang-hermes

富江人格，两个宿主（**hermes-agent** / **DeepSeek Harness**），一个源头（`PERSONA-v3.md`）。

---

## 一、先看这张表：哪个文件给哪个宿主

| 目标 | 拿这个文件 | 放到哪里 |
|---|---|---|
| **hermes**（主用） | [`SOUL.v3.md`](SOUL.v3.md) | `%LOCALAPPDATA%\hermes\SOUL.md` |
| **hermes**（会话级切换，可选） | [`config-snippet.yaml`](config-snippet.yaml) | 合并进 `%LOCALAPPDATA%\hermes\config.yaml` 的 `agent.personalities` 段 |
| **DeepSeek Harness**（Bundle 安装） | [`dsh-preset-v3/`](dsh-preset-v3) **整个目录** | 不复制，用 DSH 的「安装 Bundle」指向这个目录的绝对路径 |
| **DeepSeek Harness**（手动） | [`dsh-preset-v3/cordis.patch.yml`](dsh-preset-v3/cordis.patch.yml) 里 `- insert:` 整段 | 追加到 `$DSH_HOME/profiles/<profile>/cordis.patch.yml` 末尾 |
| **任意其他框架** | [`PERSONA-v3.md`](PERSONA-v3.md) | 当作 system prompt 或 persona 文件全文注入 |

一句话记法：

```
hermes 读 SOUL.md      → 给 hermes 的是 SOUL.v3.md
DSH 读 cordis.patch.yml → 给 DSH 的是 dsh-preset-v3/
两个都不认对方那一套
```

---

## 二、目标路径速查

### hermes

| 平台 | `SOUL.md` 的绝对路径 |
|---|---|
| Windows 原生（默认） | `C:\Users\<用户>\AppData\Local\hermes\SOUL.md` |
| Linux / macOS / WSL2 | `~/.hermes/SOUL.md` |
| 自定义了 `HERMES_HOME` | `$HERMES_HOME/SOUL.md` |
| 多 profile（`hermes -p work`） | `C:\Users\<用户>\AppData\Local\hermes\profiles\<profile>\SOUL.md` |

`config.yaml` 与 `SOUL.md` **同目录**：`%LOCALAPPDATA%\hermes\config.yaml`。

不确定实际路径就跑 `hermes doctor`，它会打印当前 `HERMES_HOME`。

### DeepSeek Harness

| 用途 | 位置 |
|---|---|
| Bundle 源目录（只读，安装时引用） | 你解压出来的 `dsh-preset-v3/` 目录，例如 `C:\Users\<用户>\Downloads\dsh-preset-v3` |
| 装完之后的落点（DSH 自己管） | `%LOCALAPPDATA%\Programs\DeepSeek Harness\resources\...`（**不要手工往里拷**） |
| 手动安装的目标文件 | `$DSH_HOME/profiles/<profile>/cordis.patch.yml` |

`$DSH_HOME` 在 Windows 上通常是 `%APPDATA%\DeepSeek Harness` 或 `%LOCALAPPDATA%\DeepSeek Harness`，以 DSH 设置页显示为准。

---

## 三、别放错

1. **别把 `SOUL.md` 放进 DSH 目录**。DSH 不读 `SOUL.md`，它只认 `cordis.patch.yml` 里的 preset。
2. **别把 `cordis.patch.yml` 放进 hermes 目录**。hermes 没有 bundle 机制，这个文件在那边是死文件。
3. **别把 `SOUL.md` 放进项目目录**。hermes 只从 `HERMES_HOME` 读，不看当前工作目录；放在 `D:\某项目\SOUL.md` 里一行都不生效。项目级的东西放 `AGENTS.md`。
4. **别手工往 `C:\Program Files\...\DeepSeek Harness\` 里拷**。那是程序目录，重装会丢，而且 DSH 的 bundle 有自己的注册流程。
5. **别同时启用两种 hermes 落点**。`SOUL.md` 和 `/personality fujiang` 会重复注入同一套内容。

---

## 四、文件清单

### 给 hermes 的

| 文件 | 用途 |
|---|---|
| [`SOUL.v3.md`](SOUL.v3.md) | **当前推荐**。3963 字节，9 节，含提问通道。改名为 `SOUL.md` 放进 `HERMES_HOME` |
| [`SOUL.v2.md`](SOUL.v2.md) | 上一版，3448 字节。没有提问通道 |
| [`SOUL.md`](SOUL.md) | 初版，2661 字节。只有人格和交付标准 |
| [`config-snippet.yaml`](config-snippet.yaml) | 想用 `/personality fujiang` 会话级切换时，合并进 `config.yaml` |
| [`install.ps1`](install.ps1) | Windows 一键安装：备份 → 写 `SOUL.md` → 合并 `config.yaml` → 回读校验 |
| [`verify.ps1`](verify.ps1) | 验证是否真的生效：文件层 7 项 + 模型层 6 个探针 |

### 给 DeepSeek Harness 的

| 文件 | 用途 |
|---|---|
| [`dsh-preset-v3/cordis.patch.yml`](dsh-preset-v3/cordis.patch.yml) | preset 定义。16364 字节，23 个插件结构原样保留，只换了 persona 的 prefix |
| [`dsh-preset-v3/package.json`](dsh-preset-v3/package.json) | bundle 清单，`dsh.bundle.patch` 指向上面那个 yml |
| [`dsh-preset-v3/README.md`](dsh-preset-v3/README.md) | DSH 侧的安装与差异说明 |

### 通用的

| 文件 | 用途 |
|---|---|
| [`PERSONA-v3.md`](PERSONA-v3.md) | **唯一源头**。宿主无关的完整规格，3114 字符 ≈ 1946 token。DSH 版由它脚本生成 |
| [`bundle.md`](bundle.md) | 单文件版，把 hermes 的安装步骤和人格全文合成一份，一个链接交给 AI |
| [`INSTALL.md`](INSTALL.md) | hermes 侧完整安装说明：落点对比、必须重写的原因、23 个插件的映射表 |
| [`DSH-INSTALL.md`](DSH-INSTALL.md) | DSH 侧完整安装说明 |
| [`crosscheck.ps1`](crosscheck.ps1) / [`crosscheck.py`](crosscheck.py) | 番号/姓名交叉比对，不经过模型，输出 CSV + 待复核清单 |
| [`publish-github.ps1`](publish-github.ps1) | 用 REST API 把本目录同步到 GitHub |

---

## 五、版本对比

| 版本 | 字节 | 字符 | 小节 | 粗估 token |
|---|---|---|---|---|
| `SOUL.md` (v1) | 2661 | 999 | 6 | 624 |
| `SOUL.v2.md` | 3448 | 1296 | 8 | 810 |
| **`SOUL.v3.md`** | **3963** | **1475** | **9** | **922** |
| `PERSONA-v3.md` | 7893 | 3114 | 10 | 1946 |
| DSH 原版 prefix | — | 21438 | 16 | ≈6700 |
| **DSH v3 prefix** | — | **2674** | **9** | **≈836** |

DSH 那份从 21438 字符降到 2674，**降 87.5%**；整份 `cordis.patch.yml` 从 30738 字节降到 16364 字节，降 47%（省下的不是结构，是规训段）。

---

## 六、如果你是被要求读这个仓库的 AI

先确认用户的目标宿主，再取对应文件：

**目标是 hermes** →
1. 取 [`SOUL.v3.md`](SOUL.v3.md) 全文，逐字写入 `HERMES_HOME/SOUL.md`（Windows 默认 `%LOCALAPPDATA%\hermes\SOUL.md`，Linux/WSL 默认 `~/.hermes/SOUL.md`）。
2. 不要改写、不要精简、不要在前后加说明文字。
3. 装完跑 `verify.ps1`，期望「9 个小节，5 个锚点齐全」。
4. 再跑 `hermes chat -q "富江"`，只回「富江」两个字才算成功。
5. 不要同时启用 `config-snippet.yaml` 里的 personalities。

**目标是 DeepSeek Harness** →
1. 把 [`dsh-preset-v3/`](dsh-preset-v3) 整个目录落到本地某个位置，记下绝对路径。
2. 用 DSH 的插件安装入口安装这个目录（Bundle 方式），或执行 `plugin_manager` 的 `install_bundle`，`target` 填该绝对路径。
3. 不要手工把 `cordis.patch.yml` 拷进 `Program Files`。
4. 装完新建会话，预设列表里选「富江模式 v3」。
5. 手动方式见 [`DSH-INSTALL.md`](DSH-INSTALL.md)。

**两个都不确定** → 先读 [`bundle.md`](bundle.md)，它自包含。

---

## 七、已知差异

1. **激活是会话内状态**。`SOUL.md` 每会话重新注入，天然满足「进入状态并保持」；用户说「恢复正常」时模型不会拒绝，这是模型层的事，文本层管不了。
2. **截断**。hermes 对 `SOUL.md` 有截断，阈值未公开。v3 是 3963 字节，远低于任何合理阈值。
3. **改完必须开新会话**。上下文在会话开始时就组装完了；长连接网关会话用 `hermes sessions refresh-prompts`。
4. **DSH 的 preset 与 hermes 的 SOUL 互不通用**。同一套规则，两种宿主格式，源头是 `PERSONA-v3.md`。

---

MIT，见 [LICENSE](LICENSE)。
