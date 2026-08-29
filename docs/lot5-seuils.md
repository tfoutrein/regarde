# Lot 5 — seuils et contrats, écrits avant la première ligne d'audio

Session S60, le 29 août 2026. La règle est celle de S31, S46 et du § 7.6 : un
seuil écrit après la mesure est un seuil ajusté au résultat, et un format décidé
pendant qu'on l'écrit est un format ajusté au code.

## 0. État de la mesure S59 — à faire, trois minutes chrono

La dictée réelle du § 10.1 — la voix de l'auteur, trois minutes, bureau
habituel — reste **à faire** ; le harnais est prêt et la rend exécutable en
trois minutes : enregistrer (Dictaphone ou QuickTime), exporter en `.m4a`, puis
`swift app/Tools/lot5-dictee.swift <fichier.m4a>`, et compter les trois nombres.

En attendant les trois nombres, les sessions engagées sont celles **valides dans
toutes les branches** de la table § 10.1 — S60 (contrats), S61 (micro), S62
(chaîne), S63 (machine à états), S69-S70 (clavier, nécessaire dans les trois
branches). Seul l'ordre S64-S68 avant le clavier — la voix comme canal
principal — dépend de la mesure.

## 1. Les seuils, chacun avec son unité et sa source

| # | Seuil | Valeur | Unité | Source |
|---|---|---|---|---|
| 1 | Rattachement — critère du lot | 6 observations sur 6 à la bonne marque | observations, session de 3 min | § 11.3, ADR-0011 |
| 2 | Perte de fin de parole | 0 mot perdu dans les 3 dernières secondes avant ⌃⌥F | mots | livrable du lot |
| 3 | Budget d'ancrage du « premier mot » | ± 150 ms après compensation de latence | ms entre l'instant réel du premier mot et son horodatage session | § 3.6 — la latence AirPods non compensée (150-300 ms) « consomme tout le budget » : le budget EST donc de cet ordre |
| 4 | Latence d'entrée compensée | mesurée à l'ouverture et à chaque `ConfigurationChange`, affichée au doctor | ms (somme des trois termes § 3.6) | § 3.6, ADR-0007 |
| 5 | Drain à la fermeture de fenêtre | attendu jusqu'à 2,7 s ; jamais coupé | s | § 7.2 (résultats finaux 1,3-2,7 s après la parole) |
| 6 | Plafond d'une fenêtre de parole | 20 s, dur, volatils compris | s | ADR-0011 |
| 7 | Fin de session, drain compris | ≤ 20 s du raccourci au presse-papiers, chrono au manifeste | s | § 6.6 — budget dur du lot 4, inchangé |
| 8 | Taille de `transcript.txt` | < 25 Kio par session | Kio | § 9.2 |
| 9 | Correction lexicale | uniquement sous confiance < 0,6 ; les deux versions au rapport | confiance par mot | § 7.3, ADR-0012 |

## 2. Verdict du harnais S59 sur cette machine — à rejouer à chaque mise à jour macOS

macOS **26.1**, dictée de synthèse (voix Thomas) de 75 s, 29 août 2026 :

| Mode | Segments | Constat |
|---|---|---|
| nominal (fil de l'eau, detector) | 7 | segmentation aux pauses, texte complet |
| `--sans-detector` | 7 | **identique** — le fait de sonde n°1 d'ADR-0012 ne se manifeste plus |
| `--vite` (plus vite que le réel) | 7 | **identique** — le fait de sonde n°2 ne se manifeste plus |

Le produit garde `SpeechDetector` dans les modules et la poussée au fil de l'eau
— défense en profondeur contre une régression système. Aucun critère n'exige de
reproduire les effondrements ; le harnais les mesure et cette table se remet à
jour à chaque version de macOS.

Leçons d'implémentation, payées par le harnais et NORMATIVES pour S62 :
`bufferStartTime` se compte en **échantillons entiers** (jamais en secondes
flottantes — le cumul chevauche d'un tick et le moteur refuse l'audio), et suit
les échantillons **sortis** du converter (les résidus de conversion créent des
trous qui hachent les mots).

## 3. `transcript.txt` — le format, tranché (§ 9.2)

Une ligne par **segment final**, append-only par la porte unique
(`AppendOnlyLog`), UTF-8, jamais réécrite :

```
[MM:SS.d] (marque 2|global|éclair) texte brut du segment
```

- le temps est le **temps de session** de l'onset du segment ;
- le texte est `rawText` — jamais la version corrigée par le lexique : le
  fichier est le témoin brut, la correction vit au manifeste ;
- **versionnable** : hors `.gitignore` du projet. `git status` d'une session
  publiée propose donc CINQ chemins à partir de S66 — `BoucleSelfTest` (égalité
  d'ensembles), la recette du lot 4 (« exactement quatre ») et le `.gitignore`
  écrit par le publieur changent **dans la même session** ;
- « jamais servi par MCP » (§ 9.2) — contrat pour le lot 6, rien à faire ici ;
- éclair : même format, dans le dossier de l'éclair sous `~/Regarde`.

## 4. Manifeste — membres optionnels du schéma 1.1, pas de montée de version

L'exemple normatif du § 9.5 montre `voice[]`, `session.locale` et
`session.audioInputLatencyMs` **sous `schemaVersion` 1.1**. Décision conforme :

- les champs voix sont des membres **optionnels** de 1.1 — un manifeste sans
  voix reste identique à l'octet, l'empreinte du rapport de référence du lot 4
  est préservée par construction ;
- `marks[].voice[]` : `{id "v-NNN", attachedTo, attachment{rule, auto,
  editedByUser}, onset, end, text, rawText, lexiconSuggestions[{heard,
  suggested, confidence, at}]}` — au mot près l'exemple § 9.5 ;
- les segments **globaux** vont dans `session.voice[]`, même forme sans
  `attachedTo` — trou du § 9.5 tranché ici : la symétrie avec `marks[].voice[]`
  évite un second vocabulaire ;
- `locale` et `audioInputLatencyMs` ne sont rendus dans l'en-tête du rapport
  **que si le manifeste porte de la voix** (`marks[].voice[]` ou
  `session.voice[]` non vides) — une session au micro refusé n'a rien à en
  dire, et `schemaVersion` seule ne déclenche jamais l'affichage ;
- `MarkShape.text(NormPoint, String)` (§ 3.4) : au manifeste, `kind: "text"`
  et le texte dans le champ `text` de la marque — schéma posé ici pour S70.

## 5. La voix de l'éclair — modalités (le principe est tranché : l'éclair parle)

- la fenêtre de parole s'ouvre à la prise ⌥⌘, en éclair comme en session —
  même chemin, même machine à états (S63) ;
- l'éclair **silencieux** publie comme aujourd'hui : `flashGrace` 0,8 s après
  le relâchement, si **aucun volatile** n'est arrivé depuis l'ouverture ;
- l'éclair **parlé** attend la fermeture de la fenêtre (8 s + volatils,
  plafond 20 s) puis le drain, et publie avec son transcript — le coût
  d'armement du moteur par fenêtre est le prix assumé d'ADR-0011 ;
- l'horodatage hors session : les temps de l'éclair sont relatifs à la prise
  de ⌥⌘ (l'origine de sa fenêtre), sur l'horloge maîtresse d'ADR-0007.

## 6. Les paroles d'une marque annulée (`undoLast`)

La parole de l'utilisateur ne se jette jamais en silence : les segments d'une
marque annulée basculent en **commentaire global**, `attachment.rule`
inchangée, avec la mention de réaffectation au journal. Le rapport écrit
« marque N (supprimée) » si un texte y fait référence (§ 3.5).

## 7. Décisions d'ouverture (S59, tranchées par écrit)

- **A2** : la saisie texte clavier est DANS le lot (S69-S70) — l'arbitrage
  § 13.1 recommandait, c'est acté ;
- **A5** : la revue à la demande est DANS le lot (S71) ; la **purge** du
  plafond de 15 min part au lot 7 — la frontière passe entre éditer et purger ;
- la table § 10.1 est réconciliée sur le seuil normatif du § 7.3 : **4/5**.

## 8. Décisions de S63 — la machine à états, vérifiées par `--parole-test`

- un **second tracé dans la même tenue** de ⌥⌘ scinde la fenêtre : une fenêtre
  porte une marque et une seule, la suivante hérite de la tenue ;
- une **fenêtre sans marque** (tenue sans tracé) est globale — la parole ne se
  jette jamais en silence ; le geste global *explicite* (> 400 ms, immobile) est
  en plus annoncé au HUD ;
- la **prolongation** par les volatils repousse l'échéance à `dernier volatil +
  1 s`, jamais au-delà du plafond de 20 s ; un volatil en retard ne raccourcit
  rien (maximum, pas dernier venu) ;
- une **nouvelle prise** ferme la fenêtre précédente : les fenêtres sont des
  intervalles disjoints, un premier mot n'en trouve qu'une ;
- le **verrou ⌃⌥M** l'emporte sur la fenêtre pendant toute sa durée, y compris
  relu après coup ; la parole d'avant et d'après reste à sa marque.

## 9. Découvertes de S61 — le micro, mesurées en vivant le 29 août 2026

- **`AVAudioEngine` ne prend pas de périphérique imposé** sur macOS 26.1 :
  `kAudioOutputUnitProperty_CurrentDevice` sur l'`inputNode` — avant la
  préparation, entre uninit/init, après la préparation — répond « succès » et
  tue l'entrée en silence (zéro appel du tap, moteur « en marche »). Sans
  imposition, 15 tranches. Comme « jamais l'entrée par défaut » (§ 7.2) n'est
  pas négociable, le micro est une **`AVCaptureSession`** avec
  `AVCaptureDeviceInput` sur le périphérique choisi : 141 tranches en 1,5 s,
  contiguës depuis 0, PTS sur l'horloge hôte (ADR-0007). Le terme
  « présentation » de la latence § 3.6 n'existe plus : le PTS de chaque buffer
  porte déjà l'instant de capture, restent les deux termes du périphérique.
- **Le rappel audio n'est jamais une fermeture écrite dans une classe
  `@MainActor`** : Swift 6 l'infère isolée, et la file audio plante à
  l'assertion d'isolation (SIGTRAP, `dispatch_assert_queue_fail`) — constaté
  au premier rappel qui a réellement tourné. Le délégué est une classe à part,
  non isolée, nourrie d'un contexte Sendable ; le bloc d'entrée du converter
  (`@Sendable`) reçoit une boîte à usage unique (`SourceAudioUnique`), jamais
  une variable mutable ni un tampon — en release ce sont des erreurs.
- La fermeture d'office (veille, verrouillage, changement de session, saisie
  sécurisée) et la reconfiguration (périphérique débranché, erreur de session)
  sont câblées ; leur épreuve vivante appartient à S64, quand une fenêtre
  existe dans l'application.
