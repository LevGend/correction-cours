# video.ps1 - Genere une video explicative MP4 1920x1080 a partir de work/05_video.md
# Diapos : gabarit template/video_slide.html rendu par Chrome/Edge headless (PNG)
# Voix   : System.Speech (Microsoft Hortense Desktop, repli fr-FR), table "## Prononciation"
# Sous-titres : SRT genere depuis les narrations, incruste par ffmpeg (libass)
# PowerShell 5.1 - fichier ASCII uniquement (accents via [char]0x..)
param(
  [string]$In = "work\05_video.md",
  [string]$Out = "",
  [string]$Temp = "work\video_tmp",
  [int]$Rate = -1,              # debit de la voix (-10..10), -1 = legerement ralenti
  [double]$Pause = 0.6,         # pause apres la voix (s)
  [double]$Lead = 0.35,         # silence avant la voix (s), couvre le fondu d'entree
  [double]$Fade = 0.25          # duree des fondus au noir (s)
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$inv = [Globalization.CultureInfo]::InvariantCulture
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Fail($msg) { Write-Host ("ERREUR : " + $msg) -ForegroundColor Red; exit 1 }
function Resolve-Rel($p) { if ([IO.Path]::IsPathRooted($p)) { return $p } return (Join-Path $root $p) }
function F($d) { return $d.ToString("0.000", $inv) }

# ---------- Chemins ----------
$In = Resolve-Rel $In
if (-not (Test-Path -LiteralPath $In)) { Fail "fichier d'entree introuvable : $In" }
$In = (Resolve-Path -LiteralPath $In).Path
$inDir = Split-Path -Parent $In
if (-not $Out) { $Out = "output\VIDEO_COURS_" + (Get-Date -Format "ddMMyyyy_HHmm") + ".mp4" }
$Out = Resolve-Rel $Out
$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$Temp = Resolve-Rel $Temp
if (-not (Test-Path -LiteralPath $Temp)) { New-Item -ItemType Directory -Path $Temp | Out-Null }
$Temp = (Resolve-Path -LiteralPath $Temp).Path
$tplPath = Join-Path $root "template\video_slide.html"
if (-not (Test-Path -LiteralPath $tplPath)) { Fail "gabarit introuvable : $tplPath" }

# ---------- Outils ----------
$ffmpeg = $null
$cand = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\ffmpeg.exe"
if (Test-Path -LiteralPath $cand) { $ffmpeg = $cand }
else { $c = Get-Command ffmpeg -ErrorAction SilentlyContinue; if ($c) { $ffmpeg = $c.Source } }
if (-not $ffmpeg) { Fail "ffmpeg introuvable (ni $cand, ni dans le PATH). Installer : winget install Gyan.FFmpeg" }

$browser = $null
foreach ($b in @("C:\Program Files\Google\Chrome\Application\chrome.exe",
                 "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
                 "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                 "C:\Program Files\Microsoft\Edge\Application\msedge.exe")) {
  if (Test-Path -LiteralPath $b) { $browser = $b; break }
}
if (-not $browser) { Fail "navigateur introuvable : ni Chrome ni Edge (necessaire pour rendre les diapos)" }

Add-Type -AssemblyName System.Speech
Add-Type -AssemblyName System.Drawing
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voices = @($synth.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $_.VoiceInfo })
$voice = $voices | Where-Object { $_.Name -eq "Microsoft Hortense Desktop" } | Select-Object -First 1
if (-not $voice) { $voice = $voices | Where-Object { $_.Culture.Name -eq "fr-FR" } | Select-Object -First 1 }
if (-not $voice) { Fail "aucune voix francaise (fr-FR) installee pour System.Speech (Parametres > Heure et langue > Voix : ajouter Francais)" }
$synth.SelectVoice($voice.Name)
$synth.Rate = $Rate

# ---------- Lecture du Markdown ----------
$lines = [IO.File]::ReadAllText($In, [Text.Encoding]::UTF8) -replace "`r", "" -split "`n"
$videoTitle = ""
$slides = New-Object System.Collections.ArrayList
$pron = @{}
$cur = $null; $inPron = $false; $inNarr = $false
foreach ($raw in $lines) {
  $l = $raw.TrimEnd()
  if ($l -match '^#\s+Vid(e|\u00e9|\u00c9)o\s*:\s*(.+)$') { $videoTitle = $Matches[2].Trim(); continue }
  if ($l -match '^##\s+Diapo\s+(\d+)\s*(?:[\u00b7:.\-\u2013\u2014|]\s*)?(.*)$') {
    $cur = [ordered]@{ Num = [int]$Matches[1]; Title = $Matches[2].Trim(); Image = ""; Points = New-Object System.Collections.ArrayList; Narr = "" }
    [void]$slides.Add($cur); $inPron = $false; $inNarr = $false; continue
  }
  if ($l -match '^##\s+Prononciation') { $cur = $null; $inPron = $true; $inNarr = $false; continue }
  if ($l -match '^##\s') { $cur = $null; $inPron = $false; $inNarr = $false; continue }
  if ($inPron) {
    if ($l -match '^\s*\|(.+)\|\s*$') {
      $cells = $Matches[1] -split '\|' | ForEach-Object { $_.Trim() }
      if ($cells.Count -ge 2 -and $cells[0] -notmatch '^:?-{2,}:?$' -and $cells[0] -notmatch '^(.crit|Ecrit)$' -and $cells[0] -ne '') {
        $pron[$cells[0]] = $cells[1]
      }
    }
    continue
  }
  if ($null -eq $cur) { continue }
  if ($l -match '^Image\s*:\s*(.+)$') { $cur.Image = $Matches[1].Trim(); $inNarr = $false; continue }
  if ($l -match '^\s*[-*]\s+(.+)$') { [void]$cur.Points.Add($Matches[1].Trim()); $inNarr = $false; continue }
  if ($l -match '^Narration\s*:\s*(.*)$') { $cur.Narr = $Matches[1].Trim(); $inNarr = $true; continue }
  if ($inNarr -and $l.Trim() -ne '') { $cur.Narr = ($cur.Narr + " " + $l.Trim()).Trim(); continue }
  if ($l.Trim() -eq '') { $inNarr = $false }
}
if ($slides.Count -eq 0) { Fail "aucune diapo trouvee (titres attendus : '## Diapo 1 $([char]0xB7) Titre')" }
if (-not $videoTitle) { $videoTitle = $slides[0].Title }

# Images : verification avant tout rendu
foreach ($s in $slides) {
  if ($s.Image) {
    $p = $s.Image; if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $inDir $p }
    if (-not (Test-Path -LiteralPath $p)) { Fail ("diapo " + $s.Num + " : image introuvable : " + $s.Image + " (cherchee dans " + $inDir + ")") }
    $s.ImagePath = (Resolve-Path -LiteralPath $p).Path
  }
}

# ---------- Utilitaires texte ----------
function HtmlEsc($t) { return ($t -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;') }
function Inline($t) {
  # Markdown en ligne : `code`, **gras**, *italique*
  $parts = [regex]::Split($t, '(`[^`]+`)')
  $sb = New-Object System.Text.StringBuilder
  foreach ($p in $parts) {
    if ($p -match '^`([^`]+)`$') { [void]$sb.Append('<code>' + (HtmlEsc $Matches[1]) + '</code>') }
    else {
      $h = HtmlEsc $p
      $h = [regex]::Replace($h, '\*\*(.+?)\*\*', '<strong>$1</strong>')
      $h = [regex]::Replace($h, '(?<![\*\w])\*(?!\s)(.+?)(?<!\s)\*(?![\*\w])', '<em>$1</em>')
      [void]$sb.Append($h)
    }
  }
  return $sb.ToString()
}
function Plain($t) { return ($t -replace '\*\*(.+?)\*\*', '$1' -replace '`([^`]+)`', '$1').Trim() }

# Prononciation : mot entier, sensible a la casse, plus longs d'abord, une seule passe
$pronRx = $null
if ($pron.Count -gt 0) {
  $keys = @($pron.Keys | Sort-Object -Property @{Expression = { $_.Length }; Descending = $true })
  $alt = ($keys | ForEach-Object { [regex]::Escape($_) }) -join '|'
  $pronRx = New-Object System.Text.RegularExpressions.Regex ('(?<![\w])(' + $alt + ')(?![\w])')
}
function Spoken($t) {
  $t = Plain $t
  if ($pronRx) { $t = $pronRx.Replace($t, { param($m) $pron[$m.Value] }) }
  return $t
}

function WavDuration($path) {
  $fs = [IO.File]::OpenRead($path)
  try {
    $br = New-Object IO.BinaryReader($fs)
    $fs.Position = 12; $byteRate = 0; $dataLen = 0
    while ($fs.Position -lt $fs.Length - 8) {
      $id = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4)); $len = $br.ReadUInt32()
      if ($id -eq 'fmt ') { $start = $fs.Position; $fs.Position = $start + 8; $byteRate = $br.ReadUInt32(); $fs.Position = $start + $len }
      elseif ($id -eq 'data') { $dataLen = $len; break }
      else { $fs.Position += $len }
    }
    if ($byteRate -eq 0) { return 0 }
    return [double]$dataLen / $byteRate
  } finally { $fs.Close() }
}

# Decoupe en segments de sous-titres (2 lignes de ~42 caracteres max)
function SplitSubs($text, [int]$max = 84) {
  $res = New-Object System.Collections.ArrayList
  $sentences = [regex]::Split($text.Trim(), '(?<=[\.\!\?\u2026;:])\s+') | Where-Object { $_.Trim() -ne '' }
  foreach ($s in $sentences) {
    $s = $s.Trim()
    if ($s.Length -le $max) { [void]$res.Add($s); continue }
    # Trop long : couper aux virgules, puis aux mots
    $chunks = [regex]::Split($s, '(?<=,)\s+')
    $buf = ""
    foreach ($c in $chunks) {
      if ($buf -and ($buf.Length + 1 + $c.Length) -le $max) { $buf = $buf + " " + $c; continue }
      if ($buf) { [void]$res.Add($buf); $buf = "" }
      if ($c.Length -le $max) { $buf = $c; continue }
      $n = [math]::Ceiling($c.Length / [double]$max)
      $target = [math]::Ceiling($c.Length / [double]$n)
      $w = ""
      foreach ($word in ($c -split '\s+')) {
        if ($w -and ($w.Length + 1 + $word.Length) -gt $target -and $w.Length -ge ($target * 0.6)) { [void]$res.Add($w); $w = $word }
        elseif ($w) { $w = $w + " " + $word } else { $w = $word }
      }
      $buf = $w
    }
    if ($buf) { [void]$res.Add($buf) }
  }
  return , $res
}
# Coupe un segment en 2 lignes equilibrees
function TwoLines($s, [int]$line = 42) {
  if ($s.Length -le $line) { return $s }
  $mid = [math]::Floor($s.Length / 2); $best = -1
  for ($d = 0; $d -lt $mid; $d++) {
    if ($mid + $d -lt $s.Length -and $s[$mid + $d] -eq ' ') { $best = $mid + $d; break }
    if ($mid - $d -gt 0 -and $s[$mid - $d] -eq ' ') { $best = $mid - $d; break }
  }
  if ($best -lt 0) { return $s }
  return $s.Substring(0, $best) + "`n" + $s.Substring($best + 1)
}
function SrtTime([double]$t) {
  $ts = [TimeSpan]::FromMilliseconds([math]::Round($t * 1000))
  return ("{0:00}:{1:00}:{2:00},{3:000}" -f [math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds, $ts.Milliseconds)
}

# ---------- 1. Diapos (PNG) ----------
$tpl = [IO.File]::ReadAllText($tplPath, [Text.Encoding]::UTF8)
$total = $slides.Count
$chromeProfile = Join-Path $Temp "chrome_profile"
Write-Host ("Diapos : " + $total + " (navigateur : " + (Split-Path -Leaf $browser) + ", voix : " + $voice.Name + ")")
for ($i = 0; $i -lt $total; $i++) {
  $s = $slides[$i]; $n = $i + 1; $tag = "{0:00}" -f $n
  $classes = @()
  if ($n -eq 1) {
    $classes += "title-slide"
    $head = '<div class="kicker">' + (HtmlEsc ("Vid" + [char]0xE9 + "o explicative")) + '</div><h1>' + (Inline $videoTitle) + '</h1>'
    if ($s.Title -and $s.Title -ne $videoTitle) { $head += '<div class="sub">' + (Inline $s.Title) + '</div>' }
  } else {
    $head = '<h1>' + (Inline $s.Title) + '</h1>'
  }
  $pts = ""
  if ($s.Points.Count -gt 0) { $pts = '<ul class="points">' + (($s.Points | ForEach-Object { '<li>' + (Inline $_) + '</li>' }) -join '') + '</ul>' }
  $img = ""
  if ($s.ImagePath) {
    $ext = [IO.Path]::GetExtension($s.ImagePath).TrimStart('.').ToLower(); if ($ext -eq 'jpg') { $ext = 'jpeg' }
    if ($ext -eq 'svg') { $ext = 'svg+xml' }
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($s.ImagePath))
    $img = '<div class="media"><img alt="" src="data:image/' + $ext + ';base64,' + $b64 + '"></div>'
    $classes += "with-img"
  } else { $classes += "no-img" }
  $html = $tpl.Replace('{{TITRE}}', (HtmlEsc (Plain $s.Title))).Replace('{{CLASSES}}', ($classes -join ' ')).
    Replace('{{COURS}}', (HtmlEsc (Plain $videoTitle))).Replace('{{NUM}}', [string]$n).Replace('{{TOTAL}}', [string]$total).
    Replace('{{PROGRESS}}', ([math]::Round(100.0 * $n / $total, 1)).ToString($inv)).
    Replace('{{HEAD}}', $head).Replace('{{POINTS}}', $pts).Replace('{{IMAGE}}', $img)
  if ($html -match '\{\{[A-Z_]+\}\}') { Fail ("gabarit : variable non remplacee " + $Matches[0]) }
  $htmlPath = Join-Path $Temp ("slide_" + $tag + ".html")
  $pngPath = Join-Path $Temp ("slide_" + $tag + ".png")
  [IO.File]::WriteAllText($htmlPath, $html, $utf8)
  if (Test-Path -LiteralPath $pngPath) { Remove-Item -LiteralPath $pngPath }
  $url = "file:///" + ($htmlPath -replace '\\', '/' -replace ' ', '%20')
  $argLine = '--headless=new --disable-gpu --hide-scrollbars --no-first-run --no-default-browser-check --mute-audio ' +
    '--force-device-scale-factor=1 --window-size=1920,1080 --virtual-time-budget=3000 ' +
    '--user-data-dir="' + $chromeProfile + '" --screenshot="' + $pngPath + '" "' + $url + '"'
  $p = Start-Process -FilePath $browser -ArgumentList $argLine -PassThru -WindowStyle Hidden
  if (-not $p.WaitForExit(90000)) { try { $p.Kill() } catch {} ; Fail "le navigateur ne repond pas (diapo $n)" }
  $t0 = Get-Date
  while (-not (Test-Path -LiteralPath $pngPath) -and ((Get-Date) - $t0).TotalSeconds -lt 10) { Start-Sleep -Milliseconds 200 }
  if (-not (Test-Path -LiteralPath $pngPath)) { Fail "capture de la diapo $n echouee ($htmlPath)" }
  $bmp = [Drawing.Image]::FromFile($pngPath); $w = $bmp.Width; $h = $bmp.Height; $bmp.Dispose()
  if ($w -ne 1920 -or $h -ne 1080) { Write-Host ("  attention : diapo $n en ${w}x${h}, mise a l'echelle par ffmpeg") -ForegroundColor Yellow }
}

# ---------- 2. Voix (WAV) + 3. durees + 4. sous-titres ----------
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$fps = 30
$srt = New-Object System.Text.StringBuilder
$spokenLog = New-Object System.Text.StringBuilder
$cue = 0; $tStart = 0.0
$durations = @()
for ($i = 0; $i -lt $total; $i++) {
  $s = $slides[$i]; $n = $i + 1; $tag = "{0:00}" -f $n
  $wav = Join-Path $Temp ("voice_" + $tag + ".wav")
  $narr = Plain $s.Narr
  $voiceDur = 0.0
  if ($narr) {
    $spoken = Spoken $s.Narr
    [void]$spokenLog.AppendLine("[" + $tag + "] " + $spoken)
    $synth.SetOutputToWaveFile($wav, $fmt)
    $synth.Speak($spoken)
    $synth.SetOutputToNull()
    $voiceDur = WavDuration $wav
  } elseif (Test-Path -LiteralPath $wav) { Remove-Item -LiteralPath $wav }
  $d = $Lead + $voiceDur + $Pause
  if ($d -lt 2.5) { $d = 2.5 }
  $d = [math]::Ceiling($d * $fps) / $fps   # multiple exact d'une image
  $durations += $d
  # Sous-titres : timings proportionnels a la longueur dans la duree de la voix
  if ($narr -and $voiceDur -gt 0) {
    $segs = SplitSubs $narr
    $totalLen = 0; foreach ($g in $segs) { $totalLen += $g.Length }
    $t = $tStart + $Lead
    foreach ($g in $segs) {
      $len = $voiceDur * $g.Length / $totalLen
      $cue++
      $end = $t + $len
      [void]$srt.AppendLine([string]$cue)
      [void]$srt.AppendLine((SrtTime $t) + " --> " + (SrtTime ($end - 0.04)))
      [void]$srt.AppendLine((TwoLines $g))
      [void]$srt.AppendLine("")
      $t = $end
    }
  }
  $tStart += $d
}
$synth.Dispose()
[IO.File]::WriteAllText((Join-Path $Temp "subs.srt"), $srt.ToString(), $utf8)
[IO.File]::WriteAllText((Join-Path $Temp "narration_dite.txt"), $spokenLog.ToString(), $utf8)

# ---------- 5. Assemblage ffmpeg ----------
Push-Location -LiteralPath $Temp
try {
  $list = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $total; $i++) {
    $n = $i + 1; $tag = "{0:00}" -f $n; $d = $durations[$i]; $ds = F $d
    $seg = "seg_" + $tag + ".mkv"
    $fadeOut = F ([math]::Max(0, $d - $Fade))
    $vf = "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=0x121212,setsar=1,format=yuv420p," +
          "fade=t=in:st=0:d=" + (F $Fade) + ",fade=t=out:st=" + $fadeOut + ":d=" + (F $Fade)
    $delay = [int][math]::Round($Lead * 1000)
    $wav = "voice_" + $tag + ".wav"
    if (Test-Path -LiteralPath $wav) {
      $a = @('-i', $wav, '-af', ("adelay=" + $delay + ",aresample=48000,aformat=channel_layouts=stereo,apad"))
    } else {
      $a = @('-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo')
    }
    $ffArgs = @('-y', '-hide_banner', '-loglevel', 'error', '-loop', '1', '-framerate', [string]$fps, '-i', ("slide_" + $tag + ".png")) + $a +
      @('-t', $ds, '-vf', $vf, '-r', [string]$fps, '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '16', '-pix_fmt', 'yuv420p',
        '-c:a', 'pcm_s16le', '-ar', '48000', '-ac', '2', '-shortest', $seg)
    & $ffmpeg @ffArgs
    if ($LASTEXITCODE -ne 0) { Fail "ffmpeg : echec du segment $n (dossier $Temp)" }
    [void]$list.AppendLine("file '" + $seg + "'")
  }
  [IO.File]::WriteAllText((Join-Path $Temp "concat.txt"), $list.ToString(), $utf8)
  $style = "FontName=Segoe UI,FontSize=15,PrimaryColour=&H00FFFFFF,BackColour=&H60000000,OutlineColour=&HFF000000," +
           "BorderStyle=4,Outline=6,Shadow=0,MarginV=14,MarginL=40,MarginR=40,Alignment=2"
  $vf = "subtitles=subs.srt:charenc=UTF-8:force_style='" + $style + "'"
  if ($srt.Length -eq 0) { $vf = "null" }
  $tmpOut = "video_final.mp4"
  $ffArgs = @('-y', '-hide_banner', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', 'concat.txt',
    '-vf', $vf, '-r', [string]$fps, '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p', '-profile:v', 'high',
    '-c:a', 'aac', '-b:a', '160k', '-ar', '48000', '-movflags', '+faststart', $tmpOut)
  & $ffmpeg @ffArgs
  if ($LASTEXITCODE -ne 0) { Fail "ffmpeg : echec de l'assemblage final (dossier $Temp)" }
  Copy-Item -LiteralPath (Join-Path $Temp $tmpOut) -Destination $Out -Force
} finally { Pop-Location }

# ---------- 7. Bilan ----------
$sum = 0.0; foreach ($d in $durations) { $sum += $d }
$ts = [TimeSpan]::FromSeconds($sum)
Write-Host ("Diapos : " + $total + " ; sous-titres : " + $cue + " ; prononciations : " + $pron.Count)
Write-Host ("Duree totale : " + ("{0}:{1:00}" -f [math]::Floor($ts.TotalMinutes), $ts.Seconds) + " (" + (F $sum) + " s)")
Write-Host ("MP4 : " + (Resolve-Path -LiteralPath $Out).Path)
Write-Host ("Fichiers intermediaires : " + $Temp)
