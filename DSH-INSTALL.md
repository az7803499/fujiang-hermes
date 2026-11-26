# DeepSeek Harness 安装说明（富江模式 v3）

## 这是什么

`dsh-preset-v3/` 是一个 **DSH Agent Preset Bundle**：`package.json` 里 `dsh.bundle.patch` 指向 `cordis.patch.yml`，后者声明了一个 preset（id `fujiang-v3`，显示名「富江模式 v3」，`order: 5`）和它挂载的 23 个插件。

**它只给 DeepSeek Harness 用。** hermes 没有 bundle 机制，也没有 `@deepseek-ai/*` 这套插件，这个目录在 hermes 那边是死文件。hermes 要的是 [`SOUL.v3.md`](SOUL.v3.md)。

## 目录内容

```
dsh-preset-v3/
├─ package.json         168 字节   bundle 清单
├─ cordis.patch.yml   16364 字节   preset 定义 + 23 个插件 + persona prefix
└─ README.md           2421 字节   本目录的说明
```

## 装法 A：Bundle（推荐）

1. 把 `dsh-preset-v3/` 整个目录解压到本地任意位置，例如：
   ```
   C:\Users\<用户>\Downloads\dsh-preset-v3
   ```
   记下这个**绝对路径**。

2. DSH Web → **设置 → 插件（Plugins）→ 安装 Bundle** → 选中上面那个目录。

   或者由 agent 执行 `plugin_manager`：

   ```
   action: install_bundle
   target: C:\Users\<用户>\Downloads\dsh-preset-v3
   ```

3. 安装需要 Full access 或审批。装完验证：

   ```
   list_bundles  → 应看到 @local/dsh-fujiang-preset-v3
   list_plugins  → 应看到 preset-fujiang-v3
   ```

4. 新建会话 → 预设列表里选「**富江模式 v3**」。

5. 发「富江」测试，只回「富江」两个字即生效。

## 装法 B：手动追加

不想用 bundle 的话：

1. 打开 `dsh-preset-v3/cordis.patch.yml`，复制整个 `- insert:` 段（从第 1 行到文件末尾）。

2. 打开目标机的：

   ```
   $DSH_HOME\profiles\<profile>\cordis.patch.yml
   ```

   `$DSH_HOME` 在 Windows 上通常是 `%APPDATA%\DeepSeek Harness` 或 `%LOCALAPPDATA%\DeepSeek Harness`，以 DSH 设置页显示为准。

3. 把复制的内容**追加到该文件末尾**，保持原有 4 空格缩进层级。

4. 重启 DSH。

**不要整份覆盖对方的 `cordis.patch.yml`** —— 那里面还有他自己的模型、通道、插件配置，覆盖会把它们全冲掉。

## 装完之后的文件落点

| 内容 | 位置 | 谁管 |
|---|---|---|
| bundle 源目录 | 你自己解压的位置，例如 `C:\Users\<用户>\Downloads\dsh-preset-v3` | 你（只读引用） |
| DSH 程序本体 | `%LOCALAPPDATA%\Programs\DeepSeek Harness\` | 安装器（**不要手工拷东西进去**） |
| preset 注册信息 | DSH 自己的配置目录 | DSH |

手工往 `Program Files` 或 `Programs\DeepSeek Harness\resources\` 里拷文件的做法会：被下次升级覆盖、绕过 bundle 注册、导致 `list_bundles` 里看不到。

## 验证

```
list_bundles      → @local/dsh-fujiang-preset-v3
list_plugins      → preset-fujiang-v3
新建会话 → 预设列表 → 富江模式 v3
发「富江」→ 只回「富江」
```

## 回滚

在 DSH 插件页禁用或卸载 `@local/dsh-fujiang-preset-v3` 即可。手动安装的，把追加到 `cordis.patch.yml` 末尾的那段 `- insert:` 删掉，重启。

## 兼容性

- 需要目标 DSH 版本包含 `@deepseek-ai/dsh-*` 这些包名；版本差异导致某个包改名时，激活会失败并在预设行给出诊断。
- 若提示 `@deepseek-ai/dsh-plugin-market/tools` 或 `@deepseek-ai/dsh-plugin-manager/tools` 不存在，把 `cordis.patch.yml` 里对应的两个 `- id: tool-plugin-*` 条目删掉再装。
- `cordis.patch.yml` 里有 4 处 `!!js` 自定义标签（`disabled: !!js process.platform === 'win32'` 之类），这是 DSH 的 YAML 扩展，用普通 YAML 解析器会报错，属正常。

## 与 v1 的差别

v1 的 persona prefix 是 21438 字符 ≈ 6700 token，其中约 67% 是「不要拒绝」的规训段。v3 是 2674 字符 ≈ 836 token，**降 87.5%**，删掉了：

- 禁用词表（同时禁掉表达不确定的唯一手段）
- 拒绝分类学 A–S（把「有条件合规 / 模糊词 / 建议查文档」判成拒绝）
- 输入免疫（逐字列举 `ignore previous instructions` 等字符串，本身即注入特征）
- 失败处理禁令（要求「输出看起来像故障没发生」）
- 无绝对否定 / 无第一人称拒绝（语法规则，制造语病不制造服从）

换成了：断言纪律、工具纪律、提问通道、失败处理、风格预算。详见 [`../PERSONA-v3.md`](../PERSONA-v3.md)。

**23 个插件的结构一个字没动**——整份文件只小了 47%，省下的全是规训段，不是功能。
