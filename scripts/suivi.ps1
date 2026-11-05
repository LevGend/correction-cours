param([string]$Action, [string]$Etape = '', [string]$Champ = '', [string]$Valeur = '')
# Met à jour suivi.json : journal + champ d'une étape du traitement en cours.
# Exemple : -Action "Traducteur lancé" -Etape traducteur -Champ statut -Valeur en_cours
$f = Join-Path $PSScriptRoot '..\suivi.json'
$j = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) | ConvertFrom-Json
$now = Get-Date -Format 'yyyy-MM-ddTHH:mm'
if ($Etape -and $Champ) {
  $t = $j.traitements[-1]
  $t.etapes.$Etape | Add-Member -NotePropertyName $Champ -NotePropertyValue $Valeur -Force
} elseif ($Champ) { $j.traitements[-1] | Add-Member -NotePropertyName $Champ -NotePropertyValue $Valeur -Force }
if ($Action) { $j.journal += [pscustomobject]@{ date = $now; acteur = 'orchestrateur'; action = $Action } }
$j.mis_a_jour = $now
[IO.File]::WriteAllText($f, ($j | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
