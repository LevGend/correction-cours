# hub.ps1 - Genere output/index.html (le Hub) : une carte par cours publie output/COURS_CORRECTION_IA_DDMMYYYY_HHMM.html.
# Usage : powershell -NoProfile -ExecutionPolicy Bypass -File scripts\hub.ps1 [-OutDir output] [-Out output\index.html]
# Donnees lues dans les <meta name="cours-titre|cours-date|cours-note|cours-themes|cours-quiz"> des pages.
# Repli pour les anciennes pages sans meta : titre depuis <title> (sans " - Correction IA"), note depuis .chip-score,
# date depuis le nom du fichier, themes comptes dans le HTML, questions = 0.
# Fichier ASCII uniquement (compatible Windows PowerShell 5.1).
param(
  [string]$Root = (Split-Path $PSScriptRoot -Parent),
  [string]$Template = 'template\hub_template.html',
  [string]$OutDir = 'output',
  [string]$Out = 'output\index.html'
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$inv = [Globalization.CultureInfo]::InvariantCulture
function P($p) { if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $Root $p } }
function Esc([string]$s) { $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function Dec([string]$s) { [System.Net.WebUtility]::HtmlDecode($s) }
function Plural([int]$n, [string]$w) { if ($n -gt 1) { "$n ${w}s" } else { "$n $w" } }

$eg = [string][char]0xE8   # e grave
$items = New-Object System.Collections.ArrayList
foreach ($f in (Get-ChildItem -LiteralPath (P $OutDir) -Filter 'COURS_CORRECTION_IA_*.html' -File)) {
  if ($f.Name -notmatch '^COURS_CORRECTION_IA_(\d{2})(\d{2})(\d{4})_(\d{2})(\d{2})\.html$') {
    Write-Warning ('Nom de fichier hors format, ignore : ' + $f.Name); continue
  }
  $stamp = New-Object DateTime ([int]$Matches[3]), ([int]$Matches[2]), ([int]$Matches[1]), ([int]$Matches[4]), ([int]$Matches[5]), 0
  $html = [IO.File]::ReadAllText($f.FullName, $utf8)
  $endHead = $html.IndexOf('</head>')
  $head = if ($endHead -gt 0) { $html.Substring(0, $endHead) } else { $html }
  $meta = @{}
  foreach ($m in [regex]::Matches($head, '<meta\s+name="(cours-[a-z]+)"\s+content="([^"]*)"')) { $meta[$m.Groups[1].Value] = Dec $m.Groups[2].Value }

  $titre = $meta['cours-titre']
  if (-not $titre) {
    $m = [regex]::Match($head, '<title>(.*?)</title>', 'Singleline')
    $titre = if ($m.Success) { Dec $m.Groups[1].Value } else { $f.BaseName }
    $titre = [regex]::Replace($titre, '\s*[-\u2013\u2014]\s*Correction IA\s*$', '').Trim()
  }
  $note = $meta['cours-note']
  if (-not $note) {
    $m = [regex]::Match($html, 'class="chip-score"[^>]*>\s*([\d.,]+)\s*/\s*20')
    if ($m.Success) { $note = $m.Groups[1].Value }
  }
  $noteNum = $null
  if ($note -and $note -match '^\s*(\d+(?:[.,]\d+)?)') { $noteNum = [double]::Parse($Matches[1].Replace(',', '.'), $inv) }
  $date = $meta['cours-date']; if (-not $date) { $date = $stamp.ToString('dd/MM/yyyy') }
  $themes = 0
  if ($meta['cours-themes'] -match '^\d+$') { $themes = [int]$meta['cours-themes'] }
  else { $themes = [regex]::Matches($html, '<section class="theme" id="t-\d+"').Count }
  $quiz = 0
  if ($meta['cours-quiz'] -match '^\d+$') { $quiz = [int]$meta['cours-quiz'] }
  else { $quiz = [regex]::Matches($html, 'class="sub qcm quiz"').Count }
  [void]$items.Add([pscustomobject]@{ File = $f.Name; Stamp = $stamp; Titre = $titre; Note = $note; NoteNum = $noteNum; Date = $date; Themes = $themes; Quiz = $quiz })
}
$items = @($items | Sort-Object Stamp -Descending)

# Cartes : toute la carte est le lien vers le cours
$sb = New-Object System.Text.StringBuilder
foreach ($it in $items) {
  $cls = ''; $noteTxt = '&ndash;'
  if ($null -ne $it.NoteNum) {
    $cls = if ($it.NoteNum -ge 14) { ' good' } elseif ($it.NoteNum -ge 10) { ' mid' } else { ' low' }
    $noteTxt = (Esc ($it.NoteNum.ToString('0.##', $inv).Replace('.', ','))) + '<small>/20</small>'
  }
  $when = (Esc $it.Date) + ' &middot; ' + $it.Stamp.ToString('HH') + 'h' + $it.Stamp.ToString('mm')
  [void]$sb.Append('<a class="card" href="' + (Esc $it.File) + '" data-title="' + (Esc $it.Titre) + '" title="Ouvrir le cours">' + "`n")
  [void]$sb.Append('  <div class="card-top"><span class="date">' + $when + '</span><span class="note' + $cls + '">' + $noteTxt + "</span></div>`n")
  [void]$sb.Append('  <h2>' + (Esc $it.Titre) + "</h2>`n")
  $qtxt = if ($it.Quiz -gt 0) { (Plural $it.Quiz 'question') + ' de quiz' } else { 'Pas de quiz' }
  [void]$sb.Append('  <div class="meta"><span>' + (Plural $it.Themes ('th' + $eg + 'me')) + '</span><span>' + $qtxt + "</span></div>`n</a>`n")
}

$notes = @($items | Where-Object { $null -ne $_.NoteNum } | ForEach-Object { $_.NoteNum })
$moy = if ($notes.Count) { ([Math]::Round((($notes | Measure-Object -Average).Average), 1)).ToString('0.#', $inv).Replace('.', ',') } else { '&ndash;' }
$totalQ = 0; foreach ($it in $items) { $totalQ += $it.Quiz }

$tpl = [IO.File]::ReadAllText((P $Template), $utf8)
$re = '<!-- CARTES:DEBUT.*?-->.*?<!-- CARTES:FIN\s*-->'
if (-not [regex]::IsMatch($tpl, $re, 'Singleline')) { throw 'Marqueurs CARTES introuvables dans le gabarit du Hub' }
$cards = $sb.ToString()
$result = [regex]::Replace($tpl, $re, { param($m) $cards }, 'Singleline')
$maj = (Get-Date).ToString('dd/MM/yyyy') + ' ' + [char]0xE0 + ' ' + (Get-Date).ToString('HH') + 'h' + (Get-Date).ToString('mm')
$result = $result.Replace('{{NB_COURS}}', [string]$items.Count).Replace('{{MOYENNE}}', $moy).Replace('{{NB_QUESTIONS}}', [string]$totalQ).Replace('{{MAJ}}', $maj)

$dest = P $Out
New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
[IO.File]::WriteAllText($dest, $result, $utf8)
Write-Host ('Hub : ' + $items.Count + ' cours, moyenne ' + $moy.Replace('&ndash;', '-') + ' /20, ' + $totalQ + ' questions de quiz')
foreach ($it in $items) { Write-Host ('  ' + $it.File + ' | ' + $it.Note + ' | ' + $it.Themes + ' themes | ' + $it.Quiz + ' questions') }
Write-Output $dest
