# md2html.ps1 - Convertit work/03_organise.md et work/02_evaluation.md en HTML autonome a partir du gabarit.
# Usage : powershell -ExecutionPolicy Bypass -File scripts\md2html.ps1 -Date "05/11/2026" -Note "14,5" [-Out output\COURS_CORRECTION_IA_DDMMYYYY_HHMM.html]
# Fichier ASCII uniquement (compatible Windows PowerShell 5.1).
param(
  [string]$Root = (Split-Path $PSScriptRoot -Parent),
  [string]$Template = 'template\cours_template.html',
  [string]$Cours = 'work\03_organise.md',
  [string]$Eval = 'work\02_evaluation.md',
  [string]$TitreFile = 'work\03_titre.txt',
  [string]$QuizFile = 'work\04_quiz.md',
  [string]$Date = (Get-Date -Format 'dd/MM/yyyy'),
  [string]$Note = '',
  [string]$Out = ''
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function P($p) { if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $Root $p } }
function ReadU($p) { [IO.File]::ReadAllText((P $p), $utf8) }

$script:imgBase = Split-Path (P $Cours) -Parent
$script:codes = New-Object System.Collections.ArrayList
$script:links = New-Object System.Collections.ArrayList
$script:rev = @{}                                       # cle "h2|h3" (et "|h3") -> @(question, reponse)
$script:revUsed = 0
$script:revMissing = New-Object System.Collections.ArrayList
$script:nbSubs = 0

# Normalise un titre pour l'appariement revision <-> cours (sans balises, numero, casse ni espaces multiples)
function Norm([string]$s) {
  $s = [regex]::Replace($s, '<[^>]+>', '')
  $s = [regex]::Replace($s, '[*`]', '')
  $s = [regex]::Replace($s, '^\s*\d+[.)]?\s+', '')
  ([regex]::Replace($s, '\s+', ' ')).Trim().ToLower()
}

function Esc([string]$s) {
  $s = $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
  $s
}

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

function TableHtml($rows) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("<table>`n")
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
    foreach ($c in (SplitRow $rows[$i])) { [void]$sb.Append('<td>' + (Inline $c) + '</td>') }
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
  [void]$sb.Append('<div class="concept"><div class="concept-title">' + (Inline $name.Trim()) + "</div>`n")
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
  $state = @{ theme = 0; sub = 0; inTheme = $false; inSub = $false; h2 = ''; h3 = '' }
  $flush = {
    if ($para.Count -gt 0) {
      $txt = ($para | ForEach-Object { Inline $_ }) -join "<br>`n"
      [void]$sb.Append("<p>$txt</p>`n"); $para.Clear()
    }
  }
  # Fermeture d'un sous-theme : question de revision eventuelle, puis </section>
  $closeSub = {
    if ($state.inSub) {
      [void]$sb.Append((RevHtml $state.h2 $state.h3))
      [void]$sb.Append("</section>`n"); $state.inSub = $false
    }
  }
  $i = 0
  while ($i -lt $lines.Count) {
    $l = $lines[$i]; $t = $l.Trim()
    if ($t -eq '') { & $flush; $i++; continue }
    if ($top -and $t -match '^# [^#]') { & $flush; $i++; continue }
    if ($top -and $t -match '^## (.+)$') {
      & $flush
      $h2 = $Matches[1]
      & $closeSub
      if ($state.inTheme) { [void]$sb.Append("</section>`n") }
      $state.theme++; $state.sub = 0; $state.inTheme = $true; $state.h2 = $h2
      [void]$sb.Append('<section class="theme" id="t-' + $state.theme + '"><h2>' + (Inline $h2) + "</h2>`n")
      $i++; continue
    }
    if ($top -and $t -match '^### (.+)$') {
      & $flush
      $h3 = $Matches[1]
      & $closeSub
      $state.sub++; $state.inSub = $true; $state.h3 = $h3; $script:nbSubs++
      [void]$sb.Append('<section class="sub" id="t-' + $state.theme + '-' + $state.sub + '"><h3>' + (Inline $h3) + "</h3>`n")
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
      [void]$sb.Append((TableHtml $rows))
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

# ---------- Questions de revision et quiz (work/04_quiz.md) ----------
function RevHtml([string]$h2, [string]$h3) {
  if ($script:rev.Count -eq 0) { return '' }
  $k = (Norm $h2) + '|' + (Norm $h3)
  $qa = $null
  if ($script:rev.ContainsKey($k)) { $qa = $script:rev[$k] }
  elseif ($script:rev.ContainsKey('|' + (Norm $h3))) { $qa = $script:rev['|' + (Norm $h3)] }
  if (-not $qa) { [void]$script:revMissing.Add("$h2 > $h3"); return '' }
  $script:revUsed++
  $lbl = 'Question de r' + [char]0xE9 + 'vision'
  '<div class="revq"><div class="revq-head">' + $lbl + '</div><div class="revq-q">' + (Inline $qa[0]) + '</div>' +
  '<button type="button" class="btn-ex" aria-expanded="false">Voir la r' + [char]0xE9 + 'ponse</button><div class="revq-r" hidden>' + (Inline $qa[1]) + "</div></div>`n"
}

# Lit 04_quiz.md : remplit $script:rev et renvoie la liste des series du quiz
function ParseQuiz([string]$md) {
  $series = New-Object System.Collections.ArrayList
  $part = ''; $h2 = ''; $h3 = ''; $last = $null; $serie = $null; $q = $null; $h3Count = @{}
  foreach ($l in (Lines $md)) {
    $t = $l.Trim()
    if ($t -match '^#\s+(.+)$') { $part = if ($Matches[1] -match '^Quiz') { 'quiz' } else { 'rev' }; continue }
    if ($part -eq 'rev') {
      if ($t -match '^##\s+(.+)$' -and $t -notmatch '^###') { $h2 = $Matches[1]; continue }
      if ($t -match '^###\s+(.+)$') { $h3 = $Matches[1]; continue }
      if ($t -match '^Q\s*:\s*(.*)$') {
        $last = @($Matches[1], '')
        $script:rev[(Norm $h2) + '|' + (Norm $h3)] = $last
        $n3 = Norm $h3; $h3Count[$n3] = 1 + [int]$h3Count[$n3]
        if ($h3Count[$n3] -eq 1) { $script:rev['|' + $n3] = $last } else { $script:rev.Remove('|' + $n3) }
        continue
      }
      if ($t -match '^R\s*:\s*(.*)$' -and $last) { $last[1] = $Matches[1]; continue }
      if ($t -ne '' -and $last) { if ($last[1]) { $last[1] += ' ' + $t } else { $last[0] += ' ' + $t } }
      continue
    }
    if ($part -eq 'quiz') {
      if ($t -match '^##\s+(.+)$' -and $t -notmatch '^###') {
        $serie = @{ name = $Matches[1]; qs = (New-Object System.Collections.ArrayList) }; [void]$series.Add($serie); $q = $null; continue
      }
      if ($t -match '^###\s+Q(\d+)\s*(.*)$') {
        if (-not $serie) { $serie = @{ name = 'QCM 1'; qs = (New-Object System.Collections.ArrayList) }; [void]$series.Add($serie) }
        $tag = [regex]::Replace($Matches[2], ('^[\s' + [char]0xB7 + ':|.\-]+'), '')
        $q = @{ num = $Matches[1]; tag = $tag; text = (New-Object System.Collections.ArrayList); choices = (New-Object System.Collections.ArrayList); answer = ''; expl = '' }
        [void]$serie.qs.Add($q); continue
      }
      if (-not $q) { continue }
      if ($t -match '^[-*]\s*([A-F])\s*[).:]\s*(.*)$') { [void]$q.choices.Add(@($Matches[1], $Matches[2])); continue }
      if ($t -match '^R.ponse\s*:\s*\**([A-F])') { $q.answer = $Matches[1]; continue }
      if ($t -match '^Explication\s*:\s*(.*)$') { $q.expl = $Matches[1]; continue }
      if ($t -ne '' -and $q.choices.Count -eq 0) { [void]$q.text.Add($l) }
    }
  }
  , $series
}

function QuizHtml($series) {
  $sb = New-Object System.Text.StringBuilder
  $s = 0
  foreach ($serie in $series) {
    $s++; $n = $serie.qs.Count
    [void]$sb.Append('<section class="theme quiz-serie" id="q-' + $s + '"><h2>' + (Inline $serie.name) + "</h2>`n")
    [void]$sb.Append('<p class="quiz-intro">' + $n + ' questions ' + [char]0xB7 + ' une seule bonne r' + [char]0xE9 + "ponse par question</p>`n")
    [void]$sb.Append('<section class="sub" id="q-' + $s + '-1"><h3>Questions</h3>' + "`n")
    $rows = New-Object System.Text.StringBuilder
    foreach ($q in $serie.qs) {
      if (-not $q.answer) { throw "Quiz : reponse manquante pour $($serie.name) Q$($q.num)" }
      if ($q.choices.Count -lt 2) { throw "Quiz : propositions manquantes pour $($serie.name) Q$($q.num)" }
      $name = 'q-' + $s + '-' + $q.num
      [void]$sb.Append('<div class="qcm" id="' + $name + '" data-answer="' + $q.answer + '"><div class="qcm-head"><span class="qcm-num">Q' + $q.num + '</span><span class="qcm-tag">' + (Inline $q.tag) + "</span></div>`n")
      [void]$sb.Append('<div class="qcm-text">' + (ConvertBlocks ([string[]]$q.text.ToArray()) $false) + "</div>`n<div class=`"qcm-choices`">`n")
      foreach ($c in $q.choices) {
        [void]$sb.Append('<label class="choice"><input type="radio" name="' + $name + '" value="' + $c[0] + '"><b>' + $c[0] + '</b><span>' + (Inline $c[1]) + "</span></label>`n")
      }
      [void]$sb.Append("</div></div>`n")
      [void]$rows.Append('<tr><td>Q' + $q.num + '</td><td>' + $q.answer + '</td><td>' + (Inline $q.expl) + "</td></tr>`n")
    }
    [void]$sb.Append('<div class="quiz-actions"><button type="button" class="btn-quiz" data-act="check">Corriger</button><button type="button" class="btn-quiz ghost" data-act="reset">Recommencer</button><span class="quiz-score"></span></div>' + "`n</section>`n")
    [void]$sb.Append('<section class="sub" id="q-' + $s + '-2"><h3>R' + [char]0xE9 + "ponses</h3>`n")
    [void]$sb.Append('<button type="button" class="btn-ex btn-ans" aria-expanded="false">Afficher les r' + [char]0xE9 + "ponses</button>`n")
    [void]$sb.Append('<div class="quiz-answers" hidden><table><thead><tr><th>Question</th><th>R' + [char]0xE9 + "ponse</th><th>Explication</th></tr></thead>`n<tbody>" + $rows.ToString() + "</tbody></table></div>`n</section>`n</section>`n")
  }
  $sb.ToString()
}

function Lines([string]$s) { [string[]]($s -split "`r?`n") }

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
$series = @()
if ($QuizFile -and (Test-Path (P $QuizFile))) { $series = ParseQuiz (ReadU $QuizFile) }
else { Write-Warning "Pas de quiz ($QuizFile) : onglet Quiz masque, pas de questions de revision." }
$coursHtml = ConvertBlocks (Lines (ReadU $Cours)) $true
$nbThemes = ([regex]::Matches($coursHtml, '<section class="theme"')).Count
$nbQuiz = 0; foreach ($se in $series) { $nbQuiz += $se.qs.Count }
$quizHtml = QuizHtml $series
if ($script:rev.Count -gt 0) {
  Write-Output ("Revision : $($script:revUsed) / $($script:nbSubs) sous-themes ; quiz : $nbQuiz questions en $($series.Count) serie(s) (" + (($series | ForEach-Object { $_.qs.Count }) -join ' + ') + ')')
  foreach ($m in $script:revMissing) { Write-Warning "Sans question de revision : $m" }
}
$evalMd = ReadU $Eval
$evalHtml = EvalHtml $evalMd $Note
if (-not $Note -and $evalMd -match 'Note\s*:\s*(\d+(?:[,.]\d+)?)\s*/\s*20') { $Note = $Matches[1] }

function ReplaceBlock([string]$s, [string]$name, [string]$html) {
  $re = '<!-- ' + $name + ':DEBUT.*?-->.*?<!-- ' + $name + ':FIN\s*-->'
  if (-not [regex]::IsMatch($s, $re, 'Singleline')) { throw "Marqueurs $name introuvables" }
  [regex]::Replace($s, $re, { param($m) $html }, 'Singleline')
}
$result = ReplaceBlock $tpl 'CONTENU-COURS' $coursHtml
$result = ReplaceBlock $result 'CONTENU-QUIZ' $quizHtml
$result = ReplaceBlock $result 'CONTENU-EVAL' $evalHtml
$result = $result.Replace('{{TITRE}}', (Esc $titre)).Replace('{{DATE}}', $Date).Replace('{{NOTE}}', $Note)
$result = $result.Replace('{{NB_THEMES}}', "$nbThemes").Replace('{{NB_QUIZ}}', "$nbQuiz")

if (-not $Out) { $Out = 'output\COURS_CORRECTION_IA_' + (Get-Date -Format 'ddMMyyyy_HHmm') + '.html' }
$dest = P $Out
New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
[IO.File]::WriteAllText($dest, $result, $utf8)
Write-Output $dest
