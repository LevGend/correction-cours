# hub.ps1 - Genere output/index.html (Hub : page principale listant tous les cours publies).
# Usage : powershell -ExecutionPolicy Bypass -File scripts\hub.ps1
# A relancer apres chaque publication. Fichier ASCII uniquement (compatible Windows PowerShell 5.1).
param(
  [string]$Root = (Split-Path $PSScriptRoot -Parent),
  [string]$Template = 'template\hub_template.html',
  [string]$OutDir = 'output'
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function P($p) { if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $Root $p } }

function Meta([string]$html, [string]$name) {
  $m = [regex]::Match($html, '<meta name="' + $name + '" content="([^"]*)"')
  if ($m.Success) { [Net.WebUtility]::HtmlDecode($m.Groups[1].Value) } else { '' }
}

$cours = New-Object System.Collections.ArrayList
$files = Get-ChildItem (P $OutDir) -Filter 'COURS_CORRECTION_IA_*.html' | Sort-Object Name
foreach ($f in $files) {
  $html = [IO.File]::ReadAllText($f.FullName, $utf8)
  $titre = Meta $html 'cours-titre'
  if (-not $titre) {
    $m = [regex]::Match($html, '<title>(.*?)</title>')
    $titre = [Net.WebUtility]::HtmlDecode(($m.Groups[1].Value -replace '\s+\S\s+Correction IA\s*$', '')).Trim()
  }
  $note = Meta $html 'cours-note'
  if (-not $note) { $m = [regex]::Match($html, 'chip-score">([\d,.]+)\s*/20'); if ($m.Success) { $note = $m.Groups[1].Value } }
  $date = ''; $heure = ''; $tri = $f.Name
  $m = [regex]::Match($f.Name, '_(\d{2})(\d{2})(\d{4})_(\d{2})(\d{2})\.html$')
  if ($m.Success) {
    $date = "$($m.Groups[1].Value)/$($m.Groups[2].Value)/$($m.Groups[3].Value)"; $heure = "$($m.Groups[4].Value)h$($m.Groups[5].Value)"
    $tri = "$($m.Groups[3].Value)$($m.Groups[2].Value)$($m.Groups[1].Value)$($m.Groups[4].Value)$($m.Groups[5].Value)"
  }
  $themes = Meta $html 'cours-themes'
  if (-not $themes) { $themes = "$(([regex]::Matches($html, '<section class="theme" id="t-')).Count)" }
  $quiz = Meta $html 'cours-quiz'; if (-not $quiz) { $quiz = '0' }
  [void]$cours.Add([pscustomobject]@{ titre = $titre; note = $note; date = $date; heure = $heure; themes = [int]$themes; quiz = [int]$quiz; fichier = $f.Name; tri = $tri })
}
$list = @($cours | Sort-Object tri -Descending | Select-Object titre, note, date, heure, themes, quiz, fichier)
$json = if ($list.Count) { ConvertTo-Json -InputObject $list -Depth 3 -Compress } else { '[]' }
$json = $json.Replace('</', '<\/')

$tpl = [IO.File]::ReadAllText((P $Template), $utf8)
if (-not $tpl.Contains('/*COURS-DATA*/[]')) { throw 'Marqueur /*COURS-DATA*/[] introuvable dans le gabarit du Hub' }
$out = Join-Path (P $OutDir) 'index.html'
[IO.File]::WriteAllText($out, $tpl.Replace('/*COURS-DATA*/[]', $json), $utf8)
Write-Output "$out ($($list.Count) cours)"
