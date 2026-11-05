# Correction IA de notes de cours

Pipeline Claude Code qui transforme des notes OneNote (+ supports de cours PDF) en une page HTML corrigée, organisée et notée.

- Règles et workflow : `CLAUDE.md`
- Agents : `.claude/agents/` (traducteur, professeur, évaluateur, organisateur, publieur)
- Suivi des consignes et des traitements : `suivi.json`
- Outils : `scripts/` (export OneNote, conversion HTML, mise à jour du suivi)
- Gabarit : `template/cours_template.html`
- Rendus : `output/COURS_CORRECTION_IA_DDMMYYYY_HHMM.html`

## Prérequis (Windows)
- Git, Claude Code
- OneNote (bureau) pour exporter les fichiers `.one`
- `pdftotext` (fourni avec Git for Windows / MSYS2) pour les supports PDF

## Utilisation
Ouvrir le dossier dans Claude Code et envoyer le fichier `.one` et les PDF du cours.
Les dossiers `input/`, `work/` et `archive/` restent locaux (non versionnés).
