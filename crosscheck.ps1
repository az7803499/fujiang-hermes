<#
  crosscheck.ps1 — 番号 + 演员名交叉比对，全程不经过任何模型。
  纯 PowerShell 实现，不需要 Python、不需要联网。

  用法：
    .\crosscheck.ps1 -A avwiki.jsonl -B scenedex.jsonl
    .\crosscheck.ps1 -A a.jsonl -B b.jsonl -Out r.csv -Threshold 0.86

  输入 JSONL 字段自动适配：
    番号: code / 番号 / id / product_id / number
    标题: title / 标题 / name
    演员: performers / actress / actresses / 演员 / cast   (list 或字符串，逗号/顿号/斜杠分隔)

  输出：
    result.csv    每个番号一行，含匹配结论
    review.jsonl  仅 needs_review=1 的条目，供人工复核
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$A,
  [Parameter(Mandatory=$true)][string]$B,
  [string]$Out = 'result.csv',
  [string]$Review = 'review.jsonl',
  [double]$Threshold = 0.80
)

$ErrorActionPreference = 'Stop'

$CodeKeys  = @('code','番号','id','product_id','number')
$TitleKeys = @('title','标题','name')
$NameKeys  = @('performers','actress','actresses','演员','cast')

function Normalize-Code([string]$raw) {
  if (-not $raw) { return '' }
  $s = $raw.Trim().ToUpper()
  # 全角转半角
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $s.ToCharArray()) {
    $o = [int]$ch
    if ($o -ge 0xFF01 -and $o -le 0xFF5E) { [void]$sb.Append([char]($o - 0xFEE0)) }
    elseif ($o -eq 0x3000) { [void]$sb.Append(' ') }
    else { [void]$sb.Append($ch) }
  }
  $s = $sb.ToString()
  # 各种破折号/下划线/空格统一成 -
  $s = $s -replace '[\u2010-\u2015\u2212\u30FB\u00B7_~\s]+', '-'
  $m = [regex]::Match($s, '^([A-Z]+)[-]*0*(\d+)(?:[-].*)?$')
  if ($m.Success) {
    return ('{0}-{1}' -f $m.Groups[1].Value, [int]$m.Groups[2].Value)
  }
  return ($s -replace '[^A-Z0-9]', '')
}

function Normalize-Name([string]$raw) {
  if (-not $raw) { return '' }
  $s = $raw.Trim().ToLower()
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $s.ToCharArray()) {
    $o = [int]$ch
    if ($o -ge 0xFF01 -and $o -le 0xFF5E) { [void]$sb.Append([char]($o - 0xFEE0)) }
    elseif ($o -ge 0x30A1 -and $o -le 0x30F6) { [void]$sb.Append([char]($o - 0x60)) }  # 片假名->平假名
    else { [void]$sb.Append($ch) }
  }
  $s = $sb.ToString()
  return ($s -replace '[\s\u30FB\u00B7\.,、，/／|｜_\-]+', '')
}

function Split-Names($v) {
  if ($null -eq $v) { return @() }
  if ($v -is [System.Array]) { return @($v | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) }
  return @(("$v" -split '[,、，/／|｜;；]+') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-Levenshtein([string]$s, [string]$t) {
  if ($s -eq $t) { return 0 }
  if (-not $s) { return $t.Length }
  if (-not $t) { return $s.Length }
  $n = $s.Length; $m = $t.Length
  $prev = New-Object int[] ($m + 1)
  $cur  = New-Object int[] ($m + 1)
  for ($j = 0; $j -le $m; $j++) { $prev[$j] = $j }
  for ($i = 1; $i -le $n; $i++) {
    $cur[0] = $i
    for ($j = 1; $j -le $m; $j++) {
      $cost = if ($s[$i-1] -eq $t[$j-1]) { 0 } else { 1 }
      $a = $prev[$j] + 1
      $b = $cur[$j-1] + 1
      $c = $prev[$j-1] + $cost
      $cur[$j] = [Math]::Min([Math]::Min($a, $b), $c)
    }
    $tmp = $prev; $prev = $cur; $cur = $tmp
  }
  return $prev[$m]
}

function Get-Similarity([string]$s, [string]$t) {
  if (-not $s -and -not $t) { return 1.0 }
  $max = [Math]::Max($s.Length, $t.Length)
  if ($max -eq 0) { return 1.0 }
  return [Math]::Round(1.0 - ((Get-Levenshtein $s $t) / $max), 3)
}

function Pick-Field($obj, [string[]]$keys) {
  foreach ($k in $keys) {
    if ($obj.PSObject.Properties.Name -contains $k) {
      $v = $obj.$k
      if ($null -ne $v -and "$v" -ne '') { return $v }
    }
  }
  return $null
}

function Import-Jsonl([string]$path) {
  $rows = @()
  $i = 0
  foreach ($line in (Get-Content -LiteralPath $path -Encoding UTF8)) {
    $i++
    if (-not $line.Trim()) { continue }
    try { $rows += ($line | ConvertFrom-Json) }
    catch { Write-Warning ("{0}:{1} 不是合法 JSON，跳过" -f $path, $i) }
  }
  return $rows
}

Write-Host "[i] 读取 A: $A"
$rowsA = Import-Jsonl $A
Write-Host "[i] 读取 B: $B"
$rowsB = Import-Jsonl $B

$idxA = @{}; $idxB = @{}
foreach ($r in $rowsA) { $k = Normalize-Code (Pick-Field $r $CodeKeys); if ($k) { if (-not $idxA.ContainsKey($k)) { $idxA[$k] = $r } } }
foreach ($r in $rowsB) { $k = Normalize-Code (Pick-Field $r $CodeKeys); if ($k) { if (-not $idxB.ContainsKey($k)) { $idxB[$k] = $r } } }

$keys = @($idxA.Keys + $idxB.Keys | Sort-Object -Unique)
Write-Host ("[i] A {0} 条 / B {1} 条 / 合并键 {2} 个" -f $rowsA.Count, $rowsB.Count, $keys.Count)

$stat = @{ both=0; onlyA=0; onlyB=0; exact=0; fuzzy=0; none=0; missing=0; review=0 }
$csv = New-Object System.Collections.Generic.List[string]
$csv.Add('code_raw,code_norm,in_avwiki,in_scenedex,name_a,name_b,match,score,needs_review,title_a,title_b')
$rev = New-Object System.Collections.Generic.List[string]

function Esc([string]$s) {
  if ($null -eq $s) { return '' }
  if ($s -match '[",\r\n]') { return '"' + ($s -replace '"','""') + '"' }
  return $s
}

foreach ($k in $keys) {
  $ra = $idxA[$k]; $rb = $idxB[$k]
  $ta = if ($ra) { "$(Pick-Field $ra $TitleKeys)" } else { '' }
  $tb = if ($rb) { "$(Pick-Field $rb $TitleKeys)" } else { '' }
  $na = @(if ($ra) { Split-Names (Pick-Field $ra $NameKeys) } else { @() })
  $nb = @(if ($rb) { Split-Names (Pick-Field $rb $NameKeys) } else { @() })
  $rawCode = if ($ra) { "$(Pick-Field $ra $CodeKeys)" } elseif ($rb) { "$(Pick-Field $rb $CodeKeys)" } else { $k }

  $nameA=''; $nameB=''; $kind=''; $score=0.0

  if ($ra -and $rb) {
    $stat.both++
    if ($na.Count -eq 0 -or $nb.Count -eq 0) { $kind='missing'; $score=0.0 }
    else {
      $normA = @($na | ForEach-Object { Normalize-Name $_ })
      $normB = @($nb | ForEach-Object { Normalize-Name $_ })
      $hit = $false
      for ($i=0; $i -lt $normA.Count -and -not $hit; $i++) {
        for ($j=0; $j -lt $normB.Count; $j++) {
          if ($normA[$i] -and $normA[$i] -eq $normB[$j]) {
            $nameA=$na[$i]; $nameB=$nb[$j]; $kind='exact'; $score=1.0; $hit=$true; break
          }
        }
      }
      if (-not $hit) {
        $best=-1.0; $bi=-1; $bj=-1
        for ($i=0; $i -lt $normA.Count; $i++) {
          for ($j=0; $j -lt $normB.Count; $j++) {
            if (-not $normA[$i] -or -not $normB[$j]) { continue }
            $r = Get-Similarity $normA[$i] $normB[$j]
            if ($r -gt $best) { $best=$r; $bi=$i; $bj=$j }
          }
        }
        if ($bi -ge 0) { $nameA=$na[$bi]; $nameB=$nb[$bj]; $score=$best }
        $kind = if ($best -ge $Threshold) { 'fuzzy' } else { 'none' }
      }
    }
  }
  elseif ($ra) { $stat.onlyA++; $nameA = if ($na.Count) { $na[0] } else { '' }; $kind='missing' }
  else         { $stat.onlyB++; $nameB = if ($nb.Count) { $nb[0] } else { '' }; $kind='missing' }

  $stat[$kind] = $stat[$kind] + 1
  $needRev = ($kind -in 'none','missing') -or ($kind -eq 'fuzzy' -and $score -lt 0.9)
  if ($needRev) {
    $stat.review++
    $rev.Add((@{ code=$k; match=$kind; score=$score; name_a=$nameA; name_b=$nameB; title_a=$ta; title_b=$tb } | ConvertTo-Json -Compress))
  }

  $csv.Add(('{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10}' -f `
    (Esc $rawCode), (Esc $k), [int][bool]$ra, [int][bool]$rb, (Esc $nameA), (Esc $nameB), $kind, $score, [int]$needRev, (Esc $ta), (Esc $tb)))
}

Set-Content -LiteralPath $Out -Value $csv -Encoding UTF8
Set-Content -LiteralPath $Review -Value $rev -Encoding UTF8

Write-Host ''
Write-Host '--- 结果 ---'
Write-Host ("两边都有 {0} ｜ 仅 A {1} ｜ 仅 B {2}" -f $stat.both, $stat.onlyA, $stat.onlyB)
Write-Host ("姓名 exact {0} ｜ fuzzy {1} ｜ none {2} ｜ missing {3}" -f $stat.exact, $stat.fuzzy, $stat.none, $stat.missing)
Write-Host ("待复核 {0} 条 -> {1}" -f $stat.review, $Review)
Write-Host ("明细 -> {0}" -f $Out)
