param([string]$Path, [string]$OutDir)
# Ouvre une section .one via OneNote COM et exporte chaque page en XML (images incluses).
$ErrorActionPreference = 'Stop'
$on = New-Object -ComObject OneNote.Application
$id = ''; $on.OpenHierarchy($Path, '', [ref]$id, 0)
for ($t = 0; $t -lt 30; $t++) {
  try { $on.SyncHierarchy($id) } catch {}
  $xml = ''; $on.GetHierarchy($id, 4, [ref]$xml)
  if ($xml -match '<one:Page ' -and $xml -notmatch 'areAllPagesAvailable="false"') { break }
  Start-Sleep -Seconds 2
}
[IO.File]::WriteAllText("$OutDir\hierarchy.xml", $xml, [Text.UTF8Encoding]::new($false))
$h = [xml]$xml; $ns = New-Object Xml.XmlNamespaceManager $h.NameTable; $ns.AddNamespace('one', $h.DocumentElement.NamespaceURI)
$i = 0
foreach ($p in $h.SelectNodes('//one:Page', $ns)) {
  $i++; $c = ''; $on.GetPageContent($p.ID, [ref]$c, 1)
  [IO.File]::WriteAllText(("$OutDir\page_{0:D2}.xml" -f $i), $c, [Text.UTF8Encoding]::new($false))
  "{0:D2} | niv {1} | {2}" -f $i, $p.pageLevel, $p.name
}
"Pages: $i"
