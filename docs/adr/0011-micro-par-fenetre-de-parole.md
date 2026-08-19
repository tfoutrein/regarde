---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 5
---

# ADR-0011 — Le micro est ouvert par fenêtre de parole liée au geste, jamais en continu

## Contexte

Regarde doit rattacher chaque commentaire parlé à la marque que l'utilisateur désignait en le
prononçant. La conception initiale répondait à ce besoin par le chemin le plus direct : micro
ouvert du début à la fin de la session, transcription continue, et rattachement de chaque segment
à la dernière marque posée. Cette option a un mérite réel qu'il faut reconnaître avant de
l'écarter : elle ne demande aucun geste pour parler. On commente à voix haute comme on le ferait
devant un collègue, la machine range ensuite.

Deux contraintes cadrent la reprise de ce choix. Le budget de temps d'abord : le mode éclair
(§ 2.1) vit ou meurt sur quelques secondes, et la fin de session est plafonnée à 20 s entre le
raccourci et le presse-papiers (§ 6.6). Le contexte d'usage ensuite : un développeur teste son
application dans un bureau ouvert, souvent avec une visioconférence en cours sur le même Mac. Le
modificateur ⌥⌘ maintenu est déjà acquis ([ADR-0006](0006-modificateur-option-commande.md)) et la
numérotation est définitive dès le `mouseDown`
([ADR-0013](0013-numerotation-definitive-au-mousedown.md)).

## Décision

Le micro est fermé par défaut. Une **fenêtre de parole** s'ouvre à la pression de ⌥⌘ et se ferme
8 s après le relâchement, prolongée tant que des résultats volatiles arrivent, avec un plafond dur
de 20 s. Tout segment dont le **premier mot** tombe dans une fenêtre appartient à la marque de
cette fenêtre. Le rattachement n'est donc plus inféré : il est déterministe par construction.

## Options envisagées

### Option A — Micro ouvert toute la session, rattachement à la dernière marque

- **Pour** : aucun geste requis pour parler ; on peut commenter avant, pendant ou longtemps après
  le tracé ; c'est le comportement qu'un utilisateur naïf attend d'un dictaphone.
- **Contre** : le micro capte 15 minutes de bureau — conversations de collègues, appels Teams,
  musique. Le point orange système reste allumé toute la session, ce qui est exact et donc
  inquiétant. Surtout, l'inférence exige un arbre de décision à quatre constantes réglables, cinq
  branches et trois niveaux de confiance, dont une règle d'horizon : une hésitation de dix
  secondes entre le tracé et le commentaire suffit à faire retomber le segment en confiance
  faible. Comme un segment de confiance faible déclenche l'écran de revue, cet écran s'ouvre
  **à chaque session**, pour 45 à 120 s (§ 6.6) — exactement le coût fixe que le produit prétend
  supprimer.

### Option B — Micro ouvert en continu, mais avec détection de voix pour filtrer l'ambiance

- **Pour** : conserverait le confort de l'option A en réduisant le bruit transcrit.
- **Contre** : un `SpeechDetector` distingue la parole du silence, pas la parole de l'utilisateur
  de celle d'un collègue ni du haut-parleur d'une visioconférence. Le point orange reste allumé.
  Et le problème principal n'est pas résolu : filtrer le bruit ne dit toujours pas à quelle marque
  rattacher une phrase, donc l'arbre de décision et la revue obligatoire restent.

### Option C — Fenêtre de parole liée au geste (retenue)

- **Pour** : rattachement déterministe, pas d'inférence, pas de niveau de confiance, pas de revue
  automatique. Le micro n'est ouvert que quelques secondes par observation. Le point orange
  s'allume au moment où l'utilisateur parle volontairement, ce qui le rend lisible.
- **Contre** : impose de tenir ⌥⌘ pour parler ; un commentaire qui vient à l'esprit après coup
  demande un geste supplémentaire.

## Justification

Ce qui a départagé n'est pas le confort d'usage mais l'arithmétique du produit. Le gain promis est
de l'ordre de la minute par observation ; un écran de revue systématique de 45 à 120 s le
consomme intégralement. Or cet écran n'est pas un défaut d'implémentation de l'option A, il en est
la conséquence nécessaire : dès qu'un rattachement est inféré, il peut être faux, donc il doit être
vérifiable, donc il faut le montrer. La seule façon d'éliminer la revue est d'éliminer l'inférence.

La fenêtre de parole y parvient parce que le geste porte déjà l'information. L'utilisateur tient
⌥⌘ pour tracer ; c'est le même geste, la même main, le même instant. Les cinq situations réelles
se couvrent alors sans aucune constante à régler :

| Situation | Règle | Trace |
|---|---|---|
| Parole pendant la fenêtre ouverte par le geste | rattachée à la marque du geste | `.fenetreDeParole` |
| Parole commencée avant le tracé, dans la même tenue de ⌥⌘ | même marque : l'utilisateur décrit puis pointe, c'est un seul geste | `.fenetreDeParole` |
| Segment final qui déborde après la fermeture de la fenêtre | rattaché si son premier mot tombait dans la fenêtre | `.debordement` |
| ⌥⌘ tenu > 400 ms sans mouvement ni tracé | commentaire global explicite, le HUD affiche « commentaire général » | `.gesteGlobal` |
| Verrouillage micro (⌃⌥M) pour un monologue long | commentaire global jusqu'au déverrouillage | `.gesteGlobal` |

Deux compléments ferment les cas restants. La **réaffectation sans panneau** : pendant qu'une
fenêtre est ouverte, `⌥⌘ + chiffre` réaffecte le segment en cours à la marque N, `⌥⌘ + 0` le
bascule en global, et le badge de la marque cible s'illumine sur le calque, à sa position — là où
le regard est déjà. C'est la correction du défaut de la prévention initiale, qui affichait l'état
de rattachement dans un HUD déporté que personne ne regarde en testant. Le **verrouillage micro**
couvre le monologue long sans réintroduire le micro permanent : il est explicite, signalé par un
bandeau permanent, et produit du commentaire global.

Enfin, la fenêtre est fermée d'office, sans exception, quand `IsSecureEventInputEnabled()` passe à
vrai — saisie d'un mot de passe — et en état `suspended` (veille, écran verrouillé, changement
d'utilisateur, Mission Control). La conception initiale laissait le moteur audio tourner : un
déjeuner écran verrouillé devenait un enregistrement clandestin.

## Conséquences

- **Positives** : plus aucune notion de confiance de rattachement ; la revue de fin de session
  quitte le chemin nominal et ne s'ouvre plus jamais seule ; le critère de réussite du lot 5
  devient binaire et vérifiable (6 observations, 6 bonnes marques) ; le micro n'est ouvert que
  quelques dizaines de secondes sur une session de dix minutes.
- **Négatives — le prix à payer, assumé** : on ne peut plus commenter sans avoir le modificateur
  enfoncé. Un commentaire qui vient à l'esprit trente secondes après le geste exige un nouveau
  geste — rappuyer ⌥⌘, éventuellement retracer ou passer par le commentaire global. Le premier
  mot prononcé juste avant la pression de ⌥⌘ est perdu, sans rattrapage possible puisqu'aucun
  tampon audio ne précède l'ouverture du moteur. Et le démarrage d'`AVAudioEngine` à chaque
  fenêtre coûte une latence de mise en route au lieu d'être payé une fois pour la session.
- **Ce que ça ferme** : le mode « dictaphone de recette », où l'on parlerait librement pendant
  toute une passe en laissant l'outil découper. Il faudrait rouvrir l'inférence et la revue pour
  l'offrir. Ferme aussi tout usage mains libres du produit.

## Signal de révision

Si l'usage réel montre que l'auteur veut souvent parler hors fenêtre : commentaires globaux
anormalement nombreux dans les manifestes, recours fréquent au verrouillage micro pour un simple
retour d'une phrase, ou observations reformulées une seconde fois parce que la première est partie
avant la pression de ⌥⌘. Un tel constat, mesurable sur deux semaines de sessions réelles,
justifierait d'étudier une fenêtre rétroactive courte plutôt qu'un retour au micro permanent.

## Références

- Spécification § 3.5 (règle de rattachement), § 6.6 (revue hors chemin nominal), § 7.2 (cycle de
  vie du micro), § 10.4 (micro et vie privée), § 11.3 lot 5.
- [ADR-0006](0006-modificateur-option-commande.md) — modificateur ⌥⌘ maintenu.
- [ADR-0012](0012-speechanalyzer-avec-speechdetector.md) — chaîne de transcription locale.
- [ADR-0013](0013-numerotation-definitive-au-mousedown.md) — numérotation définitive.
- [ADR-0020](0020-confidentialite-capture-continue.md) — mesures de confidentialité.
