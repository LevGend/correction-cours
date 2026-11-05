param([string]$Path, [int]$Min = 3)
# Extrait les chaînes UTF-16LE (alphabet latin) d'un fichier OneNote (.one), aux deux alignements
$b = [IO.File]::ReadAllBytes($Path); $out = New-Object Collections.Generic.List[string]
foreach ($start in 0,1) {
  $sb = New-Object Text.StringBuilder; $pos = 0
  for ($i = $start; $i -lt $b.Length - 1; $i += 2) {
    $c = [BitConverter]::ToUInt16($b, $i)
    $ok = ($c -ge 0x20 -and $c -le 0x24F) -or ($c -ge 0x2010 -and $c -le 0x2027) -or $c -eq 0x20AC -or ($c -ge 0x2190 -and $c -le 0x21FF) -or $c -eq 9 -or $c -eq 10 -or $c -eq 13 -or $c -eq 0x2022
    if ($ok) { if ($sb.Length -eq 0) { $pos = $i }; [void]$sb.Append([char]$c) }
    else { if ($sb.Length -ge $Min) { $out.Add(('{0:D7}|{1}' -f $pos, $sb.ToString())) }; [void]$sb.Clear() }
  }
}
$out | Sort-Object | ForEach-Object { $_.Substring(8) }
