# Regarde — Spécification du MVP macOS

**Version 1.0 — 19 août 2026**
Document produit par une conception assistée : cinq sondes de faisabilité, trois volets de
conception, deux passes de critique adversariale, puis consolidation. Les critiques sont
intégrées dans le corps du texte, pas reléguées en annexe.
Cible : macOS 26.0+ (Tahoe), Apple Silicon. Distribution Developer ID notarisée, hors App Sandbox.
Bundle : `dev.tfoutrein.regarde`. Binaires : `Regarde.app`, sidecar `regarde-mcp`.

---

## 1. Le problème et la promesse

Un développeur teste l'application que son agent IA vient d'écrire. Il voit six choses qui clochent. Pour chacune, il doit aujourd'hui : cadrer une capture d'écran, la coller dans le chat, puis **taper au clavier** ce qu'elle est censée montrer — parce qu'une image ne porte pas l'intention. Quinze à vingt secondes de frappe par observation, pendant lesquelles il n'est plus en train de tester. Et son agent reçoit six messages désordonnés sans horodatage commun.

Regarde remplace la frappe par la parole et le cadrage par un geste. Le développeur maintient un modificateur, entoure la zone, commente à voix haute, relâche, et continue à piloter son application — qui n'a ni perdu le focus ni cessé de s'animer. À la fin, un rapport structuré est écrit dans le projet et une phrase est dans le presse-papiers.

Trois propriétés distinguent l'outil d'une capture collée dans un chat :

**L'intention est capturée au moment du geste, pas reconstruite après.** La parole est transcrite localement et rattachée à la marque par construction, pas par une heuristique a posteriori. « Le bouton touche le bord de la carte, il manque du padding à droite » est plus actionnable qu'une image de ce bouton.

**L'instant désigné est exact.** La frame envoyée à l'agent est celle qui était affichée au `mouseDown`, pas celle qui se trouvait à l'écran quand l'utilisateur a fini de rédiger son message. Sur une application animée ou un état transitoire, c'est la différence entre un bug capturé et un bug à reproduire.

**Le coût en jetons est maîtrisé et annoncé.** Le canal principal vers l'agent est le texte et le chemin de fichier absolu, pas l'image inline. Une session de six observations coûte 2 000 à 4 500 jetons d'entrée au lieu de 30 000.

Ce que l'outil **ne** promet pas : il ne supprime pas les allers-retours avec l'agent, il les **groupe**. La contrepartie est un diff plus large à relire ; le rapport suggère un ordre de traitement et un commit par marque pour la limiter.

---

## 2. Le parcours utilisateur de référence

### 2.1 Mode éclair — une observation, le mode majoritaire

**La cible suit, et une observation peut en mélanger plusieurs.** Hors session, la fenêtre cible est celle de l'application au premier plan, réévaluée en continu — c'est ce qui permet à ⌥⌘ d'armer sans rien ouvrir. Un ⌥⌘-clic hors de cette fenêtre ne trace donc rien : il active l'application visée, qui devient la cible, et le geste suivant y trace.

Conséquence, observée en usage réel : une rafale peut porter sur deux applications sans que l'utilisateur s'en aperçoive — cinq marques réparties entre un navigateur et le Finder dans un même dossier. **Arbitrage retenu :** la rafale n'est pas coupée, chaque marque retient l'application qu'elle annote, et la publication signale le mélange. Couper à chaque changement d'application aurait scindé en deux les observations qui traversent volontairement deux fenêtres ; figer la cible sur la première marque aurait rendu le mode éclair muet dès qu'on change de fenêtre, sans rien dire.

C'est le mode qui doit battre `⌘⇧4`. Il n'ouvre pas de session, ne produit pas d'état, n'ouvre aucun panneau.

| t | Ce qui se passe |
|---|---|
| 0,0 s | Le développeur voit que le total du panier ne se rafraîchit pas. Il maintient **⌥⌘**. Le micro s'ouvre (point orange), le calque est ordonné à l'écran, le badge `1` apparaît sous le curseur. |
| 0,3 s | Il trace un cadre autour de la ligne « Total TTC » en disant « le total il bouge pas quand je change la quantité, il se met à jour seulement au blur ». |
| 3,5 s | Il relâche ⌥⌘. Le calque disparaît. La fenêtre de parole reste ouverte 8 s, prolongée tant que des résultats volatiles arrivent (plafond 20 s). |
| 4,8 s | Il a fini de parler. |
| 7,1 s | Le dernier résultat final tombe. La fenêtre se ferme, le micro se ferme. |
| 7,3 s | Le recadrage est gravé, le rapport écrit, la phrase déposée au presse-papiers. Un bandeau discret : « feedback #43 · 1 marque · 513 jetons · copié · ⏎ Envoyer à Claude Code ». |
| 8,0 s | Il presse ⏎. Regarde active la fenêtre de Claude Code détectée et injecte le texte. |

Coût total : **8 secondes**, dont zéro de frappe. Le même retour en `⌘⇧4` : cadrer 4 s, coller 2 s, taper 18 s, soit 24 s.

### 2.2 Mode session — une passe de recette

**14 h 32 min 00 s.** ⌃⌥S (raccourci d'ouverture, distinct du raccourci de fin). `preflight` : les permissions sont vérifiées en 40 ms, elles sont bonnes. Le pré-roll tournait déjà : les 22 dernières secondes d'écran sont conservées (20 s garanties, jusqu'à 30 s selon la rotation des segments) et deviennent le début de la session. Le `SCStream` bascule en pleine résolution. L'icône de la barre de menus passe en rouge avec un chronomètre. Le HUD s'affiche en bas à droite, au niveau `.statusBar` : projet détecté `shop-front` (badge vert « session Claude Code vivante · pid 20378 »), micro `MacBook Pro Microphone`, 0 marque.

**14 h 32 min 21 s.** Il maintient ⌥⌘, trace un cadre autour du bouton « Valider la commande » en disant « le bouton touche le bord de la carte, il manque du padding à droite ». Il relâche. Le badge `1` reste dessiné sur le calque, il pulse tant que la fenêtre de parole est ouverte. Le calque disparaît, l'application testée n'a jamais perdu le focus : le curseur clignote toujours dans son champ de saisie.

**14 h 33 min 33 s.** Il valide un code promo. Un badge d'erreur apparaît puis un toast disparaît en 800 ms. Il maintient ⌥⌘ et presse **3** : marque rétroactive à T−3 s. L'instantané est pris dans l'anneau de frames, le toast y est. Il trace une flèche vers le champ et commente.

**14 h 34 min 24 s.** Marque 3 sur le total. En parlant, il se rend compte qu'il commente en fait la marque 1 : il presse **⌥⌘+1**, le segment en cours bascule sur la marque 1, le badge `1` s'illumine sur le calque à l'endroit de la marque. Aucun panneau, aucune interruption.

**14 h 35 min 00 s.** ⌃⌥F (raccourci de fin). `finalizing` : arrêt du flux, drain de la transcription, finalisation par segment, extraction groupée, gravure. **1,4 s.** Bandeau de confirmation, 8 s à l'écran :

```
feedback #42 · 3 marques · 1 commentaire global · 1 533 jetons · copié
[⏎ Envoyer à Claude Code]  [R Revoir]  [⌫ Annuler]  [V Voir les images]
```

Il ne revoit pas. Il presse ⏎.

**14 h 35 min 12 s.** Claude Code lit `get_feedback(number: 42)`, obtient 1 610 jetons de texte, charge un seul recadrage pour la marque 2, applique les corrections, appelle `resolve_feedback`. Le HUD de Regarde affiche la note de résolution dans son historique.

**Le lendemain.** Il reteste. Menu de la barre de menus → « Reprendre le feedback #42 ». La session s'ouvre pré-chargée avec les trois marques positionnées en coordonnées normalisées. ⌥⌘-clic sur la marque 1 : « corrigé ». Sur la marque 3 : « toujours KO » + commentaire vocal. Le rapport #43 s'ouvre sur « Suite du #42 ». L'agent sait ce qu'il a déjà tenté.

### 2.3 Où la critique du coût fixe est juste, et où elle ne l'est pas

La critique adversariale chiffre le mode session à 60–135 s pour deux observations et conclut que l'outil perd contre `⌘⇧4`. Le chiffrage est juste sur le principe et faux sur le détail : il inclut 45 à 120 s de revue de fin de session, qui **est supprimée du chemin nominal** par cette spécification (§ 6.6). Reste le coût fixe réel de la session : ~2 s à l'ouverture, ~1,5 s à la fermeture, 1 clic de livraison. Le point de croisement tombe à **2 observations**, pas à 5. Et pour une observation isolée, le mode éclair du § 2.1 est structurellement plus rapide que la capture d'écran.

---

## 3. Modèle de données et ancrage

### 3.1 Les trois horloges, et la seule qui compte

Trois producteurs d'événements, trois bases de temps natives, une horloge maîtresse : **`CMClockGetHostTimeClock()`**. Elle existe avant tout `SCStream`, survit à son arrêt, et partage sa base avec `CGEvent.timestamp` et `AVAudioTime.hostTime`.

| Producteur | Base native | Conversion vers `SessionTime` |
|---|---|---|
| Frames vidéo | PTS du `CMSampleBuffer` sur `SCStream.synchronizationClock` | `CMSyncConvertTime(pts, from: sync, to: master)` **par échantillon**, pas un offset figé |
| Marques | `CGEvent.timestamp` (`mach_absolute_time` de l'événement matériel) | `CMClockMakeHostTimeFromSystemUnits` |
| Parole | `AVAudioTime.hostTime` du tap micro **moins la latence d'entrée mesurée** | idem, puis injecté dans le moteur via `AnalyzerInput.bufferStartTime` |

**Quatre corrections d'horloge par rapport à une implémentation naïve :**

1. **Pas d'offset scalaire figé.** L'esquisse initiale échantillonnait l'écart une fois au démarrage du flux. `CMSyncConvertTime` par échantillon coûte quelques nanosecondes et supprime la question de la dérive.
2. **`synchronizationClock` vaut `nil` avant `startCapture()`.** Une marque posée pendant `arming` est étiquetée `preRoll` et forcée sur la source RAM, sans seek, jamais horodatée sur un offset inventé.
3. **`CGEvent.timestamp` peut valoir 0** sur les événements synthétiques (Karabiner, BetterTouchTool, pilotes Logitech/Razer, Universal Control, partage d'écran). Validation obligatoire : le timestamp doit tomber dans `[t0, now + 50 ms]`, sinon repli sur `now()` avec trace. Sans cette validation, l'invariant de monotonie rejette silencieusement des marques chez tout utilisateur de ces outils.
4. **La veille arrête `mach_absolute_time`.** Les trois producteurs restent cohérents entre eux, mais les `Interruption` sont datées **aussi** sur `mach_continuous_time` pour que le rapport annonce une durée murale correcte.

```swift
struct SessionTime: Hashable, Comparable, Codable {
    static let scale: CMTimeScale = 90_000
    let raw: CMTime
    var seconds: Double { raw.seconds }
    init(seconds: Double) { raw = CMTime(seconds: seconds, preferredTimescale: Self.scale) }
    init(_ t: CMTime) { raw = CMTimeConvertScale(t, timescale: Self.scale, method: .roundHalfAwayFromZero) }
    static func < (a: Self, b: Self) -> Bool { a.raw < b.raw }
}

final class SessionClock: @unchecked Sendable {
    private let master = CMClockGetHostTimeClock()
    private var origin: CMTime            // MUTABLE : posee au lancement, RECALEE a l'entree en arming
    private var originContinuous: UInt64  // mach_continuous_time, pour la duree murale

    func now() -> SessionTime { SessionTime(CMTimeSubtract(CMClockGetTime(master), origin)) }

    /// CGEvent.timestamp / AVAudioTime.hostTime. Retourne nil si le tick est aberrant.
    func fromHost(_ ticks: UInt64) -> SessionTime? {
        guard ticks != 0 else { return nil }
        let t = CMClockMakeHostTimeFromSystemUnits(ticks)
        let s = SessionTime(CMTimeSubtract(t, origin))
        guard s.seconds >= -0.001, s.seconds <= now().seconds + 0.05 else { return nil }
        return s
    }

    /// L'horloge du flux a un PORTEUR NOMME, et n'est pas passee en parametre.
    /// `SCStream.synchronizationClock` vaut nil avant startCapture() : la laisser
    /// implicite invite a inventer un offset pendant `arming`, ce que la correction
    /// 2 ci-dessus interdit. `fromStream` rend nil tant qu'aucune n'est adoptee.
    private var sync: CMClock?
    func adopterHorlogeDeFlux(_ c: CMClock, id: String)
    func fromStream(_ pts: CMTime) -> SessionTime? {
        guard let sync else { return nil }
        return SessionTime(CMTimeSubtract(CMSyncConvertTime(pts, from: sync, to: master), origin))
    }
    /// Inverse de now(), dont assetTime() a besoin.
    func pts(for t: SessionTime) -> CMTime { CMTimeAdd(origin, t.raw) }
    /// Duree MURALE, veille comprise.
    func wallSeconds() -> Double
}
```

**Correction apportee en S30 : l'origine est MUTABLE et se recale a l'entree en
`arming`.** L'esquisse la posait dans `init()`, donc au lancement de l'application.
Une session ouverte six heures plus tard aurait donne a ses marques des
`SessionTime` de six heures, et `assetTime()` les aurait toutes clampees hors
bornes — sans qu'une seule image ne soit extraite, et sans le moindre message. Le
journal aurait dit « 6 marques », le dossier aurait ete vide.

### 3.2 Le temps de l'asset n'est pas le temps de session

**C'est le défaut le plus grave de la conception initiale et la première chose à implémenter correctement.** `AVAssetWriter.startSession(atSourceTime:)` définit quel PTS devient le temps 0 du fichier. Demander à `AVAssetImageGenerator` la frame à `SessionTime` produit un décalage constant égal à `PTS_première_frame − t0`, soit 0,3 à 3 s selon le délai de démarrage du `SCStream` et le temps que met l'écran à changer (ScreenCaptureKit ne livre que sur changement). Le décalage est invisible sur écran statique et systématique sur écran animé, c'est-à-dire exactement dans le cas d'usage qui justifie le produit.

```swift
struct CaptureSegment: Codable {
    let id: CaptureSegmentID
    let displayID: CGDirectDisplayID
    let fileURL: URL
    // `CMTime` n'est pas Codable, et l'encoder en secondes flottantes perdrait la
    // precision au tick sur laquelle se joue tout l'appariement : on encode le
    // couple valeur/echelle. Nil tant qu'aucun echantillon n'a ete ecrit — cas
    // LEGITIME d'un ecran strictement fige, que S32 verifie nommement.
    var firstSamplePTS: CMTimeCodable?   // PTS passe a startSession(atSourceTime:)
    var lastSamplePTS: CMTimeCodable?
    // Identite de l'horloge du flux qui a produit ces PTS. Deux flux ont deux
    // synchronizationClock, et leurs PTS ne sont PAS comparables : sans elle, un
    // decalage silencieux du meme ordre que B1, diagnostique comme lui.
    var clockID: String?
    let pixelSize: CGSize              // dimensions configurees du buffer
    var pointPixelScale: Double
    let start: SessionTime
    var end: SessionTime?
    var stopReason: StopReason?

    /// Temps a demander a AVAssetImageGenerator, borne sur la duree reelle de l'asset.
    func assetTime(for t: SessionTime, clock: SessionClock) -> CMTime? {
        guard let first = firstSamplePTS, let last = lastSamplePTS else { return nil }
        let target = CMTimeSubtract(clock.pts(for: t), first)
        let duration = CMTimeSubtract(last, first)
        if target < .zero || target > duration { return nil }   // clampage journalise
        return target
    }
}
```

Le plan de burst `[t − 0,8, t, t + 0,4]` est systématiquement clampé sur `[0, duration]` ; un temps hors bornes ne produit pas de frame, il produit une trace.

**`CaptureSegmentID` est OPTIONNEL sur une marque**, et c'est un cas légitime plutôt qu'une lacune : le mode éclair — le mode majoritaire — n'ouvre ni session, ni flux, ni segment. Sa marque est servie par le filet RAM et n'a aucun segment auquel se rapporter. Le rendre obligatoire aurait forcé un segment factice, c'est-à-dire un mensonge dans le manifeste. La marque porte à la place sa `provenance d'image` — `segment`, `preRoll` (résolution réduite), `filetRAM` ou `aucune` — parce que les quatre n'ont pas la même valeur de preuve et que le rapport doit pouvoir le dire.

### 3.3 Trois systèmes de coordonnées, une seule fonction de conversion

| Espace | Origine | Unité |
|---|---|---|
| `CGEvent.location` | haut-gauche de l'écran principal, global | points |
| Cocoa / `NSScreen` | bas-gauche | points |
| Buffer ScreenCaptureKit | haut-gauche du `contentRect` **de la frame** | pixels |

**Correction par rapport à la conception initiale :** la géométrie normalisée n'est pas relative au `contentRect` du filtre (constant) mais au `contentRect` **de la frame retenue**, lu dans les attachements `SCStreamFrameInfo.contentRect` / `.scaleFactor` / `.contentScale`. ScreenCaptureKit publie ces attachements par frame précisément parce que le contenu peut être boîté dans le buffer : l'arrondi `& ~1` des dimensions casse le ratio, `scalesToFit = false` centre plutôt qu'il n'étire. Ignorer cela produit des recadrages décalés d'une marge constante et des bandes noires sur les bords, diagnostiqués à tort comme un bug d'échelle Retina.

`FrameRef` porte donc le `contentRect` et le `scaleFactor` effectifs de sa frame. Toute marque porte son `CaptureSegmentID` — sans lui, après un `-3821` et une réouverture de segment aux dimensions différentes, les pixels des marques antérieures ne sont plus interprétables.

Deux cas refusés proprement, non silencieusement : **écran en rotation portrait** (largeur et hauteur inversées entre `CGDisplayBounds` et le buffer) et **recopie vidéo** (`SCShareableContent` remonte deux `SCDisplay` pour la même surface ; filtrer par `CGDisplayIsInMirrorSet` / `CGDisplayMirrorsDisplay`, sinon la marque atterrit sur le mauvais `displayID`).

### 3.4 Types du modèle

```swift
struct NormPoint: Codable, Hashable { var x, y: Double }   // 0..1 dans le contentRect de la frame
struct NormRect:  Codable, Hashable { var x, y, w, h: Double }

enum MarkShape: Codable {
    case point(NormPoint)
    case arrow(from: NormPoint, to: NormPoint)
    case rect(NormRect)
    case highlight(NormRect)
    case freehand([NormPoint])         // decime, max 200 points
    case text(NormPoint, String)       // saisie clavier, lot 5
}

enum MarkIntent: String, Codable {     // palette muette, ⌥⌘ + 1..6
    case alignement, erreur, etatManquant, lenteur, texte, neMarchePas
}

struct Mark: Codable, Identifiable {
    let id: UUID
    let number: Int                    // ATTRIBUE au mouseDown, JAMAIS renumerote
    let t: SessionTime                 // instant designe (mouseDown, ou T-N pour une marque retroactive)
    let tEnd: SessionTime
    let displayID: CGDirectDisplayID
    let captureSegment: CaptureSegmentID
    let shape: MarkShape
    let bbox: NormRect
    var intents: [MarkIntent] = []
    let motion: MotionSample
    let isRetroactive: Bool
    var contexts: [ContextFragment] = []
    var frames: [FrameRef] = []
    var isDeleted: Bool = false        // laisse un trou dans la numerotation
}

struct Word: Codable { let text: String; let start, end: SessionTime; let confidence: Double? }

struct SpeechSegment: Codable, Identifiable {
    let id: UUID
    let words: [Word]
    var text: String                   // editable en revue
    let rawText: String                // brut, jamais modifie
    var onset: SessionTime { words.first?.start ?? engineRange.start }
    let engineRange: SessionRange      // diagnostic uniquement
    var attachment: Attachment
}

enum Attachment: Codable, Equatable {
    case mark(UUID, rule: AttachRule)
    case global(rule: AttachRule)
    case manual(UUID?)                 // ecrase tout, jamais recalcule
}
enum AttachRule: String, Codable { case fenetreDeParole, debordement, gesteGlobal, aucuneFenetre }
```

### 3.5 La règle de rattachement : le micro suit le geste

**Décision structurante, corrigée par rapport à la conception initiale : le micro n'est pas ouvert en continu pendant la session.** Il est ouvert par **fenêtre de parole**, liée au geste.

Une fenêtre de parole s'ouvre quand ⌥⌘ est pressé et se ferme 8 secondes après le relâchement, prolongée tant que des résultats volatiles arrivent, avec un plafond dur de 20 s. Tout segment dont le premier mot tombe dans une fenêtre appartient **par construction** à la marque de cette fenêtre.

Ce que cette décision supprime :
- le bruit ambiant, les conversations de collègues et les visioconférences transcrits pendant 15 minutes ;
- le point orange allumé en permanence ;
- l'arbre de décision à quatre constantes, cinq branches et trois niveaux de confiance de la conception initiale ;
- l'écran de revue obligatoire qui en découlait.

Ce qui reste, et qui suffit :

| Situation | Règle | Trace |
|---|---|---|
| Parole pendant la fenêtre ouverte par le geste | rattachée à la marque du geste | `.fenetreDeParole` |
| Parole commencée avant le tracé, dans la même tenue de ⌥⌘ | même marque (l'utilisateur décrit puis pointe : c'est le même geste) | `.fenetreDeParole` |
| Segment final qui déborde après la fermeture de la fenêtre | rattaché si son **premier mot** tombait dans la fenêtre | `.debordement` |
| ⌥⌘ tenu > 400 ms sans mouvement de souris et sans tracé | commentaire global explicite, le HUD affiche « commentaire général » | `.gesteGlobal` |
| Verrouillage micro (⌃⌥M) pour un monologue long | commentaire global, jusqu'au déverrouillage | `.gesteGlobal` |

**Réaffectation en session, sans panneau.** Pendant qu'une fenêtre de parole est ouverte, `⌥⌘ + chiffre` réaffecte le segment en cours à la marque N ; `⌥⌘ + 0` le bascule en commentaire global. Le badge de la marque cible s'illumine sur le calque, à sa position, là où le regard de l'utilisateur se trouve déjà. C'est la correction du principal défaut de la prévention initiale : un HUD déporté que personne ne regarde en testant.

**Le numéro est attribué au `mouseDown`, pas au `mouseUp`,** et il est définitif. La conception initiale renumérotait après suppression en revue, ce qui contredit directement le fait que l'utilisateur **prononce** les numéros (« comme sur la marque 2 »). Une marque supprimée laisse un trou ; le rapport écrit « marque 2 (supprimée) » si un texte y fait référence. Un trait avorté par Échap libère le numéro, qui est réattribué à la marque suivante — c'est le seul cas de réutilisation, et il a lieu avant que l'utilisateur n'ait pu le prononcer.

### 3.6 Latence d'entrée audio

`AVAudioTime.hostTime` date la remise du buffer, pas l'instant où le son a atteint le micro. Micro interne : 10 à 30 ms, négligeable. **AirPods : 150 à 300 ms.** Non compensée, cette latence consomme l'intégralité du budget d'erreur d'ancrage.

À l'ouverture de session et à chaque `AVAudioEngineConfigurationChange` : `latence = inputNode.presentationLatency + kAudioDevicePropertyLatency + kAudioDevicePropertySafetyOffset`, soustraite dans `bufferStartTime`, affichée dans le doctor. Si `when.isHostTimeValid == false` (fréquent sur périphérique agrégé), repli sur un compteur d'échantillons.

### 3.7 Le journal d'événements

Une session est un journal append-only projeté en une structure `Session`. Écriture au fil de l'eau : un crash à la minute 8 d'une session de 10 laisse 8 minutes exploitables.

**Correction sur l'atomicité.** `PIPE_BUF` qualifie l'atomicité des écritures sur un **tube**, pas sur un fichier régulier ; pour un fichier ouvert en `O_APPEND`, l'atomicité repose sur le verrou de vnode et un `write(2)` unique ne s'entrelace pas. La conclusion (« pas de verrou nécessaire ») tient, la contrainte des 512 octets n'existe pas — et n'était de toute façon pas respectée, puisqu'une ligne `resolved` avec une note de 600 caractères la dépasse. Les vrais risques à traiter : écriture courte (boucler sur `write`), `EINTR`, et projet placé sur un dossier synchronisé (Dropbox, iCloud) où `O_APPEND` ne garantit plus rien — dans ce cas, un `flock` consultatif.

`TimelineStore` est un acteur de projection ; l'écriture disque passe par une **file série dédiée** avec son propre descripteur `O_APPEND`, distincte de l'acteur. Les événements `frameIndexed` (4/s par écran) n'entrent jamais dans l'acteur : ils sont agrégés sur la file d'encodage et écrits directement.

---

## 4. Architecture technique

```
     ⌃⌥S ouvrir · ⌃⌥F terminer · ⌃⌥M verrou micro   (RegisterEventHotKey, 0 permission TCC)
                              |
   PreRollRecorder ─────────> SessionCoordinator <──────── NSStatusItem (etat visible meme
   (opt-in, 2 fps,                machine a etats            sous Mission Control)
    demi-resolution,        proprietaire du cycle de vie
    3 segments de 10 s)     arbitre des degradations
                              |
   +----------+---------------+---------------+----------------+------------------+
   |          |               |               |                |                  |
   v          v               v               v                v                  v
Permission SessionClock  ScreenRecorder   InputRouter     VoiceWindow        ProjectResolver
Doctor     horloge       1 CaptureSegment CGEventTap      AVAudioEngine      proc_pidinfo /
(doctor,   maitresse     par ecran :      (thread dedie,  ouvert PAR GESTE   ~/.claude/sessions
 TCC hors  + latence     SCStream         run loop propre)+ SpeechAnalyzer   / git / titre
 session)  audio         + AVAssetWriter  + OptionGate    [transcriber,      3 etats affiches
                         + FrameRing (4)  + watchdog 5 s   detector]
                              |               |                |                  |
                     frames   |    index      | points  marques| segments   projet |
                     .complete|    dirtyRect  | encre   t=down |  mots             |
                              v               v                v                  v
                    +==================================================================+
                    |                        TimelineStore (actor)                     |
                    |   projection en memoire + file serie -> events.jsonl (O_APPEND)   |
                    +---+------------------------+---------------------------+---------+
                        ^                        |                           |
                        |                        v                           v
              AnnotationOverlay          HUD (SwiftUI, .statusBar)    ContextRegistry
              1 NSPanel / NSScreen       badge sur le CALQUE,          (vide au MVP,
              ordonnee a l'ecran         pas dans le HUD               budget 250 ms)
              PENDANT le trace
              3 couches CA

 ================== FIN DE SESSION (finalizing, < 2 s) ==================

  TimelineStore -> FrameExtractor -> FrameComposer -> ReportRenderer -> Publisher
                   finalisation      crop natif,      bibliotheque      .regarde/
                   PAR SEGMENT,      Lanczos, gravure PARTAGEE avec     + Clipboard (sauvegarde
                   assetTime(),      des numeros,     le sidecar        + restauration)
                   clampage          redaction        (report.md est    + AgentInjector (best
                                     des secrets      un RENDU du       effort, AX)
                                                      manifeste)
                                                            ^
                                                            |
                                              regarde-mcp (sidecar stdio)
                                              5 outils, lit le disque, app fermee
```

### 4.1 Choix technologiques tranchés

| Décision | Retenu | Écarté | Justification |
|---|---|---|---|
| Ring buffer | Encodage HEVC continu (`AVAssetWriter`) + anneau de 4 frames brutes | Ring buffer RAM de frames | Une frame BGRA 3456×2234 = 29,45 MiB. 10 s à 15 fps = 4,3 GiB. À 60 fps : 104 GiB/min. Le terme « ring buffer » est abandonné partout dans le code. |
| Encodeur | `AVAssetWriter` + `AVVideoMaxKeyFrameIntervalDurationKey = 1.0` | `SCRecordingOutput` | Aucun contrôle du GOP ; et toute `updateConfiguration` **arrête l'enregistrement** sans avertissement. |
| Arbitrage souris | `CGEventTap` `.headInsertEventTap`, décision par événement sur `event.flags` | `ignoresMouseEvents` piloté par `flagsChanged` | Course garantie : un `mouseDown` dans l'intervalle part à l'application testée. Survit à la régression Apple 26.3/26.4 sur les fenêtres transparentes. |
| Instantané de marque | Appariement sur la file d'encodage, anneau de 4 frames déjà copiées | Lecture de `lastFrame` depuis le thread du tap | Course sur une référence `CVPixelBuffer` non atomique → `EXC_BAD_ACCESS` intermittent dans `CVPixelBufferRelease`, fréquence proportionnelle à l'activité de l'écran. Le tap ne touche **jamais** un buffer d'image. |
| Ordonnancement du calque | À l'écran **pendant le tracé uniquement** | Fenêtre transparente plein écran permanente | Une couche de composition permanente fait perdre à l'application testée les chemins optimisés du WindowServer. L'outil censé diagnostiquer une lenteur en deviendrait la cause. |
| Modificateur | ⌥⌘ maintenu, configurable ; **pas de double-appui** | Double-appui sur Option | Sur clavier français, `{` `}` `[` `]` `|` `~` s'obtiennent avec Option : taper `{{` en JSX arme le mode. Structurellement incompatible avec l'AZERTY. |
| Exclusion de l'overlay | `SCContentFilter(display:excludingApplications:)` | `sharingType = .none` | Ignoré par ScreenCaptureKit depuis macOS 15.4 (confirmation DTS Apple). L'exclusion par application couvre les fenêtres créées après coup. |
| Curseur | `showsCursor = false`, point de marque dessiné à la gravure | `showsCursor = true` | Le curseur est composité exactement là où l'utilisateur trace : il masque l'élément annoté au centre de chaque recadrage. |
| Transcription | `SpeechAnalyzer` + `SpeechTranscriber` + **`SpeechDetector` obligatoire** | `SFSpeechRecognizer`, whisper.cpp | Sessions non plafonnées, horodatage au mot (0,1–0,3 s), 100 % local, **aucune permission de reconnaissance vocale**. Sans `SpeechDetector` dans les modules : aucune segmentation. |
| Canal vers l'IA | Sidecar MCP stdio lisant le disque | Serveur MCP porté par l'application ; transport HTTP local | L'agent tourne souvent application fermée. Une URL à port aléatoire ne peut pas figurer dans une configuration stable. Le transport HTTP est coupé du MVP. |
| Livraison des images | Chemin absolu en texte brut | `image` MCP par défaut, `resource_link` | Plafond dur de 25 000 jetons par résultat d'outil ; +33 % de base64 ; Zed lève `missing field mime_type`. Tous les agents cibles lisent un PNG hors du plafond MCP. |
| Sandbox | Hors sandbox, Developer ID + notarisation | Mac App Store | Accessibilité et `proc_pidinfo` incompatibles ; un tap qui consomme des événements ne passe pas la revue. |

### 4.2 Le mode dégradé sans tap : tranché

La conception initiale annonçait « sans tap → mode verrouillé armé au clic dans le HUD ». Sans tap, on n'a **aucun accès aux événements souris** : la seule voie est `ignoresMouseEvents = false` sur les panneaux et un traitement dans une `NSView`, c'est-à-dire un second chemin d'entrée complet (autres coordonnées, autre suivi de drag, autre sémantique — l'application testée ne reçoit alors plus rien).

**Décision : sans Input Monitoring et Accessibilité, il n'y a pas de session.** Le doctor le dit explicitement et propose l'octroi. Ce second chemin est budgété à part au lot 7 (1,5 j) **uniquement** comme parade à la régression Apple sur les fenêtres transparentes, pas comme mode de permission dégradé.

**Corollaire à trancher une fois pour toutes : Accessibilité est obligatoire, pas optionnelle.** Un tap `.defaultTap` qui *consomme* des événements en a besoin en plus d'Input Monitoring ; seule la lecture pure se contente d'Input Monitoring. L'onboarding le présente comme requis.

---

## 5. Capture et extraction de frames

### 5.1 Pré-roll : la session commence dans le passé

Sans pré-roll, le parcours réel est : le bug survient → raccourci → `arming` (0,3 à 1,5 s) → première frame `.complete` → **le bug est passé**. Sur un état transitoire non déterministe, il ne sera pas reproduit. C'est le cas d'usage numéro un d'un outil de feedback visuel.

**Pré-roll permanent en mode économe**, opt-in explicite avec indicateur permanent dans la barre de menus :

| Paramètre | Valeur | Coût mesuré |
|---|---|---|
| Résolution | demi (1728×1117 sur l'écran de référence) | — |
| Cadence | 2 fps | 0,4 % d'un cœur |
| Débit | 2,05 Mb/s | 15,4 MiB/min |
| Historique | 3 segments roulants de 10 s, soit 20 à 30 s selon la position dans le segment courant — **20 s garanties**, chiffre à annoncer à l'utilisateur | ~8 MiB de disque |

`AVAssetWriter` ne sait pas tronquer par l'avant : le pré-roll est implémenté en segments roulants de 10 s, les trois derniers conservés, les autres supprimés. Au raccourci d'ouverture, le flux bascule en pleine résolution (nouveau `CaptureSegment`), et les segments de pré-roll deviennent les premiers segments de la session.

**Marque rétroactive :** ⌥⌘ + `1`..`9` pose une marque datée à T−N secondes. La frame est **toujours extraite du fichier encodé** : segment de session si T−N est postérieur à l'ouverture, segment de pré-roll sinon (à résolution réduite, ce que le manifeste signale).

L'anneau de 4 frames ne couvre que **0,27 s à 15 fps** : il sert à l'appariement du `mouseDown` (§ 5.3), jamais aux marques rétroactives. Le dimensionner pour couvrir 4 s demanderait 60 frames, soit 1,77 GiB à pleine résolution — exclu par la même arithmétique qui a écarté le ring buffer RAM (§ 4.1). Le seek dans le fichier encodé coûte 31 ms avec le GOP forcé à 1 s, ce qui reste sous le seuil de perception.

> **Amendement (S43, par la mesure).** Cette section demandait à l'origine une tolérance de seek `before = .positiveInfinity` / `after = .zero`, en s'appuyant sur les 31 ms citées plus haut. C'était une erreur de raisonnement, et elle rendait **C11 structurellement impassable**.
>
> `requestedTimeToleranceBefore = .positiveInfinity` n'exprime pas « rends la frame juste avant » : elle *autorise* le générateur à remonter aussi loin qu'il veut. Il choisit donc l'option la moins chère — l'**image clé** précédente. Avec le GOP forcé à une seconde, l'image rendue peut être fausse d'une seconde entière.
>
> Mesuré le 23 août 2026 sur une session de 18 s à 15 fps : **812,8 ms** de pire écart entre l'instant demandé et l'instant obtenu, sur huit marques. Juste sous l'intervalle d'image clé, ce qui nomme la cause sans ambiguïté. Les 8 images venaient bien du fichier, l'appariement était juste, l'horloge était recalée — et l'utilisateur aurait reçu l'écran d'il y a huit dixièmes de seconde. B1 sous un autre nom.
>
> **Second amendement, même jour.** La tolérance nulle est juste, mais elle peut *échouer*. Sur un écran immobile, l'encodeur n'écrit que ce qui change : aucune frame ne couvre l'instant demandé, et le générateur rend « Cannot Decode ». La marque retombe alors sur le filet RAM — une image prise au relâchement, une à deux secondes trop tard — c'est-à-dire B1 remis par la porte de derrière. L'extraction fait donc **un second passage** sur les seuls instants refusés, avec `before = .positiveInfinity`. Le saut à l'image clé que cette tolérance autorise ne se paie que là où le premier passage a échoué, donc sur un écran qui ne produit pas de frames — et sur un écran qui ne change pas, l'image d'il y a une seconde est la bonne. Le journal marque ces images comme obtenues au second essai.
>
> **Troisième amendement : l'écart demandé/obtenu n'est plus une mesure d'erreur.** Il l'était sous la tolérance infinie — le générateur sautait à l'image clé et rendait autre chose que ce qui était affiché ; les 812 ms mesurés le 23 août 2026 étaient un défaut réel. Sous la tolérance nulle, le générateur rend la frame dont l'intervalle de présentation *contient* l'instant demandé, c'est-à-dire par construction celle qui était affichée. L'écart entre l'instant demandé et le PTS rendu est donc l'**âge** de cette image : depuis combien de temps l'écran n'avait pas changé. Sur un écran livrant 5,4 images par seconde — mesuré le même jour sur une fenêtre du Finder — 500 ms d'âge sont attendus, et l'image est exacte.
>
> Ce nombre **ne peut pas** détecter une timeline mal convertie : si `assetTime()` se trompait, on demanderait le mauvais instant et on obtiendrait la frame qui le couvre — âge minuscule, image fausse. **B1 se vérifie par la réglette du § 5.6, pas par cet écart.** Il reste utile nommé pour ce qu'il est : sur un écran animé, un âge élevé signale que l'encodeur a décroché.

> Les tolérances sont donc **nulles des deux côtés**. Le générateur rend alors la frame dont l'intervalle de présentation *contient* l'instant demandé : celle que l'utilisateur avait sous les yeux. Le décodage coûte le trajet depuis l'image clé précédente — au plus 15 frames — et c'est exactement ce que le GOP d'une seconde borne. **Le GOP sert la précision, pas la paresse** : sans tolérance nulle, il ne bornait rien du tout, il autorisait l'erreur.

**Filet supplémentaire :** au tout premier instant du raccourci, avant `arming`, un `SCScreenshotManager.captureImage` synchrone. Une image existe quoi qu'il arrive ensuite.

### 5.2 Session : configuration et budget

```swift
cfg.width  = Int(frameContentRect.width  * pointPixelScale) & ~1
cfg.height = Int(frameContentRect.height * pointPixelScale) & ~1
cfg.captureResolution    = .best
cfg.scalesToFit          = false
cfg.pixelFormat          = kCVPixelFormatType_32BGRA
cfg.minimumFrameInterval = CMTime(value: 1, timescale: 15)
cfg.queueDepth           = 6          // max 8, marge contre l'epuisement de la pool
cfg.showsCursor          = false      // voir § 4.1
cfg.colorSpaceName       = CGColorSpace.sRGB
```

Sans `width`/`height` explicites, la capture sort en 1920×1080 : perte de résolution silencieuse, texte d'IDE illisible.

| Poste | Mesure |
|---|---|
| CPU encodage | 0,30 s pour 20 s de capture 3456×2234 à 15 fps = 1,5 % d'un cœur |
| RSS | 33 MiB stable, plus l'anneau de 4 frames (≈ 120 MiB à pleine résolution) |
| Disque | 6,2 Mb/s HEVC = 46,7 MiB/min, ~470 MiB pour 10 min |
| Seek | GOP forcé à 1 s, tolérance **`.zero` des deux côtés** — voir l'amendement ci-dessous |

**Poste non chiffré dans la conception initiale et à surveiller :** la copie de chaque frame `.complete` dans l'anneau applicatif brûle 440 MiB/s de bande passante mémoire en permanence, avec la pollution de cache associée. Ce n'est pas dans les 1,5 % de CPU, qui mesurent l'encodage. Mitigation : ne copier dans l'anneau que si l'écran a bougé (`dirtyRatio > 0`) et n'entretenir l'anneau qu'à partir de la première tenue de ⌥⌘ de la session.

### 5.3 Instantané de marque : l'appariement

Le tap ne pousse que `(SessionTime, point, type)` dans un ring lock-free. Un consommateur sur `encodeQueue` — seul propriétaire des frames — apparie l'événement à la frame dont le PTS est le plus proche **par valeur inférieure**, et fait la copie. L'anneau de 4 frames absorbe le délai d'appariement et permet de choisir la frame *précédant* le `mouseDown`, ce qui est la sémantique voulue.

### 5.4 Décision de burst

Un burst systématique triple le coût pour un bénéfice nul sur un écran statique — le cas majoritaire.

```swift
func framePlan(for mark: Mark) -> [SessionTime] {
    guard mark.motion.completeFramesLastSecond > 0 else { return [mark.t] }   // ecran fige
    guard mark.motion.screenWasMoving          else { return [mark.t] }       // curseur, caret
    return [mark.t - 0.8, mark.t, mark.t + 0.4]                               // clampe par assetTime()
}
```

Seuils : `completeFramesLastSecond ≥ 6` **et** `dirtyRatioLastSecond ≥ 0,02`. Le double critère élimine le curseur clignotant (fréquence élevée, surface dérisoire) et le redraw plein écran unique (surface énorme, fréquence 1).

La demande d'instantané du § 5.3 est **globale, et lue par chaque écran avec son propre curseur**. Une pression est un *instant*, pas un écran : chaque flux enregistre indépendamment ce qu'il montrait à cet instant-là, et la marque prend celui de son écran. Un curseur de lecture partagé — ce qu'il y avait jusqu'en S43 — faisait courir les écrans après la même file : celui qui drainait le premier rangeait l'instantané chez lui, et une marque sur deux ne trouvait rien. Le symptôme se lisait `0 frame(s)/s · 0.000 de surface`, c'est-à-dire « écran figé », alors qu'il fallait lire « instantané pris par l'autre écran ». Il ne se manifeste qu'avec **deux écrans tous deux actifs**, ce qui l'a tenu caché.

`dirtyRects` arrive **en PIXELS**, alors que `contentRect` arrive **en points** — la même dissymétrie qu'en S38, à l'endroit voisin. Les diviser sans convertir gonfle la mesure du carré du facteur d'échelle : sur un écran 2× au repos, le critère de surface était franchi en permanence et le burst se déclenchait pour rien. Mesuré le 23 août 2026 : `max 4.000` sur l'écran 2× contre `max 1.000` sur l'écran 1× de la même session. Le calcul vit désormais dans `SurfaceSalie.ratio`, hors du gestionnaire de frame, pour qu'un test puisse l'appeler.

La surface salie d'une frame est la **somme** des `dirtyRects`, donc une approximation par excès : deux rectangles qui se recouvrent sont comptés deux fois. Elle est **bornée à 1** avant d'entrer dans le critère — un ratio de surface ne peut pas dépasser 1, et le laisser filer ferait franchir le seuil de burst à un écran presque immobile dont le compositeur bavarde. La valeur brute reste au bilan de flux : au-dessus de 1, elle signale soit ce recouvrement, soit une confusion points/pixels comme celle de S38.

`dirtyRatioLastSecond` est la **moyenne** des surfaces salies sur la fenêtre d'une seconde, pas leur somme — précision ajoutée en S43 après qu'une somme s'y soit glissée. Une somme vaut `fréquence × surface moyenne` : elle fait entrer la fréquence dans l'axe surface et détruit l'indépendance dont ce critère dépend entièrement. Sous la somme, un spinner de 86×86 px à 15 fps cumulait 0,0225 et franchissait le seuil — le cas même que le critère existe pour écarter. Une moyenne reste bornée par 1 ; toute valeur au-dessus signale que la somme est revenue.

### 5.5 Finalisation, par segment

```
stopCapture()
  -> pour CHAQUE segment, independamment, avec capture d'erreur par segment :
       markAsFinished() -> await finishWriting()
  -> un SEUL generateCGImagesAsynchronously(forTimes:) PAR segment finalise
```

Un writer ouvert pour un écran débranché immédiatement n'a aucun échantillon : `finishWriting()` échoue sur `AVError.noSourceTrack`. Dans une séquence `try` linéaire, la session entière est perdue, y compris les marques d'un autre écran qui, elles, sont complètes. Le writer d'un écran disparu est finalisé **au moment de la déconnexion**, pas en fin de session.

Filet universel : toute marque conserve sa frame RAM. Test de non-régression obligatoire : débrancher l'écran externe en pleine session et vérifier que les marques de cet écran ont bien leur image principale.

### 5.6 Composition, redimensionnement, gravure

| Étape | Règle |
|---|---|
| Recadrage | Zone d'intérêt dilatée ×2,5, côté long dans `[640, 1792]` px, **surface plafonnée à 1024 tuiles**, dimensions alignées sur des multiples de 28. Si la boîte dilatée dépasse 40 % de la surface de l'écran, bascule sur `full`. |

**Vue d'ensemble.** Chaque publication écrit, en plus des recadrages, **un `ensemble.png` par écran annoté** : l'écran entier réduit au palier standard, toutes ses marques gravées dessus. Les recadrages montrent chacun leur détail ; seul l'ensemble dit où les marques se situent les unes par rapport aux autres, ce dont l'agent a besoin pour interpréter « le bouton sous le titre » ou « la colonne de droite ». C'est la dernière capture de l'écran qui sert de fond — l'état le plus récent où une marque y a été posée — et elle est retenue déjà réduite : six mégaoctets au lieu de trente et un.

**Correction du lot 2 — trois règles réécrites après le premier usage réel.**

*La zone d'intérêt n'est pas la boîte englobante.* Pour une flèche, c'est un carré autour de sa **pointe**, dimensionné sur la longueur du trait. Centrer sur la boîte englobante mettait le milieu du trait au centre de l'image et laissait l'élément désigné sur un bord, souvent coupé : l'agent recevait un gros plan sur du vide traversé par un trait.

*Le côté long ne borne plus à 896 px, c'est la SURFACE qui coûte.* Un cadre tracé autour d'un paragraphe sortait en 896×112 — soit **128 tuiles** quand le palier standard en autorise 1568 — avec un texte réduit au quart de sa taille native, illisible, pour un dixième du budget disponible. La borne haute passe à 1792 px et le frein devient le budget de tuiles, calé à 1024 : exactement ce qu'occupait une image carrée de 896 px sous l'ancienne règle, si bien que les recadrages compacts gardent leur coût et que seules les zones plates gagnent la place qu'elles laissaient perdre.

*Un plancher de netteté à 0,5.* Sur un écran Retina, ce facteur rend exactement la densité que l'utilisateur a sous les yeux. En dessous, le sujet devient plus petit que ce qu'il regardait en le désignant. Quand contexte et netteté ne tiennent pas ensemble, on resserre le cadrage — le contexte cède avant la netteté, et l'intégrité de la marque avant les deux.
| Vue `full` | **Recadrée sur le cadre de la fenêtre cible par défaut**, pas sur le display. La vue display entière est une option explicite. |
| Masquage | Toute fenêtre n'appartenant pas à l'application cible et se superposant à la zone exportée est noircie, notifications comprises (`kCGStatusWindowLevel` et au-dessus). La liste des fenêtres et leurs cadres sont lus par `CGWindowListCopyWindowInfo` à l'instant de la marque. |
| Réduction | Lanczos (`CILanczosScaleTransform`, 106 ms vers 2 576 px, 24 ms vers 1 568 px). Jamais d'interpolation linéaire. |
| Dimensionnement | `hp = floor(sqrt(B/r))`, `wp = min(92, floor(hp·r))`, cible `28·wp × 28·hp`. Palier standard `B = 1568` pour la vue `full`, haute résolution `B = 4784` pour `full_hires`. |
| **Gravure** | **Après le redimensionnement**, jamais avant : un trait de 3 px gravé avant une réduction ×0,42 devient une tache grise. |

**Spécification de gravure.** Encre vermillon `#FF3B30`, constante d'un rapport à l'autre. Halo tracé **à l'épaisseur exacte du trait**, l'encre par-dessus amincie d'un liseré de 0,5 px de chaque côté — le liseré est donc PRIS sur l'épaisseur, jamais ajouté autour. *Les deux formulations précédentes ajoutaient de la largeur : mesuré, un trait censé faire 3,1 px en occupait 4. En dessous de 2,4 px d'épaisseur le trait est gravé nu, faute de quoi il n'en resterait pas assez pour se voir.* Sa couleur dont la couleur bascule selon la luminance moyenne sous un anneau dilaté du tracé : `L* > 55` → halo `#0B0B0D` à **50 %** d'alpha, sinon `#FFFFFF` à 75 %. *Les valeurs d'origine — 2× et 70 % — ont été mesurées à l'usage : le halo triplait l'épaisseur perçue du trait, au point qu'un cadre fin tracé à quelques pixels d'un paragraphe ressortait épais et collé au texte.* Contraste garanti ≥ 4,5:1 sur thème clair comme sombre. **Épaisseur : celle du calque, exactement** — `InkStyle.width` points × échelle de l'écran × facteur du recadrage, plancher à 1,2 px. *La règle d'origine, `max(3 px, 0,22 % du côté long)`, ne regardait ni l'échelle de l'écran ni celle du recadrage : sur une image de 1792 px réduite de moitié elle gravait 3,94 px là où l'écran en montrait 3. Un tiers de trop, relevé deux fois à l'usage. Ce que l'utilisateur voit en traçant est ce qui doit être gravé — le halo est le seul écart assumé, et il existe parce que l'image sera regardée hors de son contexte.* **Badge : disque plein du diamètre du calque**, `BadgeLayer.diameter` points × échelle de l'écran × facteur du recadrage, plancher à 16 px ; chiffre SF Pro Rounded Bold blanc à `BadgeLayer.fontRatio` du diamètre — la même proportion qu'à l'écran. *La règle d'origine, `max(26 px, 2,2 % du côté long)`, souffrait du même défaut que l'épaisseur du trait : elle donnait 39 px sur une image de 1792 là où l'écran en montrait 23, soit presque le double. Le calque est la référence, la gravure la reprend.* ; capsule de largeur ×1,45 à deux chiffres. Placement parmi huit positions candidates autour de la `bbox`, retenue celle qui reste dans l'image, ne chevauche aucun badge déjà placé, et minimise la variance locale de luminance du fond. Formes d'abord, badges ensuite : un badge n'est jamais recouvert.

### 5.7 La déduplication perceptuelle est retirée du MVP

La conception initiale fusionnait les frames de distance de Hamming ≤ 6 sur un dHash 64 bits. Un dHash est un gradient sur une grille 8×9 : il est **insensible par construction aux petits changements locaux**, c'est-à-dire exactement à ce qui déclenche une marque (un badge d'erreur qui apparaît, un champ qui passe en rouge, un total qui ne s'est pas rafraîchi). L'exemple fourni par la conception elle-même fusionnait la frame de 00:21 avec celle de 00:47, entre lesquelles un POST avait renvoyé 500 : le rapport aurait présenté une flèche pointant un badge d'erreur absent de l'image.

La déduplication n'économise que sur la variante `full`, qui est le format secondaire. Bénéfice marginal, risque de rapport faux : **retirée**. Elle pourra revenir comparée sur l'union des `bbox` dilatées, avec un seuil strict et une contrainte de proximité temporelle.

---

## 6. Calque d'annotation et bascule Option

### 6.1 Les fenêtres

Une `NSPanel` par `NSScreen` — jamais une fenêtre couvrant l'union des écrans (`backingScaleFactor` est par fenêtre, l'union n'est pas un rectangle en disposition L, les écrans changent d'échelle à chaud).

```swift
styleMask          = [.borderless, .nonactivatingPanel]  // fixe a l'init, JAMAIS mute
canBecomeKey       = false                               // mecanisme distinct de nonactivatingPanel
hidesOnDeactivate  = false                               // sinon le calque ne s'affiche jamais
isOpaque           = false; backgroundColor = .clear; hasShadow = false
level              = .screenSaver
collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle, .transient]
ignoresMouseEvents = true                                // en permanence : cosmetique, pas decisionnel
sharingType        = .none                               // ceinture-bretelles, sans jamais y compter
```

Affichage par `orderFrontRegardless()`. Politique `.accessory` + `LSUIElement = 1` : pas d'icône Dock, ignoré par Stage Manager, structurellement incapable de voler le focus.

**Le calque n'est ordonné à l'écran que pendant le tracé.** Il est ordonné à la pression du modificateur (le tap l'a déjà décidé, les points sont bufferisés : le trait apparaît complet quand la fenêtre arrive) et retiré à la fermeture de la fenêtre de parole. Hors de ces intervalles, aucune couche de composition permanente ne s'intercale entre l'application testée et le WindowServer.

### 6.2 La porte à verrou

```swift
private func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        CGEvent.tapEnable(tap: tap, enable: true); return nil
    }
    guard gate != .passthrough else { return Unmanaged.passUnretained(e) }   // suspended / blocked

    let armed = e.flags.contains([.maskAlternate, .maskCommand])
             && targetWindowRect.contains(e.location)          // ancrage a la fenetre cible
    var capture = strokeActive
    switch type {
    case .leftMouseDown:                       // SEUL point de decision d'entree
        capture = armed && !mouseDownInApp
        strokeActive = capture; mouseDownInApp = !capture
    case .leftMouseUp:                         // le verrou tient jusqu'ici, modificateur ou pas
        capture = strokeActive
        strokeActive = false; mouseDownInApp = false
    case .leftMouseDragged: capture = strokeActive
    case .mouseMoved:       capture = armed && !mouseDownInApp
    default: break
    }
    guard capture else { return Unmanaged.passUnretained(e) }
    Ink.shared.push(e.location, type, e.timestamp)             // lock-free, zero allocation
    return nil
}
```

**Les clics suivent le curseur, les touches suivent l'application active.** La condition ci-dessus — `targetWindowRect.contains(e.location)` — est le bon critère pour un `mouseDown`, dont la position **est** le sens. Elle est fausse pour une touche de contrôle : le geste normal amène le curseur au bord de ce qu'il désigne, parfois dehors (une flèche tracée vers l'extérieur, un cadre tiré jusqu'au coin), et l'intention frappée juste après tomberait dans le vide — pendant que le `⌥⌘ + chiffre` partirait à l'application testée. Mesuré au lot 2 sur un scénario de quatre marques : **deux intentions sur quatre perdues**, et deux changements d'outil avec.

Le critère retenu pour `⌘Z`, le changement d'outil et la palette d'intentions est donc : **une session est ouverte et la fenêtre cible est l'application au premier plan**. Si l'utilisateur est passé dans son éditeur, l'éditeur est actif et récupère ses raccourcis. Regarde ne devient jamais active ([ADR-0004](adr/0004-application-accessory-sans-dock.md)), donc ce drapeau ne se trompe jamais sur son propre compte. Il est publié depuis le thread principal sur `didActivateApplicationNotification` et lu comme un booléen atomique dans le callback — `NSWorkspace` est du AppKit, interdit ici.

**Ordre entre souris et clavier.** Les événements souris traversent le ring et n'atteignent le modèle qu'au prochain tick du display link ; les touches de contrôle arrivent directement sur le thread principal. Le ring doit donc être **drainé avant** de traiter une touche, sans quoi relâcher le bouton et frapper un chiffre dans la foulée — le geste naturel, puisque ⌥⌘ est déjà tenu — applique l'intention à la marque **précédente**. Le symptôme n'est pas une panne mais un rapport faux, où chaque marque porte l'intention de sa voisine ; observé au lot 2, quatre intentions sur quatre décalées d'un cran.

Budget du callback : zéro allocation, zéro appel AppKit, zéro I/O, zéro verrou bloquant. Les souris haute fréquence émettent à 125–1000 Hz ; un dépassement déclenche `kCGEventTapDisabledByTimeout` et la bascule cesse silencieusement. Watchdog toutes les 5 s vérifiant `tapIsEnabled` **et** qu'un événement a été vu récemment ; recréation intégrale sinon.

### 6.3 Les conflits de raccourcis, résolus

| Conflit | Résolution |
|---|---|
| ⌥-clic est un geste légitime (Safari, Finder, Figma, IDE) | Modificateur ⌥⌘ par défaut, configurable. ⌥ seule n'arme rien. |
| Double-appui sur modificateur incompatible avec l'AZERTY | **Supprimé.** Le mode verrouillé passe par un raccourci Carbon distinct (⌃⌥L) ou un clic sur le HUD. |
| ⌥⌘-clic dans l'IDE crée une marque parasite sur le code | Le `mouseDown` n'est consommé que si son point tombe dans le cadre de la fenêtre cible (`SCWindow.frame`, réactualisé à chaque changement d'application au premier plan). Ailleurs, passage transparent. `⌥⌘⇧` force la capture hors cible. |
| ⌥← ⌥→ ⌥⌫ font clignoter le badge « armé » | Le badge n'est allumé que si (modificateur tenu ≥ 120 ms) **et** (curseur dans la fenêtre cible) **et** (aucun `keyDown` depuis la pression). |
| Geste raté | `Échap` pendant le tracé annule le trait et libère le numéro. **Le clic droit fait de même**, geste plus direct quand la main est déjà sur la souris ; il n'est consommé que pendant un tracé actif, et son relâchement l'est aussi — sinon l'application testée recevrait un relâchement sans pression. Hors tracé, le menu contextuel lui appartient entièrement. `⌘Z` après le relâchement supprime la dernière marque, sans renumérotation. Ces deux touches imposent que le tap écoute `keyDown` dès le lot 0. |
| Secure Input (champ de mot de passe, 1Password) | Les événements **souris** continuent de passer : la porte fonctionne. Ce qui est faux, c'est l'indicateur du HUD. Le vrai risque à traiter : signaler visuellement que la fenêtre de parole est ouverte pendant qu'un mot de passe est saisi, et la fermer d'office quand `IsSecureEventInputEnabled()` passe à vrai. |

### 6.4 Rendu de l'encre

`CAShapeLayer` + `CATransaction.setDisableActions(true)` — sans quoi Core Animation anime implicitement `path` et le trait arrive avec 0,25 s de retard. Trois couches : marques posées (rasterisées, coût de recomposition nul), trait vivant (un seul `CAShapeLayer`), badges. Décimation Ramer-Douglas-Peucker, tête du trait figée périodiquement, queue de ~200 points dans la couche vivante. Alimentation par un ring lock-free vidé par un display link — jamais un `DispatchQueue.main.async` par point.

Latence cible : p95 < 33 ms, objectif < 16 ms.

### 6.5 Le curseur n'est jamais masqué

`NSCursor.hide()` ne fonctionne que si l'application est active, donc jamais ici. `CGDisplayHideCursor` est comptabilisé par références et global : un déséquilibre laisse le curseur invisible sur toute la machine. Un réticule d'encre est dessiné dans le calque, la flèche système reste au-dessus.

### 6.6 La revue de fin de session est retirée du chemin nominal

La conception initiale ouvrait la revue automatiquement dès qu'un segment avait une confiance faible — c'est-à-dire à chaque session, puisque une hésitation de dix secondes entre le tracé et le commentaire suffisait à déclencher la règle `horizon`. Elle plaçait ainsi 45 à 120 s de coût fixe exactement sur le poste qui annule le gain de l'outil.

Avec le micro lié au geste (§ 3.5), la notion de confiance de rattachement disparaît. **La revue ne s'ouvre plus jamais toute seule.** Le bandeau de confirmation reste 8 s et propose `R` pour la revoir. Elle sert alors à trois choses, dans cet ordre d'usage réel : **éditer le texte transcrit** (au clavier, avec conservation du brut dans le manifeste), supprimer une marque ou un segment, et **vérifier les images qui vont partir** via une bande de vignettes.

Budget dur : **20 secondes maximum entre le raccourci de fin et le presse-papiers** en chemin nominal. Toute fonctionnalité qui dépasse est supprimée du MVP, pas améliorée.

### 6.6bis Codes de touches et disposition du clavier

`kCGKeyboardEventKeycode` désigne un **emplacement** sur le clavier, pas le caractère
imprimé dessus. Deux règles opposées en découlent, et les confondre casse un raccourci
sur un clavier non-QWERTY :

| Type de touche | Résolution | Raison |
|---|---|---|
| **Lettre** | par le **caractère**, via `UCKeyTranslate` | la position change : le `Z` d'un AZERTY est à l'emplacement du `W` QWERTY (code 6) |
| **Rangée numérique** | par le **code physique** (18 à 29) | la position est stable ; sur AZERTY le caractère `1` ne s'obtient que sur le pavé numérique, code 83, absent des portables |
| **Sans caractère** (`Échap`, flèches, Tab) | par le **code physique** | identique sur toutes les dispositions |

La résolution se fait au démarrage et à chaque `kTISNotifySelectedKeyboardInputSourceChanged`,
jamais dans le callback du tap, qui ne compare que des entiers (§ 6.2). Si elle échoue, le
raccourci est **désactivé** plutôt que rabattu sur un code par défaut : un raccourci qui
atterrit silencieusement sur la mauvaise touche coûte plus cher qu'un raccourci absent.

Établi au lot 0 : ⌥⌘Z, dont le code 6 était écrit en dur, se déclenchait sur la touche `W`
d'un clavier français.

### 6.7 `⌥⌘ + chiffre` : règle de désambiguïsation

Trois fonctions distinctes revendiquent `⌥⌘ + chiffre` — marque rétroactive à T−N (§ 5.1),
palette d'intentions (§ 7.4) et réaffectation du segment de parole (§ 3.5) — et leurs contextes
se recouvrent, puisqu'une fenêtre de parole s'ouvre dès la pression de ⌥⌘.

**Le discriminant n'est ni la tenue du modificateur ni l'ouverture de la fenêtre de parole, mais
la présence d'une marque attachée à la fenêtre de parole courante.**

| État de la fenêtre de parole courante | `1`..`9` | `⇧` + `1`..`9` |
|---|---|---|
| Ouverte, **aucune marque attachée** (rien n'a été tracé) | marque rétroactive à T−N secondes | — |
| Ouverte, **une marque attachée** | intention `1`..`6` appliquée à cette marque ; `7`..`9` sans effet, flash d'invalidité sur le HUD | réaffectation du segment de parole en cours à la marque N, badge illuminé sur le calque |
| Fermée | aucun effet | aucun effet |

Trois propriétés de cette règle :

**Elle enchaîne naturellement.** `⌥⌘` puis `3` puis `2` pose une marque rétroactive à T−3 s, puis
lui applique l'intention « erreur » — car la pose de la marque rétroactive l'attache à la fenêtre
courante, ce qui bascule le chiffre suivant du sens « rétroactif » vers le sens « intention ».

**Elle rend la seconde marque rétroactive consécutive impossible sans relâcher.** Pour poser deux
marques rétroactives d'affilée, il faut relâcher ⌥⌘ et le represser. C'est assumé : deux marques
rétroactives consécutives sont un cas marginal, et l'alternative — un mode explicite — coûterait
plus cher que le geste supplémentaire.

**Elle réserve `⇧` au cas rare.** La réaffectation est une correction, pas un geste de production.
Elle mérite un accord distinct, et c'est le seul des trois qui en porte un.

Le HUD affiche le sens actif du chiffre — « T−N » ou « intention » — tant que ⌥⌘ est tenu, pour que
la règle n'ait jamais à être mémorisée.


---

## 7. Voix et transcription

### 7.1 Chaîne retenue

```swift
let loc = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "fr-FR"))!
let transcriber = SpeechTranscriber(locale: loc, preset: .timeIndexedProgressiveTranscription)
let detector    = SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: false)
let analyzer    = SpeechAnalyzer(modules: [transcriber, detector])   // detector OBLIGATOIRE
let fmt  = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])!  // 16 kHz mono Int16
let conv = AVAudioConverter(from: engine.inputNode.outputFormat(forBus: 0), to: fmt)!     // UNE fois, hors du tap
```

`attributeOptions: [.audioTimeRange, .transcriptionConfidence]`. La timeline de session est **imposée** au moteur via `AnalyzerInput(bufferStartTime:)` : tous les horodatages de retour, segments comme mots, sortent directement sur notre timeline. Aucune réconciliation applicative, y compris après une interruption micro (le moteur tolère une timeline discontinue tant qu'elle reste monotone).

Trois faits établis par les sondes, non documentés par Apple, qui conditionnent l'implémentation :

- **Sans `SpeechDetector` dans les modules, il n'y a aucune segmentation aux pauses** : toute la session revient en un unique résultat final. Son flux `.results`, en revanche, n'émet rien : `reportResults: false`.
- **Alimenter plus vite que le temps réel effondre la segmentation.** Push au fil de l'eau depuis le tap micro, jamais de file de rattrapage.
- **Aucune permission de reconnaissance vocale n'est requise.** Transcription complète vérifiée avec `SFSpeechRecognizer.authorizationStatus() == .notDetermined`, sans invite. Ne pas demander `NSSpeechRecognitionUsageDescription` : ce serait une invite anxiogène et inutile.

`AssetInventory.assetInstallationRequest(supporting:)` puis `downloadAndInstall()` sans condition au démarrage de la première session (no-op de 0,12 s quand les assets sont là). Ne jamais boucler sur la nullité de la requête : elle reste non nulle après une installation réussie.

### 7.2 Cycle de vie du micro

**Le micro est fermé par défaut.** `AVAudioEngine` est démarré à l'ouverture d'une fenêtre de parole et arrêté à sa fermeture. Il est fermé **sans exception** en état `suspended` (veille, écran verrouillé, changement d'utilisateur, Mission Control) : la conception initiale le laissait ouvert, ce qui transforme un déjeuner écran verrouillé en enregistrement clandestin.

`finalizeAndFinishThroughEndOfInput()` **et attente du drain complet** à la fermeture de chaque fenêtre : les résultats finaux arrivent 1,3 à 2,7 s après la fin de la parole.

**Choix du périphérique.** Jamais l'entrée par défaut. Énumération via `AVCaptureDevice.DiscoverySession`, exclusion explicite des pilotes de boucle (`MSLoopbackDriverDevice`, BlackHole, Loopback, Soundflower, VB-Cable, agrégés), préférence `BuiltInMicrophoneDevice`, nom affiché dans le HUD. Sur la machine cible, l'énumération remonte déjà « Microsoft Teams Audio » : si c'est l'entrée par défaut, la session transcrit une visioconférence.

**Changement de périphérique.** Abonnement à `AVAudioEngineConfigurationChange` : reconstruction du moteur, recréation de l'`AVAudioConverter`, remesure de la latence d'entrée. Le `SpeechAnalyzer` n'est **pas** recréé.

**Deux tampons distincts.** À chaque résultat : si `isFinal`, ajout au transcript et remise à vide du tampon volatile ; sinon **remplacement** du volatile. Jamais de concaténation — les volatiles réémettent la phrase entière à chaque mot. Le volatile est aussi le seul indicateur fiable d'activité vocale.

### 7.3 Correction du jargon technique

`contextualStrings` **n'a aucun effet mesurable** (A/B strict : sortie rigoureusement identique). Ne pas y investir. Le problème réel n'est pas l'erreur visible (« padding » → « pratique », que l'agent rétablit sans peine avec le code sous les yeux) mais l'erreur **plausible** : « marge à droite » → « barre de droite » est grammaticalement valide, avec une confiance élevée, et l'agent ajoutera une bordure.

Deux mécanismes, tous deux dans le MVP :

1. **Lexique déterministe.** Deux sources : une liste figée d'environ 200 termes front (padding, marge, flex, viewport, survol, focus, débordement, z-index, placeholder, requête, rendu…) et **les identifiants extraits du projet cible** (noms de composants, de props, de routes — le chemin du projet est connu). Correction par distance phonétique sur les seuls mots de confiance < 0,6, les deux versions écrites dans le rapport : `pratique` *[padding ?]*.
2. **Édition inline dans la revue.** Le texte est éditable au clavier ; le brut est conservé dans `rawText`. La conception initiale n'offrait que réaffecter, basculer en global et supprimer : l'utilisateur voyait ses mots déformés sans rien pouvoir y faire, ce qui est le déclencheur d'abandon classique de tout outil de dictée.

**Mesure préalable obligatoire, avant le lot 5 et non après :** trois minutes de dictée réelle du développeur, micro interne, bureau ouvert, comptage des termes techniques à corriger. Toutes les mesures de qualité des sondes reposent sur de la voix synthétique, hors distribution. Si le taux dépasse un terme sur cinq, le lot 5 tel que spécifié n'est pas livrable et la saisie clavier passe devant.

### 7.4 Saisie clavier — dans le MVP

La conception initiale repoussait la saisie clavier au lot 12. Sans elle il n'existe aucun mode silencieux, donc aucun usage en open space, en visioconférence, ou simplement quand quelqu'un passe. Le produit se réduirait à des flèches numérotées sans mots, inexploitables par l'agent.

Deux niveaux :

- **Palette d'intentions**, muette et instantanée : marque posée, `⌥⌘ + 1..6` applique une étiquette (`mal aligné`, `erreur`, `manque un état`, `lent`, `texte à corriger`, `ne marche pas`). Couvre la moitié des retours réels pour un coût d'une journée.
- **Texte libre** : le tap consomme les `keyDown`, on reconstruit un `NSEvent` via `NSEvent(cgEvent:)` et on le passe à un `NSTextView` **hors écran** par `interpretKeyEvents(_:)`. Aucune fenêtre ne devient *key* — faire une fenêtre *key* envoie `resignKey` à l'application testée : popovers fermés, curseur figé, animations en pause, `blur` côté page web qui suspend les `requestAnimationFrame`. C'est exactement la régression que le produit promet d'éviter. Bénéfice collatéral : touches mortes françaises (`^`, `¨`), répétition et raccourcis d'édition gratuits.

IME asiatiques non couverts : limitation assumée et documentée.

---

## 8. Contexte opportuniste et projet cible

### 8.1 Providers : aucun dans le MVP, sauf ce qui est gratuit

Le noyau ne capture que des pixels et de la géométrie. Le seul enrichissement du MVP est celui qui ne coûte ni permission ni prompt : **identité et cadre de la fenêtre cible** (`NSWorkspace.frontmostApplication` pour le bundle et le pid, `SCWindow.title` / `.frame` pour le titre et la géométrie — le titre est gratuit dès lors que Screen Recording est accordé).

Les providers AppleScript (URL de navigateur, contenu de terminal) sont repoussés au lot 9 pour une raison de flux : le consentement Automation se demande **par application cible** et le prompt vole le focus, ce qui casse l'enregistrement en cours et l'état de l'application testée. Ils ne seront jamais déclenchés depuis le chemin d'une session, uniquement depuis un écran de réglages.

Le protocole est néanmoins fixé maintenant, parce qu'il conditionne le modèle de données :

```swift
protocol ContextProvider: Sendable {
    var id: String { get }
    func canHandle(_ obs: WindowObservation) -> Bool   // synchrone, bon marche, aucun IPC
    func enrich(_ obs: WindowObservation) async throws -> ContextFragment?
}
```

Budget dur : **150 ms par provider, 250 ms au total**, à la **pose de la marque** — jamais en fin de session, où les erreurs console et le DOM auront disparu. Un provider en échec est mis en liste noire pour le reste de la session, sans message. Plafonds appliqués à la capture : 4 Ko de texte terminal (80 dernières lignes), 20 entrées console, 10 requêtes réseau ; le surplus part dans `context/*.json`.

Le levier de valeur numéro un du lot 10 est le **sélecteur CSS** : quand il est fiable, il remplace intégralement la capture d'écran pour l'agent. C'est aussi le levier de réduction de jetons le plus efficace du produit.

### 8.2 Détection du projet cible

Signaux pondérés, croisés :

| Signal | Poids | Validation |
|---|---|---|
| `~/.claude/sessions/<pid>.json` avec `cwd` | 0,9 | `kill(pid, 0)` **et** `updatedAt` < 2 h |
| `proc_pidinfo(PROC_PIDVNODEPATHINFO)` sur **tous les descendants** du processus terminal au premier plan | 0,6 | chemin absolu, existant, contenant `.git` ou `package.json` |
| Titre de fenêtre d'IDE au format connu (`fichier.ts — projet`) | 0,2 | signal faible, **jamais décisif seul** |

Le `cwd` du processus de l'application terminal ne dit rien : Warp a pour `cwd` le home, ses dix shells enfants pointent sur six projets distincts. Le nom de dossier `~/.claude/projects/` n'est **jamais** décodé (encodage lossy : 52 des 86 projets contiennent un tiret dans un segment) ; le chemin exact vient du champ `cwd` du fichier de session.

**Trois états visuellement distincts, et non trois nuances de vert :**

| État | Condition | Comportement |
|---|---|---|
| **Certain** (vert discret) | deux signaux forts concordants | écriture directe |
| **Probable** (ambre) | un seul signal, motif affiché en clair (« shell Warp #20378 ») | écriture directe, mention dans le rapport |
| **Ambigu** (rouge) | candidats multiples ou aucun | **le sélecteur s'ouvre à l'ouverture de session**, pas à la fin |

**Correction par rapport à la conception initiale :** celle-ci refusait d'écrire en état ambigu, ouvrant donc un sélecteur à la seconde où l'utilisateur voulait avoir fini. Le projet est résolu dès `arming` : l'ambiguïté se tranche à ce moment-là, quand il n'attend rien, via une pastille cliquable dans le HUD présente toute la session.

Si aucun projet n'est détecté (test d'une application sans dépôt), les artefacts sont écrits dans `~/Library/Application Support/Regarde/orphelins/`, jamais nulle part.

---

## 9. Artefacts, format et intégration MCP

### 9.1 Principes

| # | Principe | Justification mesurée |
|---|---|---|
| P1 | Le disque est la source de vérité, MCP n'est qu'une vue | L'agent tourne souvent après la session, application fermée |
| P2 | Aucune image ne transite par MCP dans le chemin nominal | Plafond dur de 25 000 jetons par résultat d'outil ; +33 % de base64 ; bugs clients documentés |
| P3 | Texte d'abord, pixels à la demande, recadrage avant plein écran | Recadrage 756×532 = 513 jetons, capture native = 4 784 facturés |
| P4 | Contenu immuable, état mutable, fichiers séparés | Plusieurs agents lisent la même session en parallèle ; muter `report.md` salit le diff git |
| P5 | Tout enrichissement est optionnel, son absence est silencieuse | Universalité : le noyau ne capture que pixels et géométrie |

### 9.2 Arborescence

```
<projet>/.regarde/
├── .gitignore
├── index.jsonl                       # catalogue append-only, verrou fcntl a l'attribution du numero
├── state.jsonl                       # journal d'etat append-only
└── sessions/0042-20260819-1432-checkout/
    ├── manifest.json                 # SOURCE : tout le reste en est un rendu
    ├── report.md                     # rendu Markdown, versionnable
    ├── transcript.txt                # brut horodate, jamais servi par MCP
    ├── paste-web.md                  # bloc autonome pour chat web
    └── frames/{crop-01.png, full-01.png, hi/full-01@hi.png}

$TMPDIR/regarde/<uuid>/             # NSTemporaryDirectory : hors Time Machine, purge systeme
    └── segment-00-display1.mov       # 0600, repertoire 0700, supprime en publishing
```

`.regarde/.gitignore` : `sessions/*/frames/`, `sessions/*/context/`, `sessions/*/paste-web.md`, `state.jsonl`. `manifest.json`, `report.md`, `transcript.txt` et `index.jsonl` restent versionnables (moins de 25 Ko par session).

**Le numéro de session est attribué en `publishing`, pas à `t0`.** Il est monotone par projet ; or le projet peut être ambigu à l'ouverture et changé en revue. L'identité pendant tout le cycle de vie est un UUID ; le numéro et le nom de dossier final sont calculés sous verrou de fichier sur `index.jsonl` au moment de l'écriture.

### 9.3 `report.md` est un rendu, pas un fichier source

Le sidecar doit préfixer le bandeau « DÉJÀ TRAITÉ » (issu de `state.jsonl`, donc dynamique), filtrer par `marks`, et honorer `include_context: false`. Il ne peut donc pas servir un fichier tel quel. **Conséquence d'architecture : le générateur de rapport est une bibliothèque partagée entre l'application et le sidecar, et `report.md` sur disque est un rendu du manifeste.** Ce point n'était pas énoncé dans la conception initiale et déplace du travail du lot 4 vers une brique commune, à faire avant le lot 6.

### 9.4 Exemple de rapport (MVP, sans providers)

````markdown
# Feedback #42 — shop-front — 19 août 2026, 14 h 32

Session de test de 2 min 14 s. **3 marques**, **1 commentaire général**.
Regarde 0.5.0 (macOS 26.1). Transcription locale fr-FR, aucune donnée sortie de la machine.

## Comment lire ce rapport

Le développeur a testé son application en la manipulant normalement. Quand quelque chose l'a
gêné, il a maintenu ⌥⌘ et entouré la zone à l'écran : cela a créé une **marque numérotée**.
Ce qu'il disait à voix haute pendant ce geste a été transcrit et rattaché à la marque.

- Les marques sont dans l'ordre chronologique, pas par importance. Les numéros peuvent
  comporter des trous : une marque supprimée n'est jamais renumérotée.
- **Le texte suffit dans la majorité des cas.** Ne charge une capture que si tu ne sais pas
  quel élément est visé, ou si le problème est purement visuel (alignement, espacement,
  chevauchement). Le chemin absolu et le coût en jetons sont sous chaque marque.
- Les termes notés `[terme ?]` sont des corrections proposées par le lexique local sur des
  mots que la reconnaissance vocale a mal entendus. Rétablis-les depuis le code.
- Quand tu as appliqué ou écarté ces retours, appelle `resolve_feedback(number: 42)`.
  Sans cela, ce feedback te sera re-servi.

## Contexte

| | |
|---|---|
| Projet | `/Users/…/shop-front` |
| Détection | **certaine** — session Claude Code vivante sur ce répertoire (pid 20378, il y a 12 s) et cwd du shell Warp au premier plan concordant |
| Git | `feat/checkout-coupon` @ `a3f19c2`, 3 fichiers modifiés non commités |
| Application testée | Google Chrome — fenêtre « Panier — Boutique Démo », 1512×982 pt |
| Écran | Display 1, 1728×1117 pt @2×, capture native 3456×2234 px |
| Interruptions | aucune |
| Statut | **nouveau** |

## Marque 1 — 00:21 — `mal aligné`

> « Le bouton Valider la commande, là il touche le bord de la carte. Il manque du
> *pratique* **[padding ?]** à droite, comme sur les autres boutons de la page. Et il est
> pas aligné avec le champ code promo au-dessus. »

**Zone entourée** : rectangle 372×72 pt à (988, 806), coin inférieur droit de la carte de
récapitulatif de commande.

**Captures**
- Recadrage : `/Users/…/frames/crop-01.png` — 756×532 px, **513 jetons** ← à privilégier
- Fenêtre entière : `/Users/…/frames/full-01.png` — 1316×868 px, **1 457 jetons**

## Marque 3 — 01:38 — `ne marche pas`

> « Et le total en bas, il bouge pas. J'ai changé la quantité de deux à quatre, la ligne
> article s'est mise à jour, le sous-total aussi, mais le total TTC il est resté à
> quarante-sept quatre-vingts. Il se met à jour seulement si je clique ailleurs. »

**Zone entourée** : rectangle 268×44 pt à (1204, 918), ligne « Total TTC ».
**Écran en mouvement à cet instant** : oui — deux frames de contexte disponibles (`-0,8 s`, `+0,4 s`).

**Captures**
- Recadrage : `/Users/…/frames/crop-03.png` — 700×448 px, **400 jetons** ← à privilégier

## Commentaires généraux

- **01:52** — « De manière générale toute la page rame dès que je touche à une quantité.
  On dirait que ça recalcule tout le panier à chaque frappe. »

## Récapitulatif

| Marque | Recadrage | Jetons | Fenêtre entière | Jetons |
|---|---|---|---|---|
| 1 | `crop-01.png` 756×532 | 513 | `full-01.png` 1316×868 | 1 457 |
| 2 | `crop-02.png` 868×560 | 620 | `full-02.png` 1316×868 | 1 457 |
| 3 | `crop-03.png` 700×448 | 400 | `full-03.png` 1316×868 | 1 457 |
| | **Total recadrages** | **1 533** | **Total fenêtres** | **4 371** |

Une version haute résolution (2380×1540, ~4 675 jetons) est générable à la demande via
`get_feedback_frames(view: "full_hires")`. N'y va que pour lire du texte fin.

## Suite

1. Applique marque par marque. En cas d'ambiguïté, charge le **recadrage**, pas la fenêtre.
2. Un commit par marque facilite la relecture.
3. Termine par `resolve_feedback(number: 42, status: "handled", note: "…")`.
````

### 9.5 Manifeste — extraits significatifs

```json
{
  "schemaVersion": "1.1",
  "session": {
    "number": 42, "uuid": "5f2c…", "id": "0042-20260819-1432-checkout",
    "startedAt": "2026-08-19T14:32:46.031+02:00",
    "durationSeconds": 134.85, "wallDurationSeconds": 134.85,
    "tool": { "name": "Regarde", "version": "0.5.0", "os": "macOS 26.1", "build": "25B78" },
    "locale": "fr-FR", "audioInputLatencyMs": 18,
    "captureSegments": [{
      "index": 0, "displayID": 1, "codec": "hevc", "fps": 15,
      "firstSamplePTSSeconds": 0.412, "lastSamplePTSSeconds": 134.60,
      "pixelSize": { "w": 3456, "h": 2234 }, "deleted": true
    }]
  },
  "marks": [{
    "number": 1, "kind": "rect", "sessionTime": 21.381, "captureSegment": 0,
    "isRetroactive": false, "intents": ["alignement"],
    "geometry": {
      "points":     { "x": 988,  "y": 806,  "w": 372, "h": 72 },
      "pixels":     { "x": 1976, "y": 1612, "w": 744, "h": 144 },
      "normalized": { "x": 0.5718, "y": 0.7216, "w": 0.2153, "h": 0.0645 },
      "frameContentRect": { "x": 0, "y": 0, "w": 3456, "h": 2234 },
      "frameScaleFactor": 2.0
    },
    "frames": { "crop": "crop-01", "full": "full-01" },
    "screenWasMoving": false,
    "voice": [{
      "id": "v-002", "attachedTo": 1,
      "attachment": { "rule": "fenetreDeParole", "auto": true, "editedByUser": false },
      "onset": 27.02, "end": 31.55,
      "text": "Il manque du pratique [padding ?] à droite, comme sur les autres boutons.",
      "rawText": "Il manque du pratique à droite, comme sur les autres boutons.",
      "lexiconSuggestions": [{ "heard": "pratique", "suggested": "padding", "confidence": 0.41, "at": 27.72 }]
    }]
  }],
  "frames": [{
    "id": "crop-01", "role": "crop",
    "absolutePath": "/Users/…/frames/crop-01.png",
    "size": { "w": 756, "h": 532 }, "sourcePixels": { "w": 756, "h": 532 },
    "visualTokens": 513, "visualTokensNote": "min(patches, plafond du palier)",
    "bytes": 173044, "marks": [1], "engravedMarks": [1],
    "cropRectPixels": { "x": 1664, "y": 1420, "w": 756, "h": 532 }, "scaleFromSource": 1.0,
    "occludedWindowsMasked": 1
  }],
  "budget": {
    "reportTokensEstimate": 1180, "estimateMethod": "approximation 4 car./jeton, pas un tokeniseur",
    "framesTokens": { "crop": 1533, "full": 4371, "full_hires": 14025 },
    "recommendedPlan": "Texte seul (1 610 jetons) suffit pour 1 et 3. Charge crop-02 si l'état visuel du champ en erreur est utile. Total conseillé : 2 230 jetons.",
    "mcpHardLimit": 25000
  }
}
```

### 9.6 Formule de coût, corrigée

```
tokens_visuels(l, h) = min( ceil(l/28) × ceil(h/28) , plafond_du_palier )
```

Le volet 3 initial appliquait la formule brute et annonçait 9 920 jetons pour une capture native 3456×2234, alors que l'API redimensionne d'elle-même et facture le plafond du palier (4 784 en haute résolution, 1 568 en standard). Comme le produit vend à l'agent sa capacité à arbitrer sur le coût annoncé, l'annonce doit être exacte.

| Image | Dimensions | Jetons |
|---|---|---|
| Capture native Retina 16" | 3 456 × 2 234 | 4 784 (plafond) |
| `full_hires` optimal | 2 380 × 1 540 | 4 675 |
| `full` optimal (palier standard) | 1 316 × 868 | 1 457 |
| `crop` typique | 756 × 532 | 513 |

L'estimation des jetons de **texte** est étiquetée comme une approximation : aucun tokeniseur n'est embarqué.

### 9.7 Les cinq outils MCP

Serveur `regarde` (nom non réservé), transport **stdio uniquement**. Le transport HTTP local est coupé du MVP : la conception reconnaissait elle-même qu'une URL à port aléatoire ne peut pas figurer dans une configuration client stable.

| Outil | Annotations | Rôle |
|---|---|---|
| `list_feedback` | `readOnlyHint` | Sessions non traitées, métadonnées seules, < 300 jetons |
| `get_feedback` | `readOnlyHint`, `maxResultSizeChars: 60000` | **Jamais d'image.** Markdown rendu + `structuredContent` réduit + chemins absolus + coût |
| `get_feedback_frames` | `readOnlyHint` | Images, `view: crop|full|full_hires`, `max_tokens` défaut 8 000, plafond 20 000 |
| `get_feedback_context` | `readOnlyHint`, `maxResultSizeChars: 60000` | Contexte brut d'une marque (vide au MVP, actif au lot 9) |
| `resolve_feedback` | `idempotentHint` | `in_progress` / `handled` / `dismissed`, par marque ou global |

**Corrections mécaniques par rapport à la conception initiale :**
- `maxResultSizeChars` ramené de 120 000 à **60 000** : à 4 caractères par jeton, 120 000 autorise 30 000 jetons, au-dessus du plafond dur de 25 000 de Claude Code, ce qui fait échouer l'appel en bloc.
- `outputSchema` **inliné**, jamais un `$ref` vers un hôte inexistant (`https://regarde.local/…`) : un client qui tente de le résoudre échoue ou refuse l'outil.
- Base64 **brut** dans `data`, sans préfixe `data:` : c'est l'erreur la plus fréquemment rapportée sur les serveurs MCP images.

**Résolution du projet par le sidecar.** Le comportement « cwd, puis racine git » échoue sur deux des trois clients cibles : Cursor et Zed lancent fréquemment un serveur MCP déclaré en configuration globale avec le cwd de l'application ou `/`. Ordre retenu : cwd → remontée vers un `.regarde/` parent → **index utilisateur** `~/Library/Application Support/Regarde/projects.jsonl` (maintenu par l'application) → erreur explicite listant les candidats.

**TCC du sidecar.** `resolve_feedback` écrit dans le projet ; le sidecar hérite de l'identité TCC du processus qui le lance. Si le projet est sous `~/Documents` ou `~/Desktop`, le premier appel déclenche une invite « fichiers et dossiers » **au nom de Claude Code**, en plein tour d'agent, et échoue sur `EPERM`. À tester explicitement au lot 6 et à documenter.

### 9.8 Budget d'une session type

| Poste | Chemin nominal | Escalade fenêtre | Chemin naïf |
|---|---|---|---|
| `report.md` | 1 180 | 1 180 | 1 180 |
| `structuredContent` réduit | 430 | 430 | 3 800 (manifeste entier) |
| Images | 1 crop = **513** | 3 fenêtres = **4 371** | 3 captures natives = **14 352** |
| **Total** | **2 123** | **5 981** | **19 332** |
| Coût entrée Opus 5 | ~0,011 USD | ~0,030 USD | ~0,097 USD |

Beaucoup de sessions se traitent **sans charger la moindre image**. Coût médian attendu : 1 600 à 2 500 jetons.

### 9.9 État et anti-relecture

`state.jsonl`, append-only, rejoué à la lecture. États : `new → delivered → in_progress → handled | dismissed`, plus `stale` après 14 jours sans lecture et `reopened` (produit par « Reprendre le feedback #N » dans la barre de menus). La résolution est par marque quand `marks` est présent.

Trois couches empêchent la relecture : filtrage par défaut dans `list_feedback` ; bandeau « DÉJÀ TRAITÉ le … par … » en première ligne de `get_feedback` avec la note de résolution ; `resolve_feedback` décrit comme obligatoire à trois endroits que l'agent lit forcément.

**Chaînage des sessions.** « Reprendre le feedback #42 » ouvre une session pré-chargée avec les marques non résolues de #42, positionnées en coordonnées normalisées. `⌥⌘`-clic sur une marque héritée la marque `corrigé` ou `toujours KO` (avec commentaire vocal facultatif). Le rapport #43 s'ouvre sur : « Suite du #42. Marques 1 et 4 corrigées et vérifiées. Marque 3 toujours en échec après ta correction *<note>*. Nouvelle régression en marque 7. » Gain de contexte majeur pour l'agent, coût nul en jetons.

### 9.10 La phrase du presse-papiers, et son cycle de vie

```
Lis le feedback #42 avec regarde (get_feedback number=42) puis applique les corrections. Si l'outil n'est pas disponible, lis /Users/…/shop-front/.regarde/sessions/0042-20260819-1432-checkout/report.md
```

Une seule ligne, sans retour chariot. `puis applique les corrections` est la clause la plus importante : sans elle, l'agent lit et résume alors que le développeur veut qu'il code. La clause de repli avec chemin absolu fait qu'aucune session n'est perdue à cause d'un problème d'intégration.

**Trois corrections sur le cycle de vie, absentes de la conception initiale :**

1. **Sauvegarde et restauration.** Le presse-papiers est lu à l'ouverture de session et restauré si l'utilisateur n'a pas collé dans les 60 s (`changeCount` indique s'il a été touché). Écraser sans prévenir le presse-papiers d'un développeur est un comportement qu'aucun outil de développement ne se permet.
2. **Persistance dans la barre de menus.** Les trois derniers feedbacks y sont listés, un clic recopie la phrase. La perte devient rattrapable.
3. **Fermeture du geste.** Le bandeau propose « ⏎ Envoyer à \<agent détecté\> » : activation de la fenêtre de l'agent et injection du texte (AX `setValue` sur le champ de saisie, repli sur synthèse `⌘V`). Best-effort, avec repli silencieux sur le presse-papiers seul en cas d'échec. Trois heures de travail pour le dernier mètre du parcours.

### 9.11 Modes dégradés

**Sans MCP, avec accès au disque** (Cursor, Zed, Windsurf, serveur non approuvé) : la clause de repli de la phrase suffit. L'agent lit `report.md`, y trouve les chemins absolus, les ouvre avec son propre outil. Le rapport porte une consigne de repli pour écrire une ligne dans `state.jsonl` à la place de `resolve_feedback`.

**Chat web, sans accès au disque** : bouton « Copier pour un chat web ». Le presse-papiers reçoit `paste-web.md` — chemins remplacés par des noms de fichiers, géométrie décrite en mots, ordre des images annoncé en tête, aucun chemin absolu (ils divulgueraient l'arborescence dans un service tiers), section « Ce que j'attends de toi » demandant des diffs plutôt que des modifications. Le Finder s'ouvre sur `frames/` avec les recadrages présélectionnés.

**Dernier recours** : `report.md` est du Markdown, les PNG sont des PNG, `manifest.json` est du JSON. Aucun format propriétaire, aucune base de données. Le format survit à l'outil.

---

## 10. Vie privée et sécurité

Le produit filme l'écran entier et ouvre le micro. Les garanties doivent être explicites et vérifiables, pas implicites.

### 10.1 Ce qui ne sort jamais de la machine

La transcription est intégralement locale (`SpeechAnalyzer`, modèles gérés par MobileAsset, exécutés hors de l'espace d'adressage de l'application). Aucune connexion réseau sortante n'est effectuée par Regarde. Le seul transfert vers un tiers est celui que l'utilisateur déclenche lui-même en collant la phrase dans son agent — et ce que l'agent lit alors, ce sont les artefacts du projet.

### 10.2 Le fichier vidéo intermédiaire

Il contient tout l'écran : gestionnaire de mots de passe ouvert à côté, messagerie, autre projet client. Quatre mesures :

1. **Écriture dans `NSTemporaryDirectory()`** (`/var/folders/.../T/`), exclu de Time Machine et purgé par le système. La conception initiale l'écrivait dans `~/Library/Application Support/`, **inclus dans les sauvegardes Time Machine par défaut** : une session qui plante y laissait une copie permanente sur le disque de sauvegarde, que la purge à 24 h ne touche jamais. À défaut, `URLResourceValues.isExcludedFromBackup = true`.
2. Répertoire en `0700`, fichier en `0600`, création en `O_EXCL`.
3. Purge **au démarrage de chaque session**, pas seulement au lancement de l'application.
4. Suppression immédiate en `publishing`, dès que toutes les frames sont extraites.

### 10.3 Contrôle du contenu capturé

**Liste noire d'applications dans le filtre de capture.** `SCContentFilter(display:excludingApplications:)` accepte déjà une liste ; l'utiliser pour autre chose que s'exclure soi-même coûte une ligne. Par défaut : 1Password, Trousseau d'accès, Messages, Mail, Signal, WhatsApp. Éditable dans les réglages.

**Masquage des fenêtres tierces à la composition** (§ 5.6) : notifications, Slack, autres onglets. C'est aussi ce qui empêche la spirale d'autocensure — la première fois qu'un développeur voit une notification privée dans une capture partie chez un tiers, il ferme Slack avant chaque session ou n'utilise plus l'outil.

**Rédaction de secrets par motifs**, appliquée à tout fragment de contexte et à `paste-web.md` : `Bearer`, `api[_-]?key`, `password`, `secret`, `token`, forme JWT, `AKIA…`, `sk-…`. Trente lignes de code, et le contrôle le plus rentable du produit. La conception initiale ôtait les chemins absolus de `paste-web.md` « pour ne pas divulguer l'arborescence » tout en y publiant les corps de requête HTTP : modèle de menace incohérent.

**Vignettes de contrôle.** La revue affiche une bande des images qui vont être écrites, avec suppression d'un clic. Réutilise ce qui est déjà calculé.

### 10.4 Micro

Ouvert par fenêtre de parole uniquement (§ 3.5), fermé sans exception en `suspended`, fermé d'office quand `IsSecureEventInputEnabled()` passe à vrai. Le point orange système est non contournable et souhaitable : le HUD affiche explicitement l'état du micro et le nom du périphérique retenu, pour que l'indicateur ne soit jamais une surprise. Verrouillage micro (⌃⌥M) signalé par un bandeau permanent. À ne pas confondre avec ⌃⌥L, qui verrouille le **mode annotation** (§ 6.3) : deux fonctions distinctes, deux raccourcis distincts.

### 10.5 Rétention et suppression

Politique paramétrable, défaut : les sessions `handled` de plus de 90 jours voient leur dossier `frames/` supprimé, `report.md` et `manifest.json` conservés. Une commande de l'application et un sixième outil (`delete_feedback`, ajouté au lot 6) suppriment une session complète. `index.jsonl` conserve une entrée tombstone.

### 10.6 Indicateurs système

Le pré-roll, s'il est activé, allume l'indicateur de capture d'écran en permanence. C'est non désactivable et assumé : l'icône de la barre de menus de Regarde reflète toujours l'état réel (gris = inactif, bleu = pré-roll, rouge = session).

---

## 11. Plan de lots

### 11.1 Calibrage

Estimations pour un développeur expérimenté dont l'écosystème natif est React/TypeScript, non Swift/AppKit. Multiplicateurs par rapport à un praticien Swift : logique métier et MCP ×1,0 ; SwiftUI ×1,2 ; AppKit ×1,8 ; `CGEvent` tap et callbacks C ×2,0–2,5 ; ScreenCaptureKit + `CMTime` ×2,0 ; concurrence Swift 6 stricte ×1,5 transverse ; signature et TCC ×2,0.

Trois pertes de temps à budgéter : pas de hot reload (20 à 40 s par itération sur l'overlay contre 2 s en React) ; le débogage TCC est aveugle (`tapCreate` renvoie `nil`, la capture sort noire, aucune exception) ; la re-signature peut désactiver silencieusement le tap.

**Total MVP : 40 journées-homme.** Environ 8 semaines à temps plein, ou 4 à 5 mois en projet personnel du soir et du week-end.

### 11.2 Lot 0 — Prototype de risque

**2,5 j** (la conception initiale annonçait 1 j en additionnant 8 h de tâches *à vitesse nominale*, sans appliquer ses propres multiplicateurs. C'est le lot qui porte le GO/NO-GO n°1 : le sous-estimer pousse à le bâcler.)

Un bundle `.app` minimal signé ad hoc, `LSUIElement = 1`, contenant : une `NSPanel` par écran conforme au § 6.1 ; un `CGEventTap` sur thread dédié écoutant souris **et `keyDown`** ; la porte à verrou du § 6.2 ; le ré-armement et le watchdog ; un `CAShapeLayer` alimenté par ring lock-free et display link ; l'instrumentation de latence ; les preflights de permissions.

Test contre trois applications témoins : page web animée en plein écran dans Chrome (horloge à trotteuse), Simulateur iOS en animation, terminal avec `top`.

| # | Critère | Mesure |
|---|---|---|
| C1 | Sans modificateur, tous les clics atteignent l'application testée | Bouton cliqué, texte sélectionné normalement |
| C2 | Avec ⌥⌘, aucun événement souris n'atteint l'application testée | ⌥⌘-glisser ne sélectionne pas de texte |
| C3 | L'application testée continue de s'animer | La trotteuse tourne pendant le tracé |
| **C3b** | **Cadence quantifiée** | Deltas de `requestAnimationFrame` sur une page WebGL plein écran, avec et sans calque : **< 5 % de dégradation** |
| C4 | Focus jamais perdu | Le curseur de saisie continue de clignoter dans l'application testée |
| C5 | Premier point jamais perdu | 20 tracés démarrent exactement sous le curseur |
| C6 | Relâcher le modificateur en plein tracé ne produit pas d'événement orphelin | Glisser un fichier dans le Finder : aucun drag fantôme |
| C7 | Latence p95 | < 33 ms, objectif < 16 ms |
| C8 | Survie au changement de Space et au plein écran natif | Trait visible au-dessus de Safari plein écran |
| C9 | Non happé par Stage Manager | — |
| C10 | Tap actif après 30 min | Watchdog sans désactivation non ré-armée |
| **C11** | **Appariement marque ↔ frame** | Compteur d'images affichant son propre numéro à l'écran ; le numéro gravé et le numéro affiché coïncident |
| **C12** | **Événements synthétiques** | Test avec Karabiner ou un pilote de souris tiers installé : aucune marque rejetée |

Sortie : si C1 à C6 et C3b passent, le lot 1 démarre. Si C3b échoue, l'ordonnancement du calque à la demande (§ 6.1) est déjà la parade et doit être vérifié avant d'aller plus loin.

### 11.3 Les lots

| Lot | Périmètre | Effort | Critère de réussite observable |
|---|---|---|---|
| **1 — Socle et vérité sur les permissions** | Bundle Developer ID, Hardened Runtime, entitlements, `NSMicrophoneUsageDescription`. **Mode `doctor`** (CLI + HUD) : Screen Recording, Input Monitoring, Accessibilité, Micro, Secure Input, création effective du tap, écrans et `backingScaleFactor`, périphériques audio avec repérage des boucles. Bouton d'ouverture du volet de Réglages et bouton « Relancer » par ligne. **Prise de contact TCC hors chemin de session** : `SCShareableContent.getShareableContent` au lancement et au réveil, jamais au raccourci. Raccourcis Carbon : ⌃⌥S ouvrir, ⌃⌥F terminer, ⌃⌥M verrou micro, ⌃⌥L mode annotation verrouillé. `NSStatusItem` portant l'état de session. HUD SwiftUI minimal. **Liste noire d'applications et `$TMPDIR` sécurisé.** | **3,5 j** | Sur un compte vierge, les 4 permissions sont accordées en moins de 3 clics chacune et l'état passe au vert après relance. Le raccourci ouvre le doctor sans aucune permission. |
| **2 — Marques et export : premier produit utilisable** | Panneaux industrialisés (reconstruction sur `didChangeScreenParameters`, gel sur `didChangeOcclusionState`). Quatre outils : flèche, cadre, point, surlignage. Palette d'intentions ⌥⌘+1..6. Numérotation définitive au `mouseDown`, `Échap` et `⌘Z`. Ancrage à la fenêtre cible, `⌥⌘⇧` d'échappement. **Mode éclair du § 2.1.** Capture par `SCScreenshotManager.captureImage` ponctuel (pas encore de flux continu). Gravure des numéros, écriture dans `~/Regarde/sessions/<date>/`. | **5,5 j** | Session de 3 min sur une vraie application : 6 marques, 4 outils, 2 écrans dont un externe non-Retina **placé à gauche** (origine négative). 6 PNG au bon endroit, bon numéro, **aucun pixel du calque ni du HUD**, aucun décalage ×2. |
| **3 — Capture continue et ancrage exact** | `SCStream` par écran, config native, HEVC + `AVAssetWriter` GOP 1 s. Filtrage `.complete`, anneau de 4 frames dans un pool applicatif. **`firstSamplePTS` et `assetTime()` avec clampage (B1).** **Appariement marque ↔ frame sur la file d'encodage (B2).** **Géométrie relative au `contentRect` de la frame (B3).** Décision de burst. Finalisation **par segment**. Pré-roll opt-in, segments roulants. Marques rétroactives. | **6,5 j** | Sur une page animée, 8 marques pendant l'animation : les 8 images montrent l'état exact désigné, vérifié contre un enregistrement témoin. Traitement final < 3 s. RSS < 200 MiB, CPU < 3 %, disque < 500 MiB pour 10 min. Débranchement d'écran en pleine session : les marques de cet écran ont leur image. |
| **4 — Rapport, projet, presse-papiers : boucle complète** | Bibliothèque de rendu partagée (manifeste → Markdown). Deux variantes d'image, formule de jetons avec plafond, masquage des fenêtres tierces, **rédaction de secrets**. Détection du projet à trois états, tranchée **à l'ouverture**. `.regarde/`, `.gitignore`, `index.jsonl` sous verrou, `state.jsonl`. Presse-papiers avec sauvegarde/restauration, historique dans la barre de menus, `AgentInjector` best-effort. | **4,5 j** | Cycle complet sans intervention : raccourci → 5 marques → raccourci → ⏎ → l'agent lit et produit un diff pertinent. Projet correct sur 10 sessions dans 5 projets, ou affiché ambigu quand il l'est. Zéro fichier hors du projet attendu. |
| **5 — Voix et texte** | `AVAudioEngine` par fenêtre de parole, converter unique, latence d'entrée mesurée. `SpeechAnalyzer` + `SpeechDetector`. Injection de la timeline. Rattachement par fenêtre. Réaffectation ⌥⌘+chiffre avec badge sur le calque. Sélection du micro et exclusion des boucles. **Lexique déterministe** (200 termes + identifiants du projet). Saisie clavier via `NSTextView` hors écran. Bandeau de confirmation et revue à la demande (édition inline, suppression, vignettes). | **6 j** | **Mesure préalable sur voix réelle.** Session de 3 min, micro interne, bureau bruyant : 6 observations, **6 rattachées à la bonne marque** (le rattachement par fenêtre est déterministe). Aucune perte des 3 dernières secondes. Texte brut toujours conservé. |
| **6 — Serveur MCP** | Sidecar stdio, SDK Swift 0.12.1 **isolé derrière une couche interne mince**. Six outils (les cinq + `delete_feedback`). `get_feedback` sans image. Résolution du projet par index utilisateur. Journal rejoué, bandeau « DÉJÀ TRAITÉ ». Chaînage « Reprendre le feedback #N ». Commande « Configurer mon agent » (Claude Code `--scope user`, Cursor, Zed, Windsurf). Validation MCP Inspector avant tout client réel. | **3,5 j** | Le même rapport lu correctement par Claude Code, Cursor et Zed, **application fermée**. Aucun appel > 10 000 jetons. Une session `handled` n'est plus proposée à un second agent. Test explicite d'un projet sous `~/Documents` (TCC du sidecar). |
| **7 — Robustesse** | Segments multiples, `-3821` avec redémarrage et annotation d'interruption. Second flux paresseux au changement d'écran. Veille, réveil, branchement, résolution. `passthrough` forcé en `suspended` et `blocked`. Secure Input : fermeture de la fenêtre de parole. Mission Control : gel du rendu. Auto-test de la régression macOS 26.3/26.4. **Second chemin d'entrée sans tap** (parade R9 uniquement, 1,5 j des 5). Auto-pause d'inactivité à 60 s. Plafond de durée qui envoie en revue, jamais en publication automatique. | **5 j** | Session de 10 min avec débranchement d'écran, veille de 30 s, deux Mission Control, une saisie 1Password, un changement de micro : **aucune marque perdue**, interruptions mentionnées, tap actif à la fin. |
| **8 — Distribution** | Signature de l'application **et du sidecar**, notarisation, agrafage, DMG. Onboarding séquencé : Écran → Input Monitoring + Accessibilité (requis) → Micro → pré-roll (opt-in expliqué). Documentation de l'invite mensuelle. | **3 j** | DMG téléchargé depuis une autre machine, installé sans avertissement Gatekeeper, onboarding complet en moins de 3 min sur un compte vierge. |

### 11.4 Séquencement et points de décision

```
Lot 0 ──[GO/NO-GO 1 : le geste marche-t-il, et a quel cout de composition ?]──> Lot 1 ─> Lot 2 ══> UTILISABLE (mode eclair + export manuel)
                                                                                          │
                                                                                          ├─> Lot 3 ─> Lot 4 ══> UTILISABLE (boucle complete)
                                                                                          │                  │
                                                                                          │                  ├─> Lot 5 (voix + texte)
                                                                                          │                  └─> Lot 6 (MCP)
                                                                                          └──────────────────────> Lot 7 ─> Lot 8 ══> DISTRIBUABLE
```

**GO/NO-GO n°2, fin du lot 4** : après deux semaines d'usage quotidien, le rapport fait-il gagner du temps par rapport à une capture collée ? Si non, la voix et le MCP n'y changeront rien. C'est un point d'arrêt honorable.

### 11.5 Lots post-MVP

| Lot | Périmètre | Effort |
|---|---|---|
| 9 — Providers natifs | Registre avec budget 150/250 ms, liste noire, consentements depuis les réglages uniquement. Terminal via AX (tronqué aux 80 dernières lignes), Simulateur via `simctl`, URL via AppleScript. | 5 j |
| 10 — Extension Chrome MV3 | Sélecteur CSS sous la marque, console à la source, WebSocket vers 127.0.0.1. **CDP définitivement écarté.** | 5 j |
| 11 — Canal push Claude Code | `capabilities.experimental["claude/channel"]`. Jamais sur le chemin critique. | 3 j |
| 12 — Mode économe explicite | Bascule demi-résolution/2 fps en session pour les tests de performance. | 1 j |

---

## 12. Risques

| # | Risque | Prob. | Impact | Signal précoce | Parade |
|---|---|---|---|---|---|
| R1 | **Permissions multiples et rebutantes.** 4 autorisations TCC, dont deux exigent un redémarrage, plus une ré-autorisation mensuelle de la capture d'écran qui se déclenche au premier appel touchant au contenu partageable. | Certaine | Élevé — premier contact, abandon définitif | Plus de 5 min pour un état « tout vert » sur un compte vierge ; ou on ne sait pas soi-même laquelle manque | Doctor au **lot 1**, avant tout le reste. Prise de contact TCC **hors chemin de session** (`getShareableContent` au lancement et au réveil), sondage horaire, pastille dans la barre de menus. Onboarding séquencé. Ne pas espérer `com.apple.developer.persistent-content-capture`. |
| R2 | **Rapport dans le mauvais projet.** La confirmation se dégrade en réflexe. | Moyenne | Élevé — silencieux, découvert dans une PR | Le HUD affiche le même niveau de confiance quel que soit le contexte | Trois états visuellement distincts, tranchés **à l'ouverture** de session. Validation stricte : chemin absolu, existant, avec marqueur de projet. Jamais trancher entre plusieurs `cwd` de shells. |
| R3 | **Explosion du coût en jetons.** Formule sous-estimée d'un facteur 2 à 3. | Élevée si rien n'est fait | Moyen à élevé | Erreur « response exceeds maximum allowed tokens (25000) », ou l'agent perd le fil | Formule avec plafond de palier, coût affiché marque par marque. `get_feedback` sans image. Recadrage par défaut. **Chemin de fichier absolu comme canal principal.** |
| R4 | **Latence de bascule, événements volés.** | Moyenne si l'architecture dérive | Élevé — corruption de l'état de l'application testée | Le trait démarre à côté du point de départ | Le tap arbitre, `ignoresMouseEvents` reste à `true`. Machine à verrou. Validé au lot 0. |
| R5 | **Frames décalées (B1).** `SessionTime` ≠ temps de l'asset. | Élevée si non traitée | Élevé — le produit devient faux | Invisible sur écran statique ; visible seulement au test C11 | `firstSamplePTS` + `assetTime()` avec clampage, dès le lot 3, avec le test du compteur d'images. |
| R6 | **Crash intermittent sur l'instantané (B2).** | Moyenne | Élevé — non reproductible, chemin critique | `EXC_BAD_ACCESS` dans `CVPixelBufferRelease`, fréquence proportionnelle à l'activité de l'écran | Le tap ne touche jamais un buffer. Appariement sur la file d'encodage, anneau de 4 frames. |
| R7 | **Qualité du français sur le jargon.** Erreurs *plausibles* non détectables par la confiance. | Élevée | Moyen | Relire ses rapports : plus d'un terme sur trois à corriger mentalement | Lexique déterministe + identifiants du projet, édition inline, texte brut toujours conservé. **Mesure sur voix réelle avant le lot 5.** |
| R8 | **L'outil fausse le test de performance qu'il sert à diagnostiquer.** | Moyenne | Moyen — insidieux, on optimise un faux problème | FPS mesurablement plus bas session ouverte | Calque ordonné **pendant le tracé seulement**. Aucun `NSVisualEffectView`, aucun flou, aucune ombre. Critère C3b quantitatif au lot 0. Mode économe explicite (lot 12). |
| R9 | **Tap désactivé silencieusement.** Timeout, entrée utilisateur, re-signature. | Moyenne | Moyen à élevé | « Ça marchait il y a dix minutes » | Traitement dans le callback, watchdog à 5 s vérifiant l'activité et pas seulement `tapIsEnabled`. Budget strict dans le callback. |
| R10 | **Régression Apple sur les fenêtres transparentes plein écran** (FB21879057). | Moyenne | Élevé si l'architecture en dépend, faible sinon | Auto-test au lancement | L'architecture « tap d'abord » y survit. Second chemin d'entrée budgété au lot 7. 1 j par version majeure de macOS pour la revalidation. |
| R11 | **Fuite de contenu privé.** Fichier vidéo sauvegardé, notification dans une capture, secret dans `paste-web.md`. | Moyenne | Élevé — incident, pas bug | Ouvrir une capture et y voir une notification privée | `$TMPDIR` + permissions restrictives + purge par session ; liste noire d'applications ; masquage des fenêtres tierces ; rédaction par motifs ; vignettes de contrôle. Lots 1 et 4. |
| R12 | **Calque dans les pixels capturés.** `sharingType = .none` ne fonctionne plus. | Moyenne | Élevé — numéros doublés, jetons payés pour du bruit | Voir le HUD dans une image exportée | `excludingApplications`. Vérification visuelle à chaque version de macOS. Testé dès le lot 2. |
| R13 | **Conflit du modificateur.** | Moyenne | Moyen — irritant quotidien | Ne plus pouvoir faire un geste habituel | ⌥⌘ configurable, **pas de double-appui**, ancrage à la fenêtre cible, `⌥⌘⇧` d'échappement. |
| R14 | **Dérive des dépendances non contractuelles.** Format `~/.claude/sessions/`, SDK MCP en 0.12.x, spec MCP à deux révisions d'écart. | Moyenne (élevée à 12 mois) | Faible à moyen si l'architecture le prévoit | Une mise à jour de Claude Code et la détection retombe à zéro | Provider avec validation stricte et désactivation propre, repli sur `proc_pidinfo` + git. Jamais décoder le nom de dossier. SDK isolé derrière une couche mince. |
| R15 | **Enlissement du projet personnel.** 40 j sur des soirées, sur une pile inconnue. | Élevée | Élevé — mode d'échec le plus probable | Trois semaines sans commit ; le lot en cours ne produit rien d'utilisable | Produit utilisable dès le lot 2, boucle complète au lot 4. Aucun lot au-delà de 6,5 j. GO/NO-GO n°2 comme point d'arrêt. Lots 9 à 12 interdits avant livraison de 0 à 8. |

---

## 13. Arbitrages en attente

### 13.0 Tranchés par l'auteur le 19 août 2026

| # | Question | Décision |
|---|---|---|
| **A1** | Le pré-roll permanent est-il actif par défaut ? | **Opt-in, proposé une fois à l'onboarding.** L'indicateur système de capture d'écran reste allumé en permanence quand le pré-roll est actif : c'est non contournable, cela doit être un choix conscient. |
| **A6** | Nom du produit et identifiant de bundle. | **Regarde**, `dev.tfoutrein.regarde`, binaire `regarde`, sidecar `regarde-mcp`, dépôt `~/…/TOOLS/regarde`. |
| — | Micro ouvert en continu ou par fenêtre de parole ? | **Fenêtre de parole liée au geste** (§ 3.5), contre le choix initial du micro continu. Le rattachement devient déterministe, ce qui supprime la revue obligatoire de fin de session. Voir ADR-0011. |
| — | Modificateur d'armement du tracé. | **⌥⌘ maintenu**, configurable, sans double-appui (§ 6.3), contre le choix initial de ⌥ seul. Voir ADR-0006. |
| — | Cible d'engagement du développement. | **Lots 0 à 4** (22,5 j), puis GO/NO-GO n°2 sur deux semaines d'usage réel avant d'engager les lots 5 à 8. |

### 13.1 Encore en attente

| # | Question | Recommandation par défaut | Conséquence de l'autre choix |
|---|---|---|---|
| **A2** | La **saisie clavier de texte libre** (au-delà de la palette d'intentions) reste-t-elle dans le lot 5, ou passe-t-elle post-MVP ? | **Dans le lot 5.** Sans elle, aucun mode silencieux, donc aucun usage en open space ou en visioconférence. | Post-MVP : −2 j, et l'outil devient inutilisable dès qu'on ne peut pas parler. La palette d'intentions seule couvre environ la moitié des retours. |
| **A3** | L'**injection dans l'agent** (`AgentInjector` par AX) fait-elle partie du MVP ou reste-t-elle au presse-papiers seul ? | **MVP, en best-effort avec repli silencieux.** Trois heures de travail pour le dernier mètre du parcours ; l'application a déjà l'Accessibilité. | Presse-papiers seul : le geste final reste « changer de fenêtre + coller + Entrée », soit 6 s et une rupture d'attention par session. |
| **A4** | Le **mode éclair** (§ 2.1) écrit-il dans le projet comme une session à part entière, ou dans un dossier léger séparé ? | **Comme une session à part entière**, avec un numéro, un rapport et une entrée dans `index.jsonl`. Un format unique, un seul chemin de code, et le mode éclair bénéficie du chaînage et de `resolve_feedback`. | Dossier séparé : moins de bruit dans `index.jsonl`, mais deux formats à maintenir et un mode qui ne profite pas de l'état « traité ». |
| **A5** | Le plafond de durée de session (défaut 15 min) **envoie en revue avec purge par défaut**, ou publie automatiquement ? | **Revue avec purge par défaut.** Une session qui atteint le plafond est presque toujours une session oubliée ; publier automatiquement un rapport contenant potentiellement une conversation dans un dépôt Git est le pire incident possible. L'auto-pause d'inactivité à 60 s doit de toute façon l'avoir précédée. | Publication automatique : aucune session perdue, au prix d'un risque de fuite. |

Le nom du produit et l'identifiant de bundle ne figurent plus dans ce tableau : **Regarde**, `dev.tfoutrein.regarde`, binaire `regarde`, sidecar `regarde-mcp`, dépôt `~/…/TOOLS/regarde`. Décidé par l'auteur, voir ADR-0001.

---

## 14. Hors périmètre du MVP

| Exclu | Raison |
|---|---|
| **Windows, Linux, iPadOS** | Hors périmètre du MVP, **pas hors trajectoire** : ces portages sont prévus une fois le concept éprouvé sur macOS. Le noyau (`ScreenCaptureKit`, `CGEvent` tap, `SpeechAnalyzer`, `NSPanel`) est intégralement spécifique à la plateforme et devra être réécrit ; le format des artefacts, le contrat MCP, le modèle d'ancrage et le rendu du rapport se portent en l'état. La frontière entre les deux est maintenue nette dès le MVP pour que ce portage reste délimité. |
| **Chrome DevTools Protocol** | Depuis Chrome 136, `--remote-debugging-port` est ignoré sur le profil par défaut : il faudrait relancer Chrome sur un profil jetable, donc demander au développeur de ne plus tester son application comme il la teste. Écarté définitivement au profit d'une extension MV3. |
| **Providers contextuels (URL, sélecteur CSS, console, terminal)** | Le consentement Automation se demande par application cible et son prompt vole le focus en pleine session. Lot 9 et 10, déclenchés depuis les réglages uniquement. L'URL, le titre et les pixels couvrent l'essentiel de la valeur. |
| **Déduplication perceptuelle des frames** | Un dHash est insensible aux petits changements locaux, c'est-à-dire précisément à ce qui déclenche une marque. Bénéfice marginal sur la variante secondaire, risque de rapport faux. Reviendra comparée sur l'union des `bbox`. |
| **Transport MCP HTTP local** | Une URL à port aléatoire ne peut pas figurer dans une configuration client stable ; le stdio couvre les trois clients cibles et fonctionne application fermée. |
| **Vidéo envoyée à l'IA** | Ni Anthropic ni OpenAI ne lisent de vidéo. Le format pivot est une séquence d'images horodatées. Le fichier vidéo est un moyen technique, supprimé en fin de session. |
| **Mode de session sans `CGEventTap`** | Sans tap, il faudrait un second chemin d'entrée complet avec une sémantique différente. Sans Input Monitoring et Accessibilité, il n'y a pas de session, et le doctor le dit. Le second chemin est budgété uniquement comme parade à la régression Apple. |
| **IME asiatiques** | Non couverts proprement par la saisie via tap. Limitation assumée pour un outil personnel francophone. |
| **App Sandbox et App Store** | Incompatible avec l'Accessibilité et `proc_pidinfo` sur les processus voisins ; un tap qui consomme des événements ne passerait pas la revue. |
| **Canal push vers Claude Code** | Le mécanisme existe (`notifications/claude/channel`) mais il est en research preview, limité à Claude Code, exige `claude --channels` et un runtime Node/Bun. Le presse-papiers est universel. Lot 11, jamais sur le chemin critique. |
| **Édition avancée des annotations** | Déplacer, redimensionner, recolorer, gérer des calques. Une session produit 1 à 8 marques en 3 minutes. Seules exceptions conservées : `Échap` pendant le tracé, `⌘Z` après. |
| **Historique, recherche, statistiques des sessions** | Le système de fichiers et `list_feedback` suffisent. Construire une bibliothèque de sessions serait construire un second produit. |
| **Partage, équipe, synchronisation** | Projet personnel. Aucune infrastructure, aucun compte, aucun réseau sortant — ce qui est aussi la garantie de confidentialité de la voix. |
| **Réécriture de la transcription par LLM local** | Le gain est incertain (l'A/B sur `contextualStrings` n'a rien donné) et l'agent destinataire désambiguïse mieux, code en main. Le lexique déterministe couvre le besoin à un coût mesurable. |
| **Mise à jour automatique** | Téléchargement manuel d'un DMG. Sparkle est 1 à 2 jours de plus pour un utilisateur unique. |