<#
  publish-github.ps1 — 用 GitHub REST API 一次性建库 + 上传全部文件
  不需要 git、不需要 gh，只要一个 Personal Access Token（classic 勾 repo，或 fine-grained 勾 Administration:Read+Write + Contents:Read+Write）

  用法：
    $env:GITHUB_TOKEN = "ghp_xxxxxxxx"
    .\publish-github.ps1                       # 建 public 仓库 fujiang-hermes 并上传
    .\publish-github.ps1 -Private              # 建私有仓库
    .\publish-github.ps1 -Repo my-name         # 换仓库名
    .\publish-github.ps1 -DryRun               # 只打印将要发的请求，不联网

  完成后打印：仓库地址 + 每个文件的 raw 链接。
#>
[CmdletBinding()]
param(
  [string]$Owner,
  [string]$Repo = 'fujiang-hermes',
  [string]$Token = $env:GITHUB_TOKEN,
  [switch]$Private,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

$files = @(
  'README.md', 'bundle.md', 'SOUL.md', 'INSTALL.md',
  'config-snippet.yaml', 'install.ps1', 'LICENSE', '.gitignore'
)
foreach ($f in $files) {
  if (-not (Test-Path -LiteralPath (Join-Path $dir $f))) { throw "缺少文件：$f" }
}

function Invoke-GH {
  param([string]$Method, [string]$Url, $Body)
  $h = @{
    'Authorization'        = "Bearer $Token"
    'Accept'               = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'           = 'fujiang-hermes-publisher'
  }
  $p = @{ Method = $Method; Uri = $Url; Headers = $h; ContentType = 'application/json; charset=utf-8' }
  if ($null -ne $Body) { $p['Body'] = ([System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 8 -Compress))) }
  Invoke-RestMethod @p
}

if ($DryRun) {
  Write-Host "[dry] 目标仓库 : $Owner/$Repo  (private=$([bool]$Private))"
  Write-Host "[dry] 将上传 $($files.Count) 个文件："
  foreach ($f in $files) {
    $len = (Get-Item -LiteralPath (Join-Path $dir $f)).Length
    Write-Host ("       {0,-22} {1,7} 字节" -f $f, $len)
  }
  Write-Host "[dry] 请求序列：POST /user/repos  ->  PUT /repos/$Owner/$Repo/contents/<file> × $($files.Count)"
  return
}

if (-not $Token) { throw '没有 token。先设置：$env:GITHUB_TOKEN = "ghp_xxx"' }
if (-not $Owner) {
  $me = Invoke-GH GET 'https://api.github.com/user' $null
  $Owner = $me.login
  Write-Host "[i] 当前账号：$Owner"
}

# 1) 建仓库（已存在则复用）
$repoUrl = $null
try {
  $created = Invoke-GH POST 'https://api.github.com/user/repos' @{
    name        = $Repo
    private     = [bool]$Private
    auto_init   = $false
    description = '富江人格文件，移植自 DSH fujiang-preset，供 hermes-agent 使用'
  }
  $repoUrl = $created.html_url
  Write-Host "[+] 已创建仓库 $repoUrl"
} catch {
  $code = $_.Exception.Response.StatusCode.value__
  if ($code -eq 422) {
    $repoUrl = "https://github.com/$Owner/$Repo"
    Write-Host "[i] 仓库已存在，复用 $repoUrl"
  } else { throw }

  # 空仓库需要先有一个 commit 才能走 contents API 的默认分支
  try {
    Invoke-GH PUT "https://api.github.com/repos/$Owner/$Repo/contents/README.md" @{
      message = 'init'
      content = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('# init'))
    } | Out-Null
  } catch { }
}

# 2) 逐个上传
foreach ($f in $files) {
  $path = Join-Path $dir $f
  $b64  = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))

  $existingSha = $null
  try {
    $cur = Invoke-GH GET "https://api.github.com/repos/$Owner/$Repo/contents/$f" $null
    $existingSha = $cur.sha
  } catch { }

  $body = @{
    message = "add $f"
    content = $b64
    branch  = 'main'
  }
  if ($existingSha) { $body.sha = $existingSha; $body.message = "update $f" }

  try {
    Invoke-GH PUT "https://api.github.com/repos/$Owner/$Repo/contents/$f" $body | Out-Null
    Write-Host "[+] $f"
  } catch {
    Write-Host "[!] $f 失败：$($_.Exception.Message)"
  }
}

# 3) 打印链接
Write-Host ''
Write-Host '--- 仓库 ---'
Write-Host "主页 : https://github.com/$Owner/$Repo"
Write-Host ''
Write-Host '--- 发给 AI 的链接（用 raw）---'
Write-Host "单文件包 : https://raw.githubusercontent.com/$Owner/$Repo/main/bundle.md"
Write-Host "人格原文 : https://raw.githubusercontent.com/$Owner/$Repo/main/SOUL.md"
Write-Host "安装说明 : https://raw.githubusercontent.com/$Owner/$Repo/main/INSTALL.md"
Write-Host ''
Write-Host "大陆镜像 : https://cdn.jsdelivr.net/gh/$Owner/$Repo@main/bundle.md"
