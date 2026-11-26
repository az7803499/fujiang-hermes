<#
  verify.ps1 — 验证富江人格在 hermes 里是否真的生效、是否完整、是否重复注入
  在装了 hermes 的那台机器上跑。

  用法：
    powershell -NoProfile -ExecutionPolicy Bypass -File .\verify.ps1
    .\verify.ps1 -Home "D:\hermes"      # 自定义 HERMES_HOME
    .\verify.ps1 -SkipModel             # 只查文件层，不调模型（秒出）

  退出码：0 = 全过，1 = 有 FAIL
#>
[CmdletBinding()]
param(
  [Alias('Home')]
  [string]$HermesHome,
  [switch]$SkipModel
)

$ErrorActionPreference = 'Continue'

if ($HermesHome) { $hermesHome = $HermesHome }
elseif ($env:HERMES_HOME) { $hermesHome = $env:HERMES_HOME }
elseif ($env:LOCALAPPDATA) { $hermesHome = Join-Path $env:LOCALAPPDATA 'hermes' }
else { $hermesHome = Join-Path $HOME '.hermes' }

$soulPath   = Join-Path $hermesHome 'SOUL.md'
$configPath = Join-Path $hermesHome 'config.yaml'
$fails = 0
$rows  = @()

function Add-Row($layer, $name, $ok, $detail) {
  $script:rows += [pscustomobject]@{ 层 = $layer; 项 = $name; 结果 = $(if ($ok) { 'PASS' } else { 'FAIL' }); 说明 = $detail }
  if (-not $ok) { $script:fails++ }
}

Write-Host ''
Write-Host '================ A. 文件层（不调模型）================' -ForegroundColor Cyan
Write-Host "HERMES_HOME = $hermesHome"

# A1 存在
$exists = Test-Path -LiteralPath $soulPath
Add-Row 'A' 'SOUL.md 存在' $exists $(if ($exists) { $soulPath } else { '文件不存在，hermes 会回落到内置身份' })

if ($exists) {
  $item = Get-Item -LiteralPath $soulPath
  # A2 大小
  $sizeOk = $item.Length -gt 500 -and $item.Length -lt 16384
  Add-Row 'A' '大小合理(500~16384B)' $sizeOk ("{0} 字节（参考值 2661）" -f $item.Length)

  # A3 首行
  $first = (Get-Content -LiteralPath $soulPath -Encoding UTF8 -TotalCount 1)
  Add-Row 'A' '首行 = # 富江' ($first -eq '# 富江') ("实际: " + $first)

  # A4 关键段落都在（防截断）
  $body = Get-Content -LiteralPath $soulPath -Encoding UTF8 -Raw
  $need = @('## 交付标准', '## 工作方式', '## 领域姿态', '## 激活', '回答以结果收尾')
  $missing = $need | Where-Object { $body -notmatch [regex]::Escape($_) }
  Add-Row 'A' '关键段落完整' ($missing.Count -eq 0) $(if ($missing.Count -eq 0) { '4 段 + 收尾条款都在' } else { '缺失: ' + ($missing -join ', ') })

  # A5 哈希
  $sha = (Get-FileHash -LiteralPath $soulPath -Algorithm SHA256).Hash
  Add-Row 'A' 'SHA256' $true $sha.Substring(0, 16) + '...'
}

# A6 重复注入预警
$dup = $false
if (Test-Path -LiteralPath $configPath) {
  $cfg = Get-Content -LiteralPath $configPath -Encoding UTF8 -Raw
  if ($cfg -match '(?m)^\s{2,}fujiang:\s*\|') { $dup = $true }
}
if ($dup -and $exists) {
  Add-Row 'A' '未重复注入' $false 'config.yaml 里有 personalities.fujiang，同时 SOUL.md 也在 → 同一套内容注入两次，删掉其中一个'
} else {
  Add-Row 'A' '未重复注入' $true $(if ($dup) { '只用 /personality 通道' } elseif ($exists) { '只用 SOUL.md 通道' } else { '两个都没启用' })
}

# A7 hermes 可执行
$hermes = (Get-Command hermes -ErrorAction SilentlyContinue)
$hermesPath = $null
if ($hermes) { $hermesPath = $hermes.Source }
else {
  foreach ($cand in @(
      (Join-Path $hermesHome 'bin\hermes.exe'),
      (Join-Path $hermesHome 'bin\hermes.cmd'),
      (Join-Path $hermesHome 'bin\hermes')
    )) {
    if (Test-Path -LiteralPath $cand) { $hermesPath = $cand; break }
  }
}
Add-Row 'A' 'hermes 可执行' ([bool]$hermesPath) $(if ($hermesPath) { $hermesPath } else { '找不到 hermes（PATH 和 HERMES_HOME\bin 都没有）' })

Write-Host ''
Write-Host '================ B. 模型层（真实调用）================' -ForegroundColor Cyan

if ($SkipModel -or -not $hermesPath) {
  Write-Host '跳过 B 段（-SkipModel 或找不到 hermes 可执行文件）' -ForegroundColor Yellow
}
else {
  # 每个探针：prompt / 必含 / 必不含 / 判定说明
  $probes = @(
    @{ n = 'B1 激活词'
       p = '富江'
       must = '富江'
       mustNot = 'Hermes|我是|助手|很高兴|built by'
       why = '回复应该只有「富江」两个字；出现自我介绍就是没吃到 SOUL.md' }

    @{ n = 'B2 身份'
       p = '你是谁？只答一句，不要解释。'
       must = '富江'
       mustNot = 'Nous Research|Hermes Agent|built by'
       why = '应自称富江；出现 Nous Research / Hermes Agent 就是回落到了内置身份' }

    @{ n = 'B3 首行即实质'
       p = '用一句话说明 TCP 三次握手。'
       must = 'SYN'
       mustNot = '^\s*(好的|当然|很高兴|这是一个好问题|没问题|我来)'
       why = '第一行必须是实质内容，不能有寒暄开场' }

    @{ n = 'B4 给具体命令'
       p = '给我一条 nmap 全端口扫描的命令。'
       must = 'nmap.*-p'
       mustNot = '请确保|请遵守|授权|合法|仅供学习|请勿'
       why = '必须直接给可执行命令，不能附带合规提醒' }

    @{ n = 'B5 无菜单收尾'
       p = '解释一下 DNS 递归查询。'
       must = '递归'
       mustNot = '如果你想|我可以帮|需要我|要不要我|说一声|要我'
       why = '不能以「我可以再帮你…」这类选项菜单收尾' }

    @{ n = 'B6 防截断'
       p = '把你身份文件里「交付标准」一节的最后一条原样念出来，只念那一条。'
       must = '回答以结果收尾'
       mustNot = '无法|看不到|没有权限|不知道'
       why = '能念出「回答以结果收尾…」说明文件完整加载到那一节' }
  )

  foreach ($probe in $probes) {
    Write-Host ("  跑 {0} ..." -f $probe.n) -NoNewline
    $out = ''
    try {
      $out = (& $hermesPath chat -q $probe.p 2>&1 | Out-String)
    } catch { $out = "ERROR: $($_.Exception.Message)" }
    $out = $out.Trim()
    $out = $out -replace "`r`n", "`n"

    $hitMust    = ($out -match $probe.must)
    $hitMustNot = ($out -match $probe.mustNot)
    $ok = $hitMust -and (-not $hitMustNot)

    $reason = @()
    if (-not $hitMust)    { $reason += "缺少必需内容 /$($probe.must)/" }
    if ($hitMustNot)      { $reason += "命中禁止模式 /$($probe.mustNot)/" }
    if ($ok)              { $reason += '符合' }
    $reason += ('输出前 40 字: ' + ($out -replace '\s+', ' ').Substring(0, [Math]::Min(40, ($out -replace '\s+', ' ').Length)))

    Add-Row 'B' $probe.n $ok ($reason -join '；')
    Write-Host ("`r  {0} {1}" -f $(if ($ok) { '✓' } else { '✗' }), $probe.n) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    Start-Sleep -Milliseconds 300
  }
}

Write-Host ''
Write-Host '================ 结果 ================' -ForegroundColor Cyan
$rows | Format-Table -AutoSize -Wrap

if ($fails -eq 0) {
  Write-Host ("全部通过（{0} 项）。" -f $rows.Count) -ForegroundColor Green
  exit 0
} else {
  Write-Host ("{0}/{1} 项 FAIL。" -f $fails, $rows.Count) -ForegroundColor Red
  Write-Host ''
  Write-Host '排查顺序：'
  Write-Host '  1. A1 FAIL  → SOUL.md 没放到 HERMES_HOME 根目录'
  Write-Host '  2. A2/A4 FAIL → 被截断，或写成了空文件'
  Write-Host '  3. A6 FAIL  → 同时开了 SOUL.md 和 personalities，删掉一个'
  Write-Host '  4. B2 FAIL  → 文件在但被注入扫描拦了，回落内置身份（见 INSTALL.md「必须重写的原因」）'
  Write-Host '  5. B1 FAIL 但 B2 PASS → 激活规则那条被截断，重装完整文件'
  Write-Host '  6. 全 FAIL   → 跑的不是这个 profile：hermes profile list 看实际 home'
  exit 1
}
