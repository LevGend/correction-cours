# Projet : Correction IA de notes de cours

Pipeline qui transforme les notes OneNote d'un étudiant en informatique en une page HTML corrigée, organisée et publiée.

## Orchestrateur (la session principale)
La session principale **est** l'orchestrateur : un sous-agent ne peut pas lancer d'autres agents, donc c'est la session principale qui pilote.
- **Tout passe par lui.** Chaque instruction de l'utilisateur lui est adressée. Il l'enregistre dans `suivi.json` (`consignes`), puis la transmet aux agents concernés dans leur prompt.
- **Mémoire de travail = `suivi.json`.** Il le lit **au début de chaque tour** et **avant chaque étape**. En cas de doute ou d'oubli (consigne, état d'une étape, fichier produit), il s'y réfère avant toute autre source. Il le met à jour **après chaque action** : démarrage et fin d'étape, erreur, décision, nouvelle consigne.
- **Obligation de résultat.** Il ne rend la main qu'avec le fichier final livré et contrôlé. Si une étape échoue ou si sa sortie ne passe pas le contrôle, il relance l'agent (au plus 2 fois) en passant au modèle supérieur, puis corrige lui-même si besoin. Il trace chaque tentative dans `suivi.json`.
- **Contrôle qualité après chaque étape**, avant de passer à la suivante :
  - traducteur : `01_notes.md` existe, n'est pas vide et couvre tout le fichier source
  - professeur : `02_corrige.md` est complet (même nombre de pages que `01_notes.md`), toutes les balises de couleur sont fermées, chaque bloc `:::concept` a ses volets `@theorie` et `@pratique` et se ferme par `:::`
  - évaluateur : `02_evaluation.md` respecte le format (note /20 = Compréhension + Taux + Bonus plafonnée à 20, tableau « Taux par chapitre », section « Pour aller plus loin »)
  - organisateur : aucune perte de contenu par rapport à `02_corrige.md`, balises de couleur conservées (`perso`, `del`, `fix`, `ai`, `hors`, `gap`), autant de blocs `:::concept` qu'en entrée, chaque H2 a au moins un H3, `03_titre.txt` fait 40 caractères au maximum
  - publication : le nom de fichier respecte le format, le HTML est bien formé, les 2 onglets et le sommaire fonctionnent, un `.concept` par bloc `:::concept`, les boutons « Voir des exemples », la légende et l'interrupteur fonctionnent, il ne reste aucun `{{…}}`
- **Parallélisme :** l'évaluateur et l'organisateur partent tous les deux de `02_corrige.md` et n'écrivent pas les mêmes fichiers. L'orchestrateur les lance **dans le même message**, puis attend les deux avant de publier.
- **Publication par script :** l'orchestrateur lance lui-même `scripts/md2html.ps1`. L'agent **publieur** n'est appelé que si le script échoue ou si le contrôle de publication échoue.
- **Choix du modèle selon la complexité** (paramètre `model` de l'outil Agent) :

  | Étape | Par défaut | Monter d'un cran si… |
  |---|---|---|
  | traducteur | haiku | images, écriture manuscrite, PDF scanné ou plus de 20 pages → sonnet |
  | professeur | opus | toujours opus (exactitude critique) |
  | évaluateur | sonnet | support très long (plus de 50 pages) ou notation délicate → opus |
  | organisateur | sonnet | notes très longues ou très désordonnées → opus |
  | publieur (dépannage) | sonnet | bug non résolu → opus |
  | relance après échec | modèle supérieur | — |

  Le modèle retenu et la raison du choix sont notés dans `suivi.json`.
- **Fin de traitement :** il renomme la conversation (titre issu de `03_titre.txt`), affiche le message court de l'évaluateur avec la note /20, puis passe le statut du traitement à `termine`.

### Format de `suivi.json`
- `consignes[]` : toutes les instructions de l'utilisateur (date, texte, statut `active` ou `remplacee`)
- `regles_permanentes` : résumé des règles en vigueur
- `traitements[]` : un objet par cours traité, avec `id`, `debut`, `statut` (`en_cours` / `termine` / `echec`), `fichiers_entree`, `titre`, `note`, `fichier_final`, et `etapes{}` (pour chaque étape : `statut`, `modele`, `raison_modele`, `tentatives`, `sorties`, `controle`, `remarques`)
- `journal[]` : historique horodaté des actions

## Dossiers
- `input/` : fichiers déposés par l'étudiant (export OneNote + support de cours éventuel)
- `work/` : fichiers intermédiaires produits par les agents
  - `01_notes.md`, `01_support.md` (traducteur)
  - `02_corrige.md` (professeur)
  - `02_evaluation.md` (évaluateur)
  - `03_organise.md`, `03_titre.txt` (organisateur)
- `template/cours_template.html` : gabarit HTML, CSS et JS dans un seul fichier
- `scripts/` : outils de l'orchestrateur (`one_export.ps1`, `one_flatten.ps1`, `md2html.ps1`, `suivi.ps1`)
- `output/COURS_CORRECTION_IA_DDMMYYYY_HHMM.html` : rendu final

## Workflow
1. **traducteur** : `input/*` → `work/01_notes.md` (+ `work/01_support.md` si un support est joint). Pour un `.one`, l'orchestrateur prépare d'abord `work/00_source.txt` et `work/img/` avec `one_export.ps1` et `one_flatten.ps1`.
2. **professeur** : `work/01_*.md` → `work/02_corrige.md`
3. En parallèle :
   - **évaluateur** : `01_notes.md` + `01_support.md` + `02_corrige.md` → `work/02_evaluation.md`
   - **organisateur** : `work/02_corrige.md` → `work/03_organise.md` + `work/03_titre.txt`
   → l'orchestrateur renomme ensuite la conversation avec le contenu de `03_titre.txt`
4. **Publication** (orchestrateur, par script) : `scripts/md2html.ps1 -Date … -Note … -Out output/COURS_CORRECTION_IA_<date>_<heure>.html`. En cas d'échec : agent **publieur**.
5. L'orchestrateur affiche dans le chat le court message de l'évaluateur avec la note /20.

## Règles communes
- Ne pas inventer d'informations. Toute information non présente dans les notes ou dans le support doit être vérifiable.
- Ne pas surcharger : rester concis et fidèle aux notes.
- **Code couleur = provenance du texte**, sans jamais écrire « corrigé » ni « ajout IA » : la couleur suffit.

  | Couleur | Sens | Balise |
  |---|---|---|
  | Blanc | Noté par l'étudiant, présent dans le cours | texte brut |
  | Or | Noté par l'étudiant, absent du cours (recherche personnelle) | `<span class="perso">` |
  | Rouge | Correction : texte initial barré, puis version juste | `<del>…</del> <span class="fix">…</span>` |
  | Orange | Présent dans le cours, non noté (oubli complété) | `<span class="ai">` / `<div class="ai">` |
  | Violet | Complément du professeur hors cours | `<span class="hors">` / `<div class="hors">` |
  | Cyan pointillé | `[?]` comblé | `<span class="gap">` |

  Le rouge est réservé aux corrections : les encadrés `[!…]` sont neutres. Dans la page, la légende est cliquable (masquer une couleur) et un interrupteur active ou désactive toutes les couleurs.
- **Marqueur `[?]`** : l'étudiant l'écrit quand il a raté une information. Le professeur le comble s'il est certain, sinon il le laisse.
- **Notation** : Compréhension /10 + Taux de prise de notes par chapitre /10 + bonus recherche personnelle jusqu'à +3, plafond 20. La structure et la clarté ne sont pas notées.
- Codes de style Markdown reconnus par le publieur :
  - `> [!DEF]` définition · `> [!IMPORTANT]` point clé · `> [!EXEMPLE]` exemple · `> [!ATTENTION]` piège ou erreur fréquente
  - Blocs de code avec le langage (```bash, ```python…)
- Notes OneNote = toujours des notes manuscrites ou prises à la main : tolérer l'orthographe approximative et les abréviations, mais les retranscrire proprement.
- **Concepts en 3 volets** (rédigés par le professeur, conservés tels quels par l'organisateur, rendus par le publieur) :
  ```
  :::concept Nom du concept
  @theorie
  Principe, en 1 à 3 phrases.
  @pratique
  Cas d'usage ou nom des solutions.
  @exemple
  Commande, configuration, capture ![](img/…) ou schéma, tiré du cours en priorité.
  :::
  ```
  Le publieur affiche Théorie et Pratique. Si l'exemple est riche (code, image, tableau, liste ou plus de 120 caractères), il est replié derrière un bouton **« Voir des exemples »** ; un exemple court reste affiché directement.
