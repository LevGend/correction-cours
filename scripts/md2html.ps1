# md2html.ps1 - Convertit 03_organise.md et 02_evaluation.md en HTML autonome a partir du gabarit.
# Usage : powershell -ExecutionPolicy Bypass -File scripts\md2html.ps1 -Date "05/11/2026" -Note "14,5" [-Out output\COURS_CORRECTION_IA_DDMMYYYY_HHMM.html]
#         [-Cours work\03_organise.md] [-Eval ...] [-TitreFile ...] [-QuizFile ...] [-SiglesFile ...]
# Par defaut, -Eval, -TitreFile, -QuizFile et -SiglesFile sont cherches dans le dossier de -Cours
# (02_evaluation.md, 03_titre.txt, 04_quiz.md, 02_sigles.md) : -Cours archive\T1_proxmox\03_organise.md suffit pour un cours archive.
# Si le fichier quiz existe : "# Revision" = une petite question QCM a la fin de chaque sous-theme (H2/H3), "# Quiz" = onglet Quiz (une serie par "## QCM n").
# Sans fichier quiz : ni onglet Quiz, ni petites questions.
# Chapitre 0 : si le premier H2 est "Lexique", il est numerote 0 (les themes suivants gardent 1, 2, 3...) et n'a pas de question de revision.
# Sigles : tableau "| Sigle | Signification |" de 02_sigles.md (repli : tableau du "### Sigles" du Lexique). Chaque occurrence d'un sigle
# dans le texte (Cours, Quiz, Bilan) recoit une info-bulle <abbr class="sig">, jamais dans pre/code/liens/attributs/H1/H2/colonne Sigle du Lexique.
# Fichier ASCII uniquement (compatible Windows PowerShell 5.1).
param(
  [string]$Root = (Split-Path $PSScriptRoot -Parent),
  [string]$Template = 'template\cours_template.html',
  [string]$Cours = 'work\03_organise.md',
  [string]$Eval = '',
  [string]$TitreFile = '',
  [string]$QuizFile = '',
  [string]$SiglesFile = '',
  [string]$Date = (Get-Date -Format 'dd/MM/yyyy'),
  [string]$Note = '',
  [string]$Out = ''
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function P($p) { if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $Root $p } }
function ReadU($p) { [IO.File]::ReadAllText((P $p), $utf8) }

# Fichiers compagnons : par defaut dans le dossier de -Cours
$coursDir = Split-Path (P $Cours) -Parent
if (-not $Eval) { $Eval = Join-Path $coursDir '02_evaluation.md' }
if (-not $TitreFile) { $TitreFile = Join-Path $coursDir '03_titre.txt' }
if (-not $QuizFile) { $QuizFile = Join-Path $coursDir '04_quiz.md' }
if (-not $SiglesFile) { $SiglesFile = Join-Path $coursDir '02_sigles.md' }

$script:imgBase = Split-Path (P $Cours) -Parent
$script:codes = New-Object System.Collections.ArrayList
$script:links = New-Object System.Collections.ArrayList

function Esc([string]$s) {
  $s = $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
  $s
}

function EscA([string]$s) { (Esc $s).Replace('"', '&quot;') }

function Inline([string]$s) {
  $script:codes.Clear(); $script:links.Clear()
  # 1. code
  $s = [regex]::Replace($s, '`([^`]+)`', {
    param($m) [void]$script:codes.Add('<code>' + (Esc $m.Groups[1].Value) + '</code>')
    '@@C' + ($script:codes.Count - 1) + '@@' })
  # 2. echappement du texte hors balises HTML autorisees
  $tag = '(</?(?:span|div|b|i|em|strong|br|a|u|sub|sup|mark|small|del|ins)\b[^>]*>)'
  $parts = [regex]::Split($s, $tag)
  $sb = New-Object System.Text.StringBuilder
  foreach ($p in $parts) {
    if ($p -match ('^' + $tag + '$')) { [void]$sb.Append($p) }
    else {
      $t = [regex]::Replace($p, '&(?!#?\w+;)', '&amp;')
      $t = $t.Replace('<', '&lt;').Replace('>', '&gt;')
      [void]$sb.Append($t)
    }
  }
  $s = $sb.ToString()
  # 3. gras, liens, URL nues
  $s = [regex]::Replace($s, '\*\*(.+?)\*\*', '<strong>$1</strong>')
  $s = [regex]::Replace($s, '\[([^\]]+)\]\((https?://[^)\s]+)\)', {
    param($m) [void]$script:links.Add('<a href="' + $m.Groups[2].Value + '" target="_blank" rel="noopener">' + $m.Groups[1].Value + '</a>')
    '@@L' + ($script:links.Count - 1) + '@@' })
  $s = [regex]::Replace($s, '(?<![="''>(])https?://[^\s<>"]+', {
    param($m)
    $u = $m.Value; $tail = ''
    while ($u -match '[.,;:)!?]$') { $tail = $u.Substring($u.Length - 1) + $tail; $u = $u.Substring(0, $u.Length - 1) }
    [void]$script:links.Add('<a href="' + $u + '" target="_blank" rel="noopener">' + $u + '</a>')
    '@@L' + ($script:links.Count - 1) + '@@' + $tail })
  # 4. restauration
  $s = [regex]::Replace($s, '@@L(\d+)@@', { param($m) $script:links[[int]$m.Groups[1].Value] })
  $s = [regex]::Replace($s, '@@C(\d+)@@', { param($m) $script:codes[[int]$m.Groups[1].Value] })
  $s
}

function ImgTag([string]$rel, [string]$alt) {
  $f = Join-Path $script:imgBase $rel
  if (-not (Test-Path $f)) { throw "Image introuvable : $f" }
  $ext = [IO.Path]::GetExtension($f).TrimStart('.').ToLower()
  if ($ext -eq 'jpg') { $ext = 'jpeg' }
  $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f))
  '<img src="data:image/' + $ext + ';base64,' + $b64 + '" alt="' + (Esc $alt) + '" style="max-width:100%;border-radius:8px">'
}

function SplitRow([string]$l) {
  $l = $l.Trim()
  if ($l.StartsWith('|')) { $l = $l.Substring(1) }
  if ($l.EndsWith('|')) { $l = $l.Substring(0, $l.Length - 1) }
  , @($l.Split('|') | ForEach-Object { $_.Trim() })
}

# $cls = 'lex-sigles' : tableau des sigles du Lexique (1re colonne en td.sig-name, sans info-bulle)
function TableHtml($rows, [string]$cls = '') {
  $sb = New-Object System.Text.StringBuilder
  if ($cls) { [void]$sb.Append('<table class="' + $cls + '">' + "`n") } else { [void]$sb.Append("<table>`n") }
  $start = 0
  if ($rows.Count -ge 2 -and $rows[1] -match '^\s*\|?[\s:\-|]+\|?\s*$' -and $rows[1] -match '-') {
    $h = SplitRow $rows[0]
    if (($h | Where-Object { $_ -ne '' }).Count -gt 0) {
      [void]$sb.Append('<thead><tr>')
      foreach ($c in $h) { [void]$sb.Append('<th>' + (Inline $c) + '</th>') }
      [void]$sb.Append("</tr></thead>`n")
    }
    $start = 2
  }
  [void]$sb.Append('<tbody>')
  for ($i = $start; $i -lt $rows.Count; $i++) {
    [void]$sb.Append('<tr>')
    $j = 0
    foreach ($c in (SplitRow $rows[$i])) {
      $td = if ($cls -eq 'lex-sigles' -and $j -eq 0) { '<td class="sig-name">' } else { '<td>' }
      [void]$sb.Append($td + (Inline $c) + '</td>'); $j++
    }
    [void]$sb.Append("</tr>`n")
  }
  [void]$sb.Append("</tbody></table>`n")
  $sb.ToString()
}

function ListHtml($items) {
  $sb = New-Object System.Text.StringBuilder
  $stack = New-Object System.Collections.ArrayList   # elements: @(indent, tag)
  foreach ($it in $items) {
    $ind = $it.indent; $tag = if ($it.ordered) { 'ol' } else { 'ul' }
    if ($stack.Count -eq 0) {
      [void]$sb.Append("<$tag>`n<li>"); [void]$stack.Add(@($ind, $tag))
    } elseif ($ind -gt $stack[$stack.Count - 1][0]) {
      [void]$sb.Append("`n<$tag>`n<li>"); [void]$stack.Add(@($ind, $tag))
    } else {
      while ($stack.Count -gt 1 -and $ind -lt $stack[$stack.Count - 1][0]) {
        [void]$sb.Append('</li>' + "`n</" + $stack[$stack.Count - 1][1] + '>')
        $stack.RemoveAt($stack.Count - 1)
      }
      [void]$sb.Append("</li>`n<li>")
    }
    [void]$sb.Append((Inline $it.text))
  }
  for ($k = $stack.Count - 1; $k -ge 0; $k--) { [void]$sb.Append('</li>' + "`n</" + $stack[$k][1] + ">`n") }
  $sb.ToString()
}

# Bloc :::concept Nom / @theorie / @pratique / @exemple / ::: -> carte .concept
# L'exemple "riche" (code, image, tableau, liste, plusieurs paragraphes ou > 120 caracteres) est replie derriere un bouton.
function ConceptHtml([string]$name, [string[]]$lines, [ref]$idx) {
  $i = $idx.Value + 1; $parts = [ordered]@{}; $cur = $null; $inCode = $false
  while ($i -lt $lines.Count) {
    $t = $lines[$i].Trim()
    if ($t -match '^```') { $inCode = -not $inCode }
    if (-not $inCode -and $t -match '^:::\s*$') { $i++; break }
    if (-not $inCode -and $t -match '^@(theorie|pratique|exemple)\s*$') { $cur = $Matches[1]; $parts[$cur] = New-Object System.Collections.ArrayList }
    elseif ($cur) { [void]$parts[$cur].Add($lines[$i]) }
    $i++
  }
  $idx.Value = $i
  $labels = @{ theorie = "Th$([char]0xE9)orie"; pratique = 'Pratique'; exemple = 'Exemple' }
  $sb = New-Object System.Text.StringBuilder
  # Titre dans un <span> : le conteneur est en flex (les info-bulles de sigles ne doivent pas devenir des elements flex)
  [void]$sb.Append('<div class="concept"><div class="concept-title"><span>' + (Inline $name.Trim()) + "</span></div>`n")
  foreach ($k in 'theorie', 'pratique', 'exemple') {
    if (-not $parts.Contains($k)) { continue }
    $body = ConvertBlocks ([string[]]$parts[$k].ToArray()) $false
    if ($body.Trim() -eq '') { continue }
    $block = '<div class="tpe tpe-' + $k + '"><div class="tpe-label">' + $labels[$k] + '</div><div class="tpe-body">' + "`n$body</div></div>`n"
    if ($k -eq 'exemple') {
      $plain = [regex]::Replace($body, '<[^>]+>', '').Trim()
      $rich = ($body -match '<(pre|img|table|ul|ol)\b') -or ([regex]::Matches($body, '<p>').Count -gt 1) -or ($plain.Length -gt 120)
      if ($rich) {
        $block = '<button type="button" class="btn-ex" aria-expanded="false">Voir des exemples</button>' + "`n" + $block.Replace('<div class="tpe tpe-exemple">', '<div class="tpe tpe-exemple" hidden>')
      }
    }
    [void]$sb.Append($block)
  }
  [void]$sb.Append("</div>`n")
  $sb.ToString()
}

# Convertit des lignes Markdown en HTML. $top = traite aussi ## et ### (sections).
function ConvertBlocks([string[]]$lines, [bool]$top) {
  $sb = New-Object System.Text.StringBuilder
  $para = New-Object System.Collections.ArrayList
  $state = @{ theme = 0; sub = 0; inTheme = $false; inSub = $false; h2 = ''; h3 = ''; nH2 = 0; lex = $false }
  # Fermeture d'un sous-theme : la petite question de revision correspondante se place juste avant </section>
  $closeSub = {
    if ($state.inSub) {
      [void]$sb.Append((RevFor $state.h2 $state.h3 ('r-' + $state.theme + '-' + $state.sub) $state.lex))
      [void]$sb.Append("</section>`n"); $state.inSub = $false
    }
  }
  $flush = {
    if ($para.Count -gt 0) {
      $txt = ($para | ForEach-Object { Inline $_ }) -join "<br>`n"
      [void]$sb.Append("<p>$txt</p>`n"); $para.Clear()
    }
  }
  $i = 0
  while ($i -lt $lines.Count) {
    $l = $lines[$i]; $t = $l.Trim()
    if ($t -eq '') { & $flush; $i++; continue }
    if ($top -and $t -match '^# [^#]') { & $flush; $i++; continue }
    if ($top -and $t -match '^## (.+)$') {
      & $flush
      $hd = $Matches[1]
      & $closeSub
      if ($state.inTheme) { [void]$sb.Append("</section>`n") }
      # Chapitre 0 : le premier H2 "Lexique" est numerote 0, les themes suivants gardent 1, 2, 3...
      $state.lex = ($state.nH2 -eq 0) -and ((NormKey $hd) -match '^lexique\b')
      $state.nH2++
      if (-not $state.lex) { $state.theme++ } else { $script:hasLex = $true }
      $state.sub = 0; $state.inTheme = $true; $state.h2 = $hd
      $tcls = if ($state.lex) { 'theme lexique' } else { 'theme' }
      [void]$sb.Append('<section class="' + $tcls + '" id="t-' + $state.theme + '" data-num="' + $state.theme + '"><h2>' + (Inline $hd) + "</h2>`n")
      $i++; continue
    }
    if ($top -and $t -match '^### (.+)$') {
      & $flush
      $hd = $Matches[1]
      & $closeSub
      $state.sub++; $state.inSub = $true; $state.h3 = $hd
      [void]$sb.Append('<section class="sub" id="t-' + $state.theme + '-' + $state.sub + '"><h3>' + (Inline $hd) + "</h3>`n")
      $i++; continue
    }
    if ($t -match '^:::concept\s+(.+)$') {
      & $flush
      [void]$sb.Append((ConceptHtml $Matches[1] $lines ([ref]$i)))
      continue
    }
    if ($t -match '^```\s*([\w+#-]*)') {
      & $flush
      $lang = $Matches[1]; $code = New-Object System.Collections.ArrayList; $i++
      while ($i -lt $lines.Count -and $lines[$i].Trim() -notmatch '^```') { [void]$code.Add($lines[$i]); $i++ }
      $i++
      $cls = if ($lang) { ' class="lang-' + $lang + '"' } else { '' }
      [void]$sb.Append('<pre><code' + $cls + '>' + (Esc ($code -join "`n")) + "</code></pre>`n")
      continue
    }
    if ($t -match '^>') {
      & $flush
      $q = New-Object System.Collections.ArrayList
      while ($i -lt $lines.Count -and $lines[$i].Trim() -match '^>') { [void]$q.Add(($lines[$i].Trim() -replace '^>\s?', '')); $i++ }
      $cls = ''
      if ($q.Count -gt 0 -and $q[0].Trim() -match '^\[!(\w+)\]\s*(.*)$') {
        $k = $Matches[1].ToLower(); $rest = $Matches[2]
        $map = @{ def = 'def'; definition = 'def'; important = 'important'; exemple = 'exemple'; attention = 'attention' }
        if ($map.ContainsKey($k)) { $cls = $map[$k] }
        $q.RemoveAt(0)
        if ($rest.Trim() -ne '') { $q.Insert(0, $rest) }
      }
      $inner = ConvertBlocks ([string[]]$q.ToArray()) $false
      if ($cls) { [void]$sb.Append('<div class="callout ' + $cls + '">' + "`n$inner</div>`n") }
      else { [void]$sb.Append("<blockquote>`n$inner</blockquote>`n") }
      continue
    }
    if ($t -match '^\|') {
      & $flush
      $rows = New-Object System.Collections.ArrayList
      while ($i -lt $lines.Count -and $lines[$i].Trim() -match '^\|') { [void]$rows.Add($lines[$i]); $i++ }
      $tcls = ''
      if ($top -and $state.lex -and $state.inSub -and (NormKey $state.h3) -match '^sigles?$') {
        $tcls = 'lex-sigles'
        if ($script:lexRows.Count -eq 0) { $script:lexRows.AddRange($rows) }
      }
      [void]$sb.Append((TableHtml $rows $tcls))
      continue
    }
    if ($t -match '^<div\b') {
      & $flush
      $buf = New-Object System.Collections.ArrayList; $depth = 0
      do {
        $cur = $lines[$i]; [void]$buf.Add($cur)
        $depth += ([regex]::Matches($cur, '<div\b')).Count - ([regex]::Matches($cur, '</div>')).Count
        $i++
      } while ($depth -gt 0 -and $i -lt $lines.Count)
      $all = $buf -join "`n"
      $m = [regex]::Match($all, '^\s*(<div[^>]*>)(.*)</div>\s*$', 'Singleline')
      if ($m.Success) {
        $inner = ConvertBlocks ([string[]]($m.Groups[2].Value -split "`r?`n")) $false
        [void]$sb.Append($m.Groups[1].Value + "`n$inner</div>`n")
      } else { [void]$sb.Append($all + "`n") }
      continue
    }
    if ($l -match '^\s*(?:[-*]|\d+\.)\s+') {
      & $flush
      $items = New-Object System.Collections.ArrayList
      while ($i -lt $lines.Count -and $lines[$i] -match '^(\s*)([-*]|\d+\.)\s+(.*)$') {
        [void]$items.Add(@{ indent = $Matches[1].Replace("`t", '    ').Length; ordered = ($Matches[2] -match '\d'); text = $Matches[3] })
        $i++
      }
      [void]$sb.Append((ListHtml $items))
      continue
    }
    if ($t -match '^!\[([^\]]*)\]\(([^)]+)\)\s*$') {
      & $flush
      [void]$sb.Append('<p>' + (ImgTag $Matches[2] $Matches[1]) + "</p>`n"); $i++; continue
    }
    if ($t -match '^(?:---+|\*\*\*+)$') { & $flush; $i++; continue }
    [void]$para.Add($t); $i++
  }
  & $flush
  if ($top) {
    & $closeSub
    if ($state.inTheme) { [void]$sb.Append("</section>`n") }
  }
  $sb.ToString()
}

function Lines([string]$s) { [string[]]($s -split "`r?`n") }

# ---------- Quiz et questions de revision (work/04_quiz.md) ----------
$script:rev = @{}                                          # "h2|h3" normalises -> question
$script:revByH3 = @{}                                      # h3 normalise -> liste de questions
$script:revAll = New-Object System.Collections.ArrayList
$script:series = New-Object System.Collections.ArrayList   # @{ title; qs }
$script:qBad = New-Object System.Collections.ArrayList
$script:hasRev = $false
$script:revStats = @{ subs = 0; hit = 0 }
$script:MID = [string][char]0xB7
$script:E_ = [string][char]0xE9

# Cle de comparaison tolerante : sans balises, sans Markdown, sans numero en tete, sans casse ni ponctuation, espaces simples.
function NormKey([string]$s) {
  $s = [regex]::Replace($s, '<[^>]+>', ' ')
  $s = $s.Replace('**', '').Replace('`', '')
  $s = [regex]::Replace($s, '^\s*(?:(?:module|partie|chapitre)\s+)?\d+(?:\.\d+)*\s*[.):-]?\s+', '', 'IgnoreCase')
  $s = [regex]::Replace($s, '[^\p{L}\p{Nd}]+', ' ')
  $s.Trim().ToLowerInvariant()
}

# Une question : enonce, propositions "- A) ...", "Reponse : X", "Explication : ..."
function ParseQcm([string[]]$lines) {
  $q = @{ stem = New-Object System.Collections.ArrayList; opts = New-Object System.Collections.ArrayList; answer = ''; expl = ''; label = ''; used = $false }
  $mode = 'stem'
  foreach ($l in $lines) {
    $t = $l.Trim()
    if ($mode -ne 'expl' -and $t -match '^[-*+]\s*\(?([A-Fa-f])\s*[).:]\s*(.*)$') {
      [void]$q.opts.Add(@{ k = $Matches[1].ToUpper(); text = $Matches[2] }); $mode = 'opts'; continue
    }
    if ($t -match '^\**\s*R.ponses?\s*\**\s*:\s*\**\s*\(?([A-Fa-f])\b') { $q.answer = $Matches[1].ToUpper(); $mode = 'ans'; continue }
    if ($t -match '^\**\s*Explications?\s*\**\s*:\s*\**\s*(.*)$') { $q.expl = $Matches[1]; $mode = 'expl'; continue }
    if ($mode -eq 'stem') { [void]$q.stem.Add($l) }
    elseif ($mode -eq 'expl' -and $t) { $q.expl += ' ' + $t }
  }
  $q.expl = $q.expl.Trim()
  if ($q.opts.Count -lt 2 -or -not $q.answer) { return $null }
  if (-not ($q.opts | Where-Object { $_.k -eq $q.answer })) { return $null }
  if (-not ($q.stem | Where-Object { $_.Trim() -ne '' })) { return $null }
  $q
}

function LoadQuiz([string]$path) {
  if (-not $path) { return $false }
  $f = P $path
  if (-not (Test-Path -LiteralPath $f)) { return $false }
  $entries = New-Object System.Collections.ArrayList
  $part = ''; $h2 = ''; $cur = $null; $inCode = $false
  foreach ($l in (Lines (ReadU $path))) {
    $t = $l.Trim()
    if ($t -match '^```') { $inCode = -not $inCode }
    if (-not $inCode) {
      if ($t -match '^#\s+(.+)$') {
        $k = NormKey $Matches[1]
        $part = if ($k -match 'quiz|qcm') { 'quiz' } elseif ($k -match 'vision') { 'rev' } else { '' }
        $h2 = ''; $cur = $null; continue
      }
      if ($t -match '^##\s+(.+)$') {
        $h2 = $Matches[1].Trim(); $cur = $null
        if ($part -eq 'quiz') { [void]$script:series.Add(@{ title = $h2; qs = New-Object System.Collections.ArrayList }) }
        continue
      }
      if ($t -match '^###\s+(.+)$') {
        if ($part -eq 'quiz' -and $script:series.Count -eq 0) { [void]$script:series.Add(@{ title = 'Quiz'; qs = New-Object System.Collections.ArrayList }) }
        $cur = @{ part = $part; h2 = $h2; h3 = $Matches[1].Trim(); lines = New-Object System.Collections.ArrayList; serie = $script:series.Count - 1 }
        [void]$entries.Add($cur); continue
      }
    }
    if ($cur) { [void]$cur.lines.Add($l) }
  }
  foreach ($e in $entries) {
    if (-not $e.part) { continue }
    if ($e.part -eq 'rev') { $script:hasRev = $true }
    $q = ParseQcm ([string[]]$e.lines.ToArray())
    if (-not $q) {
      $where = if ($e.part -eq 'rev') { 'Revision' } else { 'Quiz' }
      [void]$script:qBad.Add($where + ' > ' + $e.h2 + ' > ' + $e.h3); continue
    }
    if ($e.part -eq 'rev') {
      $q.h2 = $e.h2; $q.h3 = $e.h3
      $key = (NormKey $e.h2) + '|' + (NormKey $e.h3)
      if ($script:rev.ContainsKey($key)) { Write-Warning ('Revision : question en double pour ' + $e.h2 + ' > ' + $e.h3 + ' (seule la premiere est gardee)'); continue }
      $script:rev[$key] = $q
      $k3 = NormKey $e.h3
      if (-not $script:revByH3.ContainsKey($k3)) { $script:revByH3[$k3] = New-Object System.Collections.ArrayList }
      [void]$script:revByH3[$k3].Add($q)
      [void]$script:revAll.Add($q)
    } else {
      $label = $e.h3; $ix = $label.IndexOf($script:MID)
      if ($ix -ge 0) { $label = $label.Substring($ix + 1).Trim() }
      elseif ($label -match '^Q\s*\d+\s*[-:.)]\s*(.+)$') { $label = $Matches[1].Trim() }
      elseif ($label -match '^Q\s*\d+$') { $label = '' }
      $q.label = $label
      [void]$script:series[$e.serie].qs.Add($q)
    }
  }
  $true
}

# Carte QCM. $kind = 'rev' (fin de sous-theme, onglet Cours) ou 'quiz' (onglet Quiz).
function QcmHtml($q, [string]$kind, [string]$id, [int]$num) {
  $sb = New-Object System.Text.StringBuilder
  $stem = ConvertBlocks ([string[]]$q.stem.ToArray()) $false
  if ($kind -eq 'rev') {
    [void]$sb.Append('<div class="qcm rev" id="' + $id + '" data-answer="' + $q.answer + '">' + "`n")
    [void]$sb.Append('<div class="qcm-head"><span class="qcm-kicker">Question de r' + $script:E_ + 'vision</span><span class="qcm-res" aria-live="polite"></span></div>' + "`n")
  } else {
    $lab = 'Q' + $num
    if ($q.label) { $lab += ' ' + $script:MID + ' ' + [System.Net.WebUtility]::HtmlDecode([regex]::Replace((Inline $q.label), '<[^>]+>', '')) }
    [void]$sb.Append('<section class="sub qcm quiz" id="' + $id + '" data-answer="' + $q.answer + '" data-label="' + (EscA $lab) + '">' + "`n")
    $tag = if ($q.label) { '<span class="qcm-tag">' + (Inline $q.label) + '</span>' } else { '' }
    [void]$sb.Append('<h3 class="qcm-head"><span class="qcm-num">Q' + $num + '</span>' + $tag + '<span class="qcm-res" aria-live="polite"></span></h3>' + "`n")
  }
  [void]$sb.Append('<div class="qcm-q">' + "`n" + $stem + '</div>' + "`n" + '<div class="qcm-opts" role="radiogroup">' + "`n")
  foreach ($o in $q.opts) {
    [void]$sb.Append('<label class="opt" data-v="' + $o.k + '"><input type="radio" name="' + $id + '" value="' + $o.k + '" autocomplete="off"><span class="opt-k">' + $o.k + '</span><span class="opt-t">' + (Inline $o.text) + "</span></label>`n")
  }
  [void]$sb.Append("</div>`n")
  if ($kind -eq 'rev') {
    [void]$sb.Append('<div class="qcm-actions"><button type="button" class="btn-qcm primary qcm-validate" disabled>Valider</button></div>' + "`n")
    $ex = if ($q.expl) { ' ' + (Inline $q.expl) } else { '' }
    [void]$sb.Append('<div class="qcm-expl" hidden><b>R' + $script:E_ + 'ponse ' + $q.answer + '.</b>' + $ex + "</div>`n</div>`n")
  } else {
    [void]$sb.Append("</section>`n")
  }
  $sb.ToString()
}

# Petite question a la fin d'un sous-theme du cours (appelee a la fermeture de chaque section.sub)
# $quiet = chapitre 0 Lexique : pas de question attendue (ni avertissement, ni comptage), mais une question explicite est affichee.
function RevFor([string]$h2, [string]$h3, [string]$id, [bool]$quiet = $false) {
  if (-not $quiet) { $script:revStats.subs++ }
  if (-not $script:hasRev) { return '' }
  $q = $script:rev[(NormKey $h2) + '|' + (NormKey $h3)]
  if (-not $q -and -not $quiet) { $l = $script:revByH3[(NormKey $h3)]; if ($l -and $l.Count -eq 1) { $q = $l[0] } }
  if (-not $q -or $q.used) {
    if (-not $quiet) { Write-Warning ('Revision : aucune question pour le sous-theme ' + $h2 + ' > ' + $h3) }
    return ''
  }
  if ($quiet) { $script:revStats.subs++ }
  $q.used = $true; $script:revStats.hit++
  QcmHtml $q 'rev' $id 0
}

function QuizHtml() {
  $h = New-Object System.Text.StringBuilder
  $s = 0
  foreach ($se in $script:series) {
    if ($se.qs.Count -eq 0) { continue }
    $s++; $n = $se.qs.Count
    $plural = if ($n -gt 1) { 's' } else { '' }
    [void]$h.Append('<section class="theme quiz-serie" id="q-' + $s + '"><h2>' + (Inline $se.title) + "</h2>`n")
    [void]$h.Append('<p class="quiz-sub">' + $n + ' question' + $plural + ' ' + $script:MID + ' choisis une r' + $script:E_ + 'ponse par question, puis <b>Corriger</b>.</p>' + "`n")
    $rows = New-Object System.Text.StringBuilder
    for ($k = 0; $k -lt $n; $k++) {
      $q = $se.qs[$k]; $id = 'q-' + $s + '-' + ($k + 1)
      [void]$h.Append((QcmHtml $q 'quiz' $id ($k + 1)))
      $opt = $q.opts | Where-Object { $_.k -eq $q.answer } | Select-Object -First 1
      $qcell = '<a href="#' + $id + '">Q' + ($k + 1) + '</a>'
      if ($q.label) { $qcell += ' ' + $script:MID + ' ' + (Inline $q.label) }
      [void]$rows.Append('<tr data-for="' + $id + '"><td class="ans-q">' + $qcell + '</td><td class="ans-r"><b>' + $q.answer + ')</b> ' + (Inline $opt.text) + '</td><td>' + (Inline $q.expl) + "</td></tr>`n")
    }
    $lblEnd = 'Correction et r' + $script:E_ + 'ponses'
    [void]$h.Append('<section class="sub quiz-end" id="q-' + $s + '-fin" data-label="' + $lblEnd + '"><h3>' + $lblEnd + "</h3>`n")
    [void]$h.Append('<div class="quiz-bar"><button type="button" class="btn-qcm primary quiz-check">Corriger</button><button type="button" class="btn-qcm quiz-reset">Recommencer</button><span class="quiz-score" aria-live="polite"></span></div>' + "`n")
    [void]$h.Append('<button type="button" class="btn-ex btn-ans" aria-expanded="false">Afficher les r' + $script:E_ + 'ponses</button>' + "`n")
    [void]$h.Append('<div class="quiz-answers" hidden><table><thead><tr><th>Question</th><th>R' + $script:E_ + 'ponse</th><th>Explication</th></tr></thead><tbody>' + "`n" + $rows.ToString() + "</tbody></table></div>`n")
    [void]$h.Append("</section>`n</section>`n")
  }
  $h.ToString()
}

# ---------- Sigles : info-bulles ----------
$script:hasLex = $false
$script:lexRows = New-Object System.Collections.ArrayList   # lignes du tableau "### Sigles" du Lexique (repli)
$script:sigDef = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)   # sigle -> signification
$script:sigHits = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
$script:sigOrder = New-Object System.Collections.ArrayList
$script:sigRe = $null
$script:sigTotal = 0
# Elements dont le contenu ne recoit jamais d'info-bulle (+ td.sig-name, colonne Sigle du Lexique)
$script:sigSkip = @{ pre = 1; code = 1; kbd = 1; samp = 1; a = 1; h1 = 1; h2 = 1; abbr = 1; button = 1; script = 1; style = 1; textarea = 1; svg = 1; title = 1; select = 1 }

function Dec([string]$s) { [System.Net.WebUtility]::HtmlDecode($s) }

# Texte brut d'une cellule Markdown (sans balises, gras, code)
function CellText([string]$c) {
  $c = [regex]::Replace($c, '<[^>]+>', '')
  $c = $c.Replace('**', '').Replace('`', '')
  ([regex]::Replace($c, '\s+', ' ')).Trim()
}

# Charge les lignes "| Sigle | Signification |" (en-tete et separateur ignores). Sensible a la casse, premier gagnant.
function LoadSigles($rows) {
  foreach ($r in $rows) {
    $t = ([string]$r).Trim()
    if (-not $t.StartsWith('|')) { continue }
    if ($t -match '^\|?[\s:\-|]+\|?$') { continue }
    $cells = SplitRow $t
    if ($cells.Count -lt 2) { continue }
    $sg = CellText $cells[0]
    $df = CellText ((@($cells[1..($cells.Count - 1)]) | Where-Object { $_ -ne '' }) -join ' | ')
    if (-not $sg -or -not $df) { continue }
    if ((NormKey $sg) -match '^sigles?$') { continue }
    if ($script:sigDef.ContainsKey($sg)) { continue }
    $script:sigDef[$sg] = $df; $script:sigHits[$sg] = 0; [void]$script:sigOrder.Add($sg)
  }
  if ($script:sigOrder.Count -eq 0) { return }
  # Plus longs d'abord ; pluriel simple tolere (VMs -> VM) si le sigle finit par une majuscule ou un chiffre
  $alts = @($script:sigOrder | Sort-Object -Property @{ Expression = { $_.Length }; Descending = $true } | ForEach-Object {
    $e = [regex]::Escape((Esc $_))
    if ($_ -cmatch '[A-Z0-9]$') { $e + 's?' } else { $e }
  })
  $script:sigRe = New-Object System.Text.RegularExpressions.Regex ('(?<![\p{L}\p{Nd}_&#])(?:' + ($alts -join '|') + ')(?![\p{L}\p{Nd}_])')
}

# Enveloppe chaque sigle des noeuds texte d'un fragment HTML (balises et attributs jamais modifies).
function ApplySigles([string]$html) {
  if (-not $script:sigRe -or -not $html) { return $html }
  $parts = [regex]::Split($html, '(<!--[\s\S]*?-->|<[^>]+>)')
  $sb = New-Object System.Text.StringBuilder
  $skipTag = $null; $depth = 0
  $wrap = {
    param($m)
    $v = $m.Value; $base = $v
    if (-not $script:sigDef.ContainsKey((Dec $v))) { $base = $v.Substring(0, $v.Length - 1) }
    $key = Dec $base
    $script:sigHits[$key]++; $script:sigTotal++
    $ds = if ($base -ne $v) { ' data-sig="' + (EscA $key) + '"' } else { '' }
    '<abbr class="sig" title="' + (EscA $script:sigDef[$key]) + '"' + $ds + '>' + $v + '</abbr>'
  }
  foreach ($p in $parts) {
    if ($p.Length -eq 0) { continue }
    if ($p[0] -eq '<') {
      [void]$sb.Append($p)
      if ($p -match '^<(/?)([A-Za-z][\w-]*)') {
        $close = $Matches[1] -eq '/'; $name = $Matches[2].ToLower()
        if ($skipTag) {
          if ($name -eq $skipTag) { if ($close) { $depth--; if ($depth -eq 0) { $skipTag = $null } } elseif (-not $p.EndsWith('/>')) { $depth++ } }
        } elseif (-not $close -and -not $p.EndsWith('/>')) {
          if ($script:sigSkip.ContainsKey($name) -or ($name -eq 'td' -and $p -match 'class="[^"]*\bsig-name\b')) { $skipTag = $name; $depth = 1 }
        }
      }
      continue
    }
    if ($skipTag) { [void]$sb.Append($p); continue }
    [void]$sb.Append($script:sigRe.Replace($p, [System.Text.RegularExpressions.MatchEvaluator]$wrap))
  }
  $sb.ToString()
}

# ---------- Evaluation ----------
function EvalHtml([string]$md, [string]$noteOverride) {
  $sec = [ordered]@{}; $cur = $null
  foreach ($l in (Lines $md)) {
    if ($l -match '^#{1,2}\s+(.+?)\s*$') { $cur = $Matches[1]; $sec[$cur] = New-Object System.Collections.ArrayList }
    elseif ($cur) { [void]$sec[$cur].Add($l) }
  }
  function Find($re) { foreach ($k in $sec.Keys) { if ($k -match $re) { return ,@($k, $sec[$k]) } } return $null }
  $note = $noteOverride
  $kn = Find '^Note'
  if (-not $note -and $kn -and $kn[0] -match '(\d+(?:[,.]\d+)?)\s*/\s*20') { $note = $Matches[1] }
  $msg = ''; $x = Find 'Message'; if ($x) { $msg = ConvertBlocks ([string[]]$x[1].ToArray()) $false }
  $grille = ''; $x = Find 'Grille'; if ($x) { $grille = ConvertBlocks ([string[]]$x[1].ToArray()) $false }
  $forts = ''; $x = Find 'forts'; if ($x) { $forts = ConvertBlocks ([string[]]$x[1].ToArray()) $false }
  $ameli = ''; $x = Find 'am.liorer'; if ($x) { $ameli = ConvertBlocks ([string[]]$x[1].ToArray()) $false }
  $err = ''; $x = Find 'Erreurs'; if ($x) { $err = ConvertBlocks ([string[]]$x[1].ToArray()) $false }
  $taux = ''; $x = Find '^Taux'; if ($x) {
    $taux = ConvertBlocks ([string[]]$x[1].ToArray()) $false
    # Barre de progression dans les cellules de pourcentage
    $taux = [regex]::Replace($taux, '<td>(\d{1,3})\s*%</td>', { param($m) $v = [Math]::Min(100, [int]$m.Groups[1].Value); '<td class="pct">' + $v + ' %<div class="bar"><i style="width:' + $v + '%"></i></div></td>' })
  }
  $plus = ''; $x = Find 'loin'; if ($x) { $plus = ConvertBlocks ([string[]]$x[1].ToArray()) $false }
  $tEval = [regex]::Unescape('\u00c9valuation')
  $tPF = [regex]::Unescape('Points forts et \u00e0 am\u00e9liorer')
  $tAm = [regex]::Unescape('\u00c0 am\u00e9liorer')
  $h = New-Object System.Text.StringBuilder
  [void]$h.Append("<section class=`"theme`" id=`"e-1`"><h2>$tEval</h2>`n")
  [void]$h.Append("<section class=`"sub`" id=`"e-1-1`"><h3>Note globale</h3>`n<div class=`"eval-head`">`n<div class=`"score`"><div><b>$note</b><small>sur 20</small></div></div>`n<div>$msg</div>`n</div>`n</section>`n")
  [void]$h.Append("<section class=`"sub`" id=`"e-1-2`"><h3>Grille</h3>`n$grille</section>`n")
  if ($taux) { [void]$h.Append("<section class=`"sub`" id=`"e-1-5`"><h3>Taux par chapitre</h3>`n$taux</section>`n") }
  [void]$h.Append("<section class=`"sub`" id=`"e-1-3`"><h3>$tPF</h3>`n<div class=`"cards-2`">`n<div class=`"card good`"><h2>Points forts</h2>`n$forts</div>`n<div class=`"card bad`"><h2>$tAm</h2>`n$ameli</div>`n</div>`n</section>`n")
  [void]$h.Append("<section class=`"sub`" id=`"e-1-4`"><h3>Erreurs relev$([char]0xE9)es</h3>`n$err</section>`n")
  [void]$h.Append("</section>`n")
  [void]$h.Append("<section class=`"theme`" id=`"plus-loin`"><h2>Pour aller plus loin</h2>`n<section class=`"sub`" id=`"e-2-1`"><h3>Pistes</h3>`n$plus</section>`n</section>`n")
  $h.ToString()
}

# ---------- Assemblage ----------
$tpl = ReadU $Template
$titre = (ReadU $TitreFile).Trim()
$hasQuizFile = LoadQuiz $QuizFile
$coursHtml = ConvertBlocks (Lines (ReadU $Cours)) $true
$quizHtml = QuizHtml
# Sigles : 02_sigles.md, sinon tableau du "### Sigles" du Lexique, sinon rien
$sigSrc = ''
if ($SiglesFile -and (Test-Path -LiteralPath (P $SiglesFile))) { LoadSigles (Lines (ReadU $SiglesFile)); $sigSrc = (Split-Path (P $SiglesFile) -Leaf) }
if ($script:sigOrder.Count -eq 0 -and $script:lexRows.Count -gt 0) { LoadSigles $script:lexRows; $sigSrc = 'Lexique > Sigles' }
$nQuiz = 0; $serieCounts = @()
foreach ($se in $script:series) { if ($se.qs.Count) { $nQuiz += $se.qs.Count; $serieCounts += $se.qs.Count } }
$nThemes = [regex]::Matches($coursHtml, '<section class="theme"').Count
$evalMd = ReadU $Eval
$evalHtml = EvalHtml $evalMd $Note
$coursHtml = ApplySigles $coursHtml
$evalHtml = ApplySigles $evalHtml
if (-not $Note -and $evalMd -match 'Note\s*:\s*(\d+(?:[,.]\d+)?)\s*/\s*20') { $Note = $Matches[1] }

function ReplaceBlock([string]$s, [string]$name, [string]$html) {
  $re = '<!-- ' + $name + ':DEBUT.*?-->.*?<!-- ' + $name + ':FIN\s*-->'
  if (-not [regex]::IsMatch($s, $re, 'Singleline')) { throw "Marqueurs $name introuvables" }
  [regex]::Replace($s, $re, { param($m) $html }, 'Singleline')
}
$result = ReplaceBlock $tpl 'CONTENU-COURS' $coursHtml
$result = ReplaceBlock $result 'CONTENU-EVAL' $evalHtml
if ($nQuiz -gt 0) {
  $result = ReplaceBlock $result 'CONTENU-QUIZ' (ApplySigles $quizHtml)
  $result = [regex]::Replace($result, '<!-- (?:PAGE-QUIZ|QUIZ-TAB):(?:DEBUT|FIN)[^>]*-->\r?\n?', '')
} else {
  # Pas de quiz : ni onglet ni page Quiz
  $result = ReplaceBlock $result 'QUIZ-TAB' ''
  $result = ReplaceBlock $result 'PAGE-QUIZ' ''
}
$sPl = if ($serieCounts.Count -gt 1) { 's' } else { '' }
$resume = [string]$nQuiz + ' questions en ' + $serieCounts.Count + ' s' + [char]0xE9 + 'rie' + $sPl
$result = $result.Replace('{{TITRE_ATTR}}', (EscA $titre)).Replace('{{NOTE_ATTR}}', (EscA $Note)).Replace('{{DATE_ATTR}}', (EscA $Date))
$result = $result.Replace('{{META_THEMES}}', [string]$nThemes).Replace('{{META_QUIZ}}', [string]$nQuiz).Replace('{{META_REVISION}}', [string]$script:revStats.hit).Replace('{{META_SIGLES}}', [string]$script:sigOrder.Count)
$result = $result.Replace('{{QUIZ_RESUME}}', $resume)
$result = $result.Replace('{{TITRE}}', (Esc $titre)).Replace('{{DATE}}', $Date).Replace('{{NOTE}}', $Note)

# Bilan quiz / revision
if ($script:qBad.Count) {
  Write-Warning ([string]$script:qBad.Count + ' question(s) ignoree(s), format QCM attendu (enonce, - A) ... - D), Reponse : X, Explication : ...) :')
  foreach ($b in $script:qBad) { Write-Warning ('  ' + $b) }
}
foreach ($q in $script:revAll) { if (-not $q.used) { Write-Warning ('Revision : question sans sous-theme correspondant dans le cours : ' + $q.h2 + ' > ' + $q.h3) } }
$detail = if ($serieCounts.Count) { ' (' + ($serieCounts -join ' + ') + ')' } elseif (-not $hasQuizFile) { ' (fichier quiz absent)' } else { '' }
if ($script:sigOrder.Count) {
  $miss = @($script:sigOrder | Where-Object { $script:sigHits[$_] -eq 0 })
  $mtxt = if ($miss.Count) { ' ; jamais trouves (' + $miss.Count + ') : ' + ($miss -join ', ') } else { ' ; tous trouves' }
  Write-Host ('Sigles : ' + $script:sigOrder.Count + ' charges (' + $sigSrc + '), ' + $script:sigTotal + ' occurrences avec info-bulle' + $mtxt)
} else { Write-Host 'Sigles : aucun (ni fichier de sigles, ni tableau Lexique > Sigles)' }
$lexTxt = if ($script:hasLex) { ' (hors chapitre 0 Lexique)' } else { '' }
Write-Host ('Revision : ' + $script:revStats.hit + ' / ' + $script:revStats.subs + ' sous-themes' + $lexTxt + ' ; quiz : ' + $nQuiz + ' questions en ' + $serieCounts.Count + ' serie(s)' + $detail)

if (-not $Out) { $Out = 'output\COURS_CORRECTION_IA_' + (Get-Date -Format 'ddMMyyyy_HHmm') + '.html' }
$dest = P $Out
New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
[IO.File]::WriteAllText($dest, $result, $utf8)
Write-Output $dest
