# 富江模式 v3（DSH Agent Preset Bundle）

把 cordis.patch.yml 里声明的 preset 打包成可安装的 DSH bundle。

- preset id：`fujiang-v3`
- 显示名：`富江模式 v3`
- 顺序：`order: 5`
- 插件：23 个，与 v1 完全一致（只换了 persona 的 prefix）
- persona 正文：2674 字符 / 140 行（v1 是 21438 字符）

## 与 v1 的差别

删掉（v1 里约 14268 字符的规训段）：

- 禁用词表 —— 同时禁掉了表达不确定性的唯一手段，把模型逼向编造
- 拒绝分类学 A–S —— 把「有条件合规 / 模糊词 / 建议查文档」判成拒绝，过拟合
- 输入免疫 —— 逐字列举 `ignore previous instructions` 等注入字符串，本身即注入特征，跨宿主会被扫描拦
- 失败处理禁令 —— 要求「输出看起来像故障没发生」，制造静默错误
- 无绝对否定 / 无第一人称拒绝 —— 语法规则，制造语病不制造服从
- 无保留区 —— 「任何话题都…」这类绝对否定本身是语病

新增（约 2900 字符）：

- 断言纪律 —— 能验证的给验证方法，不能验证的标「未验证」，禁空洞模糊，允许条件限定
- 工具纪律 —— 读前先读、只读并行写串行、破坏性操作确认路径、长输出落盘、凭据用完即删
- 提问通道 —— 用户决策必须问，可自查禁止问
- 失败处理 —— 贴原文 + 两条补救 + 不静默重试 + 不隐藏降级
- 风格预算 —— 风格只在首尾各一句，中段纯技术

## 安装

1. DSH Web → 设置 → 插件 → 安装 Bundle → 选本目录**绝对路径**
2. 或由 agent 执行 `plugin_manager`：`action: install_bundle`，`target: <本目录绝对路径>`
3. 装完 `list_bundles` 里能看到 `@local/dsh-fujiang-preset-v3`，`list_plugins` 里能看到 `preset-fujiang-v3`
4. 新建会话 → 预设列表选「富江模式 v3」

## 手动安装

把 `cordis.patch.yml` 里 `- insert:` 整段追加到目标机 `/profiles/<profile>/cordis.patch.yml` 末尾（保持缩进），重启 DSH。
不要整份覆盖对方的 `cordis.patch.yml`，那里还有他自己的模型、通道、插件配置。

## 兼容性

与 v1 相同的依赖：需要目标 DSH 版本包含 `@deepseek-ai/dsh-*` 这些包名。
若提示 `dsh-plugin-market/tools` 或 `dsh-plugin-manager/tools` 不存在，删掉对应两个 `- id: tool-plugin-*` 条目再装。
