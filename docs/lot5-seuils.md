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

Le produit garde la poussée au fil de l'eau — elle ne coûte rien. Le
`SpeechDetector`, lui, est **retiré** depuis S64 : il ne segmentait rien de plus,
et face au bruit réel d'un micro il avalait toute énonciation après la première
finale (§ 10). `--avec-detecteur` au lancement le remet, pour re-vérifier à
chaque version de macOS ; cette table se remet à jour avec.

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
  le relâchement, si **aucune parole n'a été entendue** depuis l'ouverture —
  au sens de l'énergie des tranches (§ 10), pas des volatils du moteur, qui
  n'existent pas avant douze secondes ;
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

## 10. Découvertes de S64 — le branchement, mesuré en vivant le 29 août 2026

- **Le moteur ne rend rien pendant les douze premières secondes** d'une
  fenêtre : sur la dictée de référence poussée au temps réel, TOUS les
  volatils « progressifs » arrivent en rafale à 12,1 s d'horloge murale, quel
  que soit leur temps audio ; en vivant, le premier volatile d'une phrase dite
  à 2 s arrive à 11,8 s. La « transcription progressive » l'est en temps audio,
  pas en temps réel. Conséquence : ni la prolongation de la fenêtre par les
  volatils (ADR-0011) ni « aucun volatile à 0,8 s » (§ 5) n'ont de quoi
  décider. Le signal de parole en temps réel est l'**énergie** des tranches —
  RMS sur l'échelle Int16, calculée dans le rappel audio — : elle nourrit la
  machine (« la parole continue ») et retient l'éclair. Seuil calibré sur cette
  machine : bruit ambiant 208, parole de synthèse aux haut-parleurs 1 382 —
  **400**, au plus quatre signaux par seconde. Les volatils du moteur restent
  branchés : quand ils arrivent, ils prolongent aussi.
- **La continuité audio** : une nouvelle prise qui ferme la fenêtre précédente,
  ou un second tracé qui la scinde, ne ferme ni le micro ni le moteur —
  fermer et rouvrir coûtait une à deux secondes de parole et « une fenêtre de
  transcription est déjà ouverte ». La machine change de fenêtre, l'audio
  continue, et l'historique rattache chaque segment à la sienne au drain.
- **Sous le verrou ⌃⌥M**, le geste ne ferme ni ne scinde la fenêtre tenue : un
  monologue ne se coupe pas parce qu'on trace pendant qu'on parle.
- **La permission micro au premier usage réel**, tirée de S72 par nécessité :
  l'autorisation accordée à un binaire lancé depuis le terminal appartient au
  processus responsable (Warp), pas à l'application lancée normalement.
  L'invite part à la première fenêtre de parole, jamais au lancement ; S72
  garde le doctor, l'épreuve `tccutil` et le refus.
- Les libellés du journal, pour la recette : `voix — prête`, `parole —
  fenêtre ouverte à MM:SS.d`, `parole — fenêtre enchaînée à …, l'audio
  continue`, `parole — segment → marque N (règle) : « … »`, `parole — segment
  → global (règle) : « … »`, `parole — fenêtre fermée à … · N segment(s) ·
  énergie max E`, `parole — commentaire général`, `verrou micro — activé,
  commentaire global jusqu'au déverrouillage`, `verrou micro — désactivé`,
  `éclair — la parole continue, publication à la fermeture de la fenêtre`,
  `éclair — publication : fenêtre de parole ouverte, sans parole entendue`.
- **Le `SpeechDetector` avale la parole en conditions réelles** : un monologue
  verrouillé de deux phrases — « parlé 2,5-3,9, 7,3-8,5 », l'audio des deux est
  arrivé au moteur, 1 773 tranches contiguës — n'en rendait qu'une, sans même
  un volatile pour la seconde ; sans le détecteur, les deux (2 segments, drain
  102 ms). Le banc ne le reproduit pas avec du bruit de synthèse : c'est le
  bruit d'un vrai micro qui le déclenche. Décision : retiré des modules par
  défaut, `--avec-detecteur` pour re-vérifier ; ADR-0012 porte la révision.
- **Le moteur date le premier mot au début de sa plage**, silence de tête
  compris — jusqu'à l'origine de l'audio pour la première énonciation : « Le »
  à 0,000 s pour une phrase dite à 3,0 s. Trop tôt de plusieurs secondes pour
  la règle du premier mot (ADR-0011) et hors du budget d'ancrage (seuil n°3).
  La première tranche PARLÉE de la plage, lue sur la carte d'énergie, corrige
  l'onset à ± 11 ms : « premier mot à 00:03.0 » quand l'énergie dit 3,0-4,6.
  Et la marge d'ouverture de 5 ms couvre l'arrondi 16 kHz / 90 kHz qui plaçait
  un segment entier en « aucune fenêtre ».
- Une leçon de méthode, payée une heure : un journal qui tronque à soixante
  caractères a fait chercher une finalisation perdue qui n'existait pas. Les
  textes s'écrivent entiers, ou avec leur longueur.

## 11. S66 — le drain dans la publication, mesuré en vivant le 29 août 2026

- **Le critère du lot tient** : phrase dite pendant que le micro écoute, `⌃⌥F`
  pressé aussitôt après — dans la fenêtre de finalisation de 1,3-2,7 s —, et la
  phrase ENTIÈRE est au rapport : « Le bouton validé est mal aligné avec le
  chant du code promo. » Le drain la rattrape en vol parce qu'il est attendu
  DANS le chemin ordonné de la publication, après l'extraction (avec laquelle
  il a couru en parallèle) et avant tout ce qui écrit le rapport.
- **`transcript.txt` est le cinquième chemin de `git status`**, en
  `-rw-r--r--` (un dépôt se partage), constaté sur un dépôt réel. Une session
  muette n'en a pas : rien à dire, pas de fichier — et le rendu ne mentionne
  jamais un fichier absent (amendement S46).
- **`⌃⌥F` ferme la fenêtre de parole immédiatement**, sans attendre les huit
  secondes de grâce : le raccourci de fin est un ordre, pas une suggestion.
  L'audio postérieur n'existe donc pas — couper au MILIEU d'une phrase perd
  légitimement la suite, ce n'est pas le drain qui la perd.
- **La durée de session s'arrête au raccourci**, plus à la fin de la
  publication : sans quoi le drain se serait ajouté à la durée annoncée.
- Honnêteté sur `--sans-drain` : l'interrupteur saute l'ATTENTE, mais la tâche
  de drain court quand même — la perte dépend alors d'une course que
  l'extraction rapide fait souvent gagner au drain. C'est un diagnostic, pas
  une preuve ; la preuve du contrat est dans `--boucle-test` (le cinquième
  chemin, le brut jamais édité, l'absence de fichier quand il n'y a rien).
