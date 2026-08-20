# Regarde

> Montre à ton IA ce que tu vois, en parlant, sans quitter ton application.

Tu testes l’application que ton agent IA vient d’écrire. Quelque chose cloche. Tu maintiens
une touche, tu entoures la zone, tu dis pourquoi à voix haute, et l’agent reçoit un rapport
où **chaque commentaire est collé au bon pixel, au bon instant**.

Pas de capture à recadrer. Pas de contexte à retaper. Plus de « le bouton en haut à droite,
tu vois ? ».

> **État : conception terminée, développement à peine commencé.** Il n’y a pas encore
> d’application utilisable, seulement un prototype qui valide le geste. Ce dépôt est
> aujourd’hui surtout un travail de conception : une spécification, 21 décisions
> d’architecture et un plan. Le détail est [plus bas](#état-réel-du-projet).

---

## Le problème

Développer avec une IA, c’est passer sa journée à décrire des choses qu’on a sous les yeux.

La capture d’écran n’est pas le goulot d’étranglement : `⌘⇧4` fait le travail, et
CleanShot ou Shottr le font mieux. Le coût est ailleurs : dans le **dernier mètre**.
Cadrer, coller dans le chat, puis **taper au clavier ce que l’image est censée montrer**,
parce qu’une image ne porte pas l’intention. De l’ordre de quinze à vingt secondes de frappe
par observation, pendant lesquelles on n’est plus en train de tester.

Et sur tout ce qui bouge (une transition, un état de survol, un total qui se rafraîchit
400 ms trop tard), la capture figée ne dit rien du tout.

## Comment ça marche

```
⌃⌥S          Session ouverte. L'écran est enregistré en continu en arrière-plan,
             la transcription est locale. Rien ne bouge à l'écran, aucun panneau.

             Tu testes normalement. Tu cliques, tu navigues, l'app s'anime.

⌥⌘ + glisser Une flèche numérotée ① apparaît par-dessus. Tu relâches, tu recliques
             dans l'app — elle n'a jamais perdu le focus ni cessé de tourner.

  « ce bouton devrait passer en vert au survol »      → rattaché à ①

⌥⌘ + glisser Un cadre ②.  « et le libellé déborde de deux pixels »   → rattaché à ②

  « globalement les transitions sont trop lentes »    → commentaire général

⌃⌥F          Session fermée. Pour chaque marque, la frame de SON instant est extraite,
             les repères y sont gravés, le rapport part dans ton projet.
             Le presse-papiers contient déjà la phrase à coller.

⌘V ⏎         L'agent lit, voit les repères sur les pixels exacts, et corrige.
```

Pour une observation isolée, un **mode éclair** fait la même chose en huit secondes, sans
ouvrir de session.

## Ce qui le distingue d’une capture collée dans un chat

**L’intention est capturée au moment du geste, pas reconstruite après.** La parole est
transcrite et rattachée à la marque *par construction*, pas par une heuristique appliquée
après coup. « Le bouton touche le bord de la carte, il manque du padding à droite » est
autrement plus actionnable qu’une image de ce bouton.

**L’instant désigné est exact.** L’enregistrement démarre **avant** la marque. La frame
envoyée à l’agent est celle qui était affichée quand tu as appuyé, pas celle qui traînait
à l’écran quand tu as fini d’écrire ton message. Sur une interface animée, c’est la
différence entre un bug capturé et un bug à reproduire. Cela permet aussi de commenter
**rétroactivement** : « attends, le truc d’il y a trois
secondes » reste exploitable, puisque les images sont déjà dans le tampon.

**Le coût en jetons est maîtrisé et annoncé.** Le canal principal vers l’agent est le texte
et le chemin de fichier, pas l’image encodée dans la réponse. D’après la formule du § 9 de la
spécification, une session de six observations reviendrait à 2 000 à 4 500 jetons d’entrée
au lieu de 30 000, et le rapport annonce à l’agent le coût de chaque image pour qu’il
arbitre lui-même. Ces chiffres sont des estimations de conception : le code qui les
produira appartient au lot 4, pas encore écrit.

**Universel par construction.** Le noyau ne connaît que des pixels et de la géométrie :
application web, application native, fenêtre de terminal, simulateur iOS, script en cours
d’exécution. Des greffons optionnels enrichissent le contexte quand ils reconnaissent la
fenêtre, mais leur absence ne dégrade jamais rien.

**Agnostique du modèle.** Ni Claude ni GPT ne lisent de vidéo. Le format transmis est donc
une séquence d’images horodatées, jamais un fichier vidéo. N’importe quel agent capable de
lire une image et du texte peut exploiter un rapport.

**Local.** La transcription vocale ne quitte pas la machine, et l’application n’ouvre
aucune connexion sortante.

Le tout sans rupture de flux. L’application testée garde le focus et continue de tourner
pendant l’annotation, et il n’y a aucun mode à mémoriser : on maintient une touche, on
trace, on relâche.

## macOS d’abord, Windows et Linux ensuite

**Prérequis actuels** : macOS 26 (Tahoe) ou supérieur, Apple Silicon.

On commence par macOS parce que c’est la machine sur laquelle l’outil est écrit, et parce
qu’une seule plateforme suffit à répondre à la question qui compte : est-ce que ce mode de
travail fait vraiment gagner du temps ? Éprouver le concept sur un poste réel vaut mieux que
trois portages d’une idée non validée.

Windows et Linux viendront. Ce ne sera pas gratuit : le noyau repose sur des API propres à
la plateforme, `ScreenCaptureKit` pour la capture, `CGEventTap` pour arbitrer les événements
souris, `SpeechAnalyzer` pour la transcription locale, `NSPanel` pour le calque. Chacune a
son équivalent ailleurs, avec ses propres pièges.

**Cette couche est la moins précieuse du projet.** Ce qui a coûté le travail de conception
se porte tel quel :

| Portable en l’état | À réécrire par plateforme |
|---|---|
| Format des artefacts (Markdown, JSON, PNG) | Capture d’écran et encodage |
| Outils MCP et leur contrat | Calque d’annotation |
| Modèle de données et règle d’ancrage | Arbitrage des événements d’entrée |
| Stratégie de budget de jetons | Transcription locale |
| Rendu du rapport | Autorisations et intégration système |

La frontière entre les deux est tenue nette dès maintenant, précisément pour que le portage
reste un chantier délimité plutôt qu’une reprise à zéro. Voir
[ADR-0001](docs/adr/0001-application-macos-native-swift.md).

## Limites, connues et assumées

| | |
|---|---|
| **Rien n’est utilisable aujourd’hui** | Le prototype valide le geste, rien d’autre : pas de numérotation, pas de voix, pas de rapport, pas d’intégration agent. |
| **L'icône de barre de menus n'est pas garantie** | Sur un portable à encoche dont la barre est chargée, macOS place l'icône **sous l'encoche** : elle existe, le système la déclare visible, et elle est introuvable. Constaté sur la machine de développement. C'est la raison d'être des raccourcis Carbon : **⌃⌥S ouvre le diagnostic sans dépendre ni de la barre de menus ni d'aucune autorisation.** L'application le détecte et le signale. |
| **Quatre autorisations système** | Enregistrement de l’écran, Surveillance de la saisie, Accessibilité, Micro. Les deux du milieu sont **obligatoires** : sans elles, rien ne fonctionne. macOS redemande par ailleurs l’autorisation de capture d’écran chaque mois. |
| **Pas encore distribuable** | La notarisation exige un compte Apple Developer, qui n'est pas ouvert à ce jour. L'application se construit et s'utilise en local avec un certificat auto-signé ; elle ne s'installe pas encore sur une autre machine sans avertissement Gatekeeper. |
| **Hors Mac App Store** | L’Accessibilité et un tap qui consomme des événements sont incompatibles avec le bac à sable et avec la revue App Store. Distribution en Developer ID notarisé. |
| **Il reste un geste vers l’agent** | MCP fonctionne en *pull* : rien ne permet de réveiller Claude Code ou Cursor. L’outil réduit ce geste à un `⌘V ⏎`, il ne le supprime pas. |
| **La parole se paie** | En open space ou en visioconférence, on ne commente pas à voix haute. Une palette d’intentions et une saisie clavier couvrent le mode silencieux, moins finement. |
| **Le français technique résiste** | La transcription locale confond « padding » et « pratique ». Un lexique déterministe corrige les cas connus, un agent rétablit le reste code en main, mais l’erreur *plausible* reste un risque ouvert. |
| **Projet personnel, du soir** | Environ 45 jours-homme pour le produit complet. Deux points d’arrêt sont prévus, et l’abandon après le second est présenté comme un résultat acceptable, pas comme un échec. |

## État réel du projet

| Document | Contenu | État |
|---|---|---|
| [`docs/SPECIFICATION.md`](docs/SPECIFICATION.md) | Parcours, modèle d’ancrage temporel, architecture, format des artefacts, risques | complet, 1 100 lignes |
| [`docs/adr/`](docs/adr/README.md) | 21 décisions d’architecture, avec les options écartées et le prix payé | complet |
| [`docs/PLAN-DE-DEVELOPPEMENT.md`](docs/PLAN-DE-DEVELOPPEMENT.md) | Neuf lots, deux GO/NO-GO, calibrage en travail fractionné | complet |
| [`prototypes/lot0/`](prototypes/lot0/) | Prototype de réduction de risque : le geste, et rien d’autre | **en cours de validation** |

Le lot 0 est le prototype qui décide de la suite du projet. Il ne produit rien qu’on puisse
montrer, son seul but est d’établir que le geste fonctionne : le calque capture les
événements sans que l’application testée perde le focus, continue de s’animer, et sans
qu’aucun événement orphelin ne lui parvienne. Quinze critères, dont un fatal. Son état est
consigné dans [`RESULTATS.md`](prototypes/lot0/RESULTATS.md).

Le code du lot 0 sera **jeté**. Ce qui survit, ce sont les mesures et le journal des
surprises qu’il produit.

## Méthode

La conception a été menée avec une IA, puis soumise à des passes de critique adversariale :
lentilles indépendantes, chaque constat passé à un réfutateur chargé de le démolir. Les
constats survivants ont été intégrés dans la conception elle-même, pas relégués en annexe.

Le prototype a subi le même traitement avant sa première exécution : 48 constats bruts,
18 confirmés, 12 corrections. Trois défauts étaient bloquants, dont un fatal, le calque
rendait à l’application testée le milieu d’un clic dont elle n’avait pas vu le début. La
revue est archivée dans [`prototypes/lot0/revue/`](prototypes/lot0/revue/), avec sa section
« ce qui a été vérifié et tient », qui vaut autant que la liste des corrections.

Deux défauts lui ont malgré tout échappé et n’ont été trouvés qu’en tapant sur un vrai
clavier : un raccourci codé sur un code de touche physique, qui migrait sur une autre touche
en AZERTY, et une sonde de diagnostic qui annonçait « tout va bien » en testant la mauvaise
chose. C’est précisément la raison d’être d’un prototype de risque.

## Essayer le prototype

```bash
git clone https://github.com/tfoutrein/regarde.git
cd regarde/prototypes/lot0
./Tools/make-cert.sh    # une fois — lis l'avertissement ci-dessous d'abord
./Tools/start.sh        # auto-test, build signé, lancement, état
```

> [ !WARNING]
> **`make-cert.sh` demande `sudo` et modifie ton trousseau système.** Il crée un certificat
> auto-signé nommé « Regarde Dev », puis l’ajoute au trousseau **système** comme racine
> approuvée pour la signature de code, et autorise `codesign` à utiliser la clé sans invite.
>
> C’est nécessaire parce que TCC identifie une application par son identité de signature :
> avec une signature ad hoc, elle change à chaque build et les autorisations d’Accessibilité
> sont perdues à chaque fois. Mais ce n’est pas anodin, et tu dois le décider en connaissance
> de cause. L’alternative manuelle par Trousseau d’accès est décrite dans
> [`prototypes/lot0/README.md`](prototypes/lot0/README.md).
>
> Pour retirer le certificat ensuite :
> ```bash
> sudo security delete-certificate -c "Regarde Dev" /Library/Keychains/System.keychain
> security delete-certificate -c "Regarde Dev" ~/Library/Keychains/login.keychain-db
> ```

macOS demandera **Surveillance de la saisie** et **Accessibilité**. Sans elles,
`CGEvent.tapCreate` renvoie `nil`, sans erreur, sans exception, sans le moindre indice.
C’est pourquoi le rapport de permissions s’imprime avant toute autre chose.

Le protocole de test est dans [`PROTOCOLE.md`](prototypes/lot0/PROTOCOLE.md). L’auto-test
de la logique d’arbitrage tourne sans aucune permission :

```bash
swift build && ./.build/debug/Regarde0 --selftest
```

## Licence

MIT, voir [`LICENSE`](LICENSE).
