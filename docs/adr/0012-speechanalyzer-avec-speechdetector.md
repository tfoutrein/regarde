---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 5
---

# ADR-0012 — La transcription repose sur SpeechAnalyzer avec SpeechDetector obligatoire, 100 % local

## Contexte

Le produit transforme un commentaire parlé en texte rattaché à une marque. Trois exigences le
cadrent. Rien ne doit sortir de la machine : l'outil filme un écran de développement, un envoi
vers un service de transcription serait rédhibitoire pour un usage sur projet client. Les
horodatages doivent être précis au mot, puisque le rattachement se joue sur l'instant du **premier
mot** d'un segment ([ADR-0011](0011-micro-par-fenetre-de-parole.md)). Enfin la transcription doit
se découper aux pauses : un segment par observation, pas un bloc pour la session.

L'horloge maîtresse de la session est déjà fixée
([ADR-0007](0007-horloge-maitresse-unique.md)), et les horodatages audio sont corrigés de la
latence d'entrée mesurée (§ 3.6) avant d'entrer dans le moteur.

## Décision

La chaîne retenue est `SpeechAnalyzer(modules: [transcriber, detector])`, avec
`SpeechTranscriber(preset: .timeIndexedProgressiveTranscription)` et un `SpeechDetector`
(`reportResults: false`) **obligatoire dans les modules**. L'audio est poussé au fil de l'eau
depuis le tap micro, jamais depuis une file de rattrapage, via `AnalyzerInput(bufferStartTime:)`
portant la timeline de session. Aucune permission de reconnaissance vocale n'est déclarée.

## Options envisagées

### Option A — `SFSpeechRecognizer`

- **Pour** : API mature, disponible depuis longtemps, abaisserait la version minimale de macOS.
- **Contre** : sessions plafonnées en durée, ce qui interdit une passe de recette de dix minutes ;
  horodatage à la granularité de la phrase, pas du mot ; et l'API impose une autorisation
  utilisateur explicite pour la reconnaissance vocale, donc une invite système supplémentaire dans
  un produit qui en demande déjà quatre.

### Option B — whisper.cpp embarqué

- **Pour** : local, indépendant de la version du système, qualité connue et réglable.
- **Contre** : plusieurs centaines de mégaoctets de modèle à embarquer, signer et notariser ;
  charge CPU/GPU permanente pendant une session dont la promesse est de ne pas perturber
  l'application testée ; et surtout, le découpage et l'horodatage relèveraient alors de code
  applicatif, à écrire, régler et maintenir, pour un résultat au mieux équivalent.

### Option C — `SpeechAnalyzer` + `SpeechTranscriber` + `SpeechDetector` (retenue)

- **Pour** : sessions non plafonnées, horodatage au mot (0,1 à 0,3 s), exécution locale hors de
  l'espace d'adressage de l'application, modèles gérés par MobileAsset, **aucune permission de
  reconnaissance vocale requise**.
- **Contre** : exige macOS 26 ; comportement de segmentation non documenté qu'il a fallu établir
  par sondage.

## Justification

Trois faits établis par les sondes de faisabilité, absents de la documentation Apple, ont fixé la
forme exacte de l'implémentation :

1. **Sans `SpeechDetector` dans les modules, il n'y a aucune segmentation aux pauses.** Toute la
   session revient en un unique résultat final. Le détecteur n'est pas là pour ce qu'il rapporte —
   son flux `.results` n'émet rien, d'où `reportResults: false` — mais pour le comportement qu'il
   induit dans l'analyseur. Sans lui, la règle de rattachement de l'ADR-0011 n'a plus d'objet :
   un seul segment ne se rattache à aucune marque en particulier.
2. **Alimenter plus vite que le temps réel effondre la segmentation.** Toute stratégie de
   rattrapage — bufferiser puis pousser en rafale après une interruption — détruit précisément ce
   qu'on cherche. Le push se fait au fil de l'eau depuis le tap micro, sans file intermédiaire.
3. **Aucune permission de reconnaissance vocale n'est requise.** Une transcription complète a été
   obtenue avec `SFSpeechRecognizer.authorizationStatus() == .notDetermined`, sans qu'aucune
   invite n'apparaisse. `NSSpeechRecognitionUsageDescription` n'est donc pas déclaré : le
   déclarer ferait apparaître une invite « souhaite accéder à la reconnaissance vocale » là où le
   système n'en demande aucune — anxiogène et sans contrepartie. Seul
   `NSMicrophoneUsageDescription` reste nécessaire.

Le point décisif face aux deux options écartées est ailleurs : `AnalyzerInput(bufferStartTime:)`
permet d'**imposer** la timeline de session au moteur. Tous les horodatages de retour, segments
comme mots, sortent directement sur cette timeline, y compris après une interruption micro — le
moteur tolère une timeline discontinue tant qu'elle reste monotone, ce qui est exactement le cas
d'une succession de fenêtres de parole. Il n'existe donc aucune couche de réconciliation
applicative entre le temps du son et le temps de la session. Avec whisper.cpp, cette couche serait
à écrire, et c'est du code sur le chemin critique de la justesse du produit.

Sur le jargon technique, une piste a été mesurée puis abandonnée : `contextualStrings` **n'a aucun
effet mesurable** — en A/B strict, avec et sans liste de termes, la sortie est rigoureusement
identique. Le mécanisme retenu est un lexique déterministe (environ 200 termes front figés, plus
les identifiants extraits du projet cible, dont le chemin est connu), appliqué par distance
phonétique aux seuls mots de confiance inférieure à 0,6, les deux versions étant écrites dans le
rapport : `pratique` *[padding ?]*. Complété par l'édition inline dans la revue, `rawText` conservé.

## Conséquences

- **Positives** : aucun modèle à embarquer ni à notariser ; rien ne quitte la machine, ce qui rend
  la garantie du § 10.1 vérifiable ; une invite système de moins à l'onboarding ; horodatages
  exploitables directement, sans code de recalage.
- **Négatives — le prix à payer, assumé** : macOS 26 minimum, sans repli possible. La cible était
  annoncée, ce choix la verrouille : aucune version antérieure ne pourra être servie, même en
  dégradant la qualité. Le comportement de segmentation repose sur un effet non documenté du
  `SpeechDetector`, qu'une mise à jour du système peut modifier sans note de version. Et surtout, le
  risque d'erreur **plausible** demeure : « marge à droite » transcrit en « barre de droite » est
  grammaticalement valide et sort avec une confiance élevée, donc ni le seuil de 0,6 ni le lexique
  ne le rattrapent — l'agent ajoutera une bordure.
  Seule la relecture humaine dans la revue protège de ce cas, et elle n'est plus automatique.
- **Ce que ça ferme** : le choix du modèle de transcription, sa langue au-delà de ce que
  `SpeechTranscriber.supportedLocale` propose, et tout réglage de qualité. On prend ce que le
  système donne.

## Signal de révision

Deux observations rouvriraient la décision. La première est la mesure préalable obligatoire du
lot 5 : trois minutes de dictée réelle du développeur, micro interne, bureau ouvert, comptage des
termes techniques à corriger. Au-delà d'un terme sur cinq, le lot 5 tel que spécifié n'est pas
livrable et la saisie clavier passe devant. La seconde est l'apparition d'erreurs plausibles
répétées sur un même vocabulaire projet, constatée dans les diffs produits par l'agent : ce serait
le signe que le lexique déterministe ne suffit pas et qu'un modèle contrôlable localement
redevient défendable, malgré son coût d'embarquement.

## Références

- Spécification § 4.1 (ligne Transcription), § 7.1 (chaîne retenue et faits des sondes),
  § 7.3 (jargon technique), § 3.6 (latence d'entrée), § 10.1, § 11.3 lot 5.
- Sondes de faisabilité : segmentation sans `SpeechDetector`, alimentation plus rapide que le
  temps réel, `authorizationStatus() == .notDetermined`, A/B `contextualStrings`.
- [ADR-0011](0011-micro-par-fenetre-de-parole.md) — micro par fenêtre de parole.
- [ADR-0007](0007-horloge-maitresse-unique.md) — horloge maîtresse unique.
- [ADR-0002](0002-hors-sandbox-developer-id.md) — distribution hors sandbox, Developer ID.

## Révision du 29 août 2026 — macOS 26.1, sessions S59 et S64

Le risque résiduel nommé ci-dessus s'est réalisé, dans les deux sens. Mesuré
avec le harnais de S59 puis en vivant en S64 :

- **sans `SpeechDetector`, la segmentation est identique** (trois modes, sept
  segments) — le fait de sonde n°1 ne se manifeste plus ;
- **alimenter plus vite que le temps réel ne dégrade rien** — le fait de sonde
  n°2 non plus ;
- **avec `SpeechDetector`, la parole se perd** : face au bruit réel d'un micro
  (jamais un silence), toute énonciation après la première finale est avalée,
  sans même un volatile — un monologue de deux phrases n'en rendait qu'une ;
  sans lui, les deux ;
- **les résultats ne sont pas progressifs en temps réel** : rien pendant les
  douze premières secondes d'une fenêtre, puis une rafale. La prolongation de
  la fenêtre et la rétention de l'éclair reposent sur l'énergie des tranches
  audio, pas sur les volatils.

Décision révisée : `SpeechAnalyzer(modules: [transcriber])`, le détecteur
retiré ; `--avec-detecteur` au lancement le remet, pour re-mesurer à chaque
version de macOS (lot5-seuils § 2 et § 10). Le reste de l'ADR — poussée au fil
de l'eau, `AnalyzerInput(bufferStartTime:)`, aucune permission de
reconnaissance vocale, jargon par lexique — tient.
