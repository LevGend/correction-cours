param([string]$XmlDir, [string]$OutFile, [string]$ImgDir)
# Aplati les pages OneNote XML en texte indenté compact (titres, listes, tableaux, images + OCR).
$sb = New-Object Text.StringBuilder; $nsU = 'http://schemas.microsoft.com/office/onenote/2013/onenote'
New-Item -ItemType Directory -Force $ImgDir | Out-Null
function Txt($t) { $s = [regex]::Replace($t, '<span[^>]*font-weight:bold[^>]*>(.*?)</span>', '**$1**'); $s = [regex]::Replace($s, '<[^>]+>', ''); [Net.WebUtility]::HtmlDecode($s).Trim() }
function Walk($node, $d) {
  foreach ($n in $node.ChildNodes) {
    switch ($n.LocalName) {
      'OE' {
        $pre = '  ' * $d
        $lst = $n.SelectSingleNode('*[local-name()="List"]')
        if ($lst) { if ($lst.SelectSingleNode('*[local-name()="Number"]')) { $pre += '1. ' } else { $pre += '- ' } }
        foreach ($t in $n.SelectNodes('*[local-name()="T"]')) { $x = Txt $t.InnerText; if ($x) { [void]$sb.AppendLine("$pre$x") } }
        foreach ($tb in $n.SelectNodes('*[local-name()="Table"]')) {
          foreach ($r in $tb.SelectNodes('*[local-name()="Row"]')) {
            $cells = foreach ($c in $r.SelectNodes('*[local-name()="Cell"]')) { (($c.SelectNodes('.//*[local-name()="T"]') | ForEach-Object { Txt $_.InnerText }) -join ' / ') }
            [void]$sb.AppendLine("$('  '*$d)| " + ($cells -join ' | ') + ' |')
          }
        }
        foreach ($im in $n.SelectNodes('*[local-name()="Image"]')) { Img $im $d }
        $ch = $n.SelectSingleNode('*[local-name()="OEChildren"]'); if ($ch) { Walk $ch ($d + 1) }
      }
      'Image' { Img $n $d }
      default { if ($n.HasChildNodes -and $n.LocalName -in 'Outline','OEChildren') { Walk $n $d } }
    }
  }
}
function Img($im, $d) {
  $script:k++; $f = "img_$script:k.png"
  $data = $im.SelectSingleNode('*[local-name()="Data"]'); if ($data) { [IO.File]::WriteAllBytes("$ImgDir\$f", [Convert]::FromBase64String($data.InnerText)) }
  $ocr = $im.SelectSingleNode('.//*[local-name()="OCRText"]'); $o = if ($ocr) { ($ocr.InnerText -replace '\s+', ' ').Trim() } else { '' }
  [void]$sb.AppendLine("$('  '*$d)[IMAGE work/img/$f] OCR: $o")
}
$script:k = 0
foreach ($file in Get-ChildItem "$XmlDir\page_*.xml" | Sort-Object Name) {
  $x = New-Object Xml.XmlDocument; $x.Load($file.FullName); $p = $x.DocumentElement
  [void]$sb.AppendLine("`n===== PAGE (niveau $($p.pageLevel)) : $($p.name) =====")
  foreach ($o in $p.SelectNodes('*[local-name()="Outline"]')) { $ch = $o.SelectSingleNode('*[local-name()="OEChildren"]'); if ($ch) { Walk $ch 0 }; [void]$sb.AppendLine('') }
  foreach ($im in $p.SelectNodes('*[local-name()="Image"]')) { Img $im 0 }
}
[IO.File]::WriteAllText($OutFile, $sb.ToString(), [Text.UTF8Encoding]::new($false))
