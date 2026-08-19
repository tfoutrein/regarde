# Revue du prototype — lot 0

## Verdict

Le prototype n'est pas en état d'être soumis aux douze critères : la porte à verrou laisse échapper des événements souris orphelins vers l'application testée (C2, fatal), le chemin d'encre est faux dès qu'un second écran est branché (C5), et l'instrument qui doit trancher C3b — le témoin WebGL — s'effondre au plancher de charge et rendrait un PASS non mesuré. Il faut corriger les points 1 à 5 avant toute manipulation ; les points 6 à 11 avant de consigner un chiffre dans RESULTATS.md.

## Corrections à appliquer avant toute mesure

### 1. Échap pendant le tracé rend les drags et le mouseUp à l'application testée — C2, fatal

**`Input/OptionGate.swift:223`** (`cancelStroke`), déclenché depuis `EventTap.swift:210-213`.

`cancelStroke()` met `strokeActive = false` et rien d'autre. `decide` n'a que deux états ; une fois le verrou tombé, `.leftMouseDragged` fait `capture = strokeActive` = false → `.pass`, et `.leftMouseUp` de même. Le commentaire de doc juste au-dessus (l. 219-221) affirme l'inverse de ce que le code fait : « le mouseUp qui suivra sera consommé […] l'application n'a pas vu le mouseDown, elle ne doit pas voir le mouseUp ». Le cas `.swallow` de `GateDecision` existe pour cela et n'est jamais produit — c'est la moitié manquante de la porte.

Séquence : ⌥⌘ tenu, mouseDown capturé (l'application ne voit rien) → drags capturés → Échap → **tous les drags suivants et le mouseUp partent vers l'application**, bouton physiquement enfoncé. Dans le Finder, le fichier tenu est lâché sous le curseur. Dans le témoin 1, le DOM reçoit des `mousemove` avec `buttons=1` puis un `mouseup` : tout handler global se déclenche. C2 tombe, C6 avec.

Ajouter le troisième état, propriété du thread du tap :

```swift
/// Le bouton est physiquement enfonce, le trace a ete annule : l'application testee
/// n'a pas vu le mouseDown, elle ne doit voir NI les drags NI le mouseUp.
private var suppressUntilUp = false

func cancelStroke() {
    if strokeActive { suppressUntilUp = true }
    strokeActive = false
    strokeFlag.store(false, ordering: .releasing)
}
```

Dans `decide`, **après** le garde `passthrough` et **après** le calcul de `armed` (pour ne court-circuiter ni `publishState` ni les compteurs) :

```swift
if suppressUntilUp {
    switch type {
    case .leftMouseDragged, .mouseMoved:
        publishState(armed: armed, stroking: false); return .swallow
    case .leftMouseUp:
        suppressUntilUp = false; mouseDownInApp = false
        publishState(armed: armed, stroking: false); return .swallow
    case .leftMouseDown:
        suppressUntilUp = false   // filet : le mouseUp a ete perdu
    default: break
    }
}
```

Et `suppressUntilUp = false` dans `consumePendingReset()` (l. 243-246), sans quoi la porte reste bloquée en avalage après un réveil. Règle invariante à inscrire en tête du fichier : **tant que le bouton physique n'est pas relâché, l'application testée ne reçoit rien de ce clic — elle n'en a pas vu le début.** Ajouter au protocole du § 4.6 : ⌥⌘-glisser sur le champ de texte du témoin 1, Échap sans relâcher, continuer à bouger, relâcher ; attendu : aucune sélection, aucun `mousemove buttons=1`, aucun `mouseup` en console.

### 2. Le ring SPSC a autant de consommateurs que d'écrans branchés — C5, bloquant

**`Overlay/InkView.swift:123`**, avec `Overlay/OverlayController.swift:69-85` et `136-139`.

`InkRing` est documenté et conçu à consommateur unique, et `drain` avance `tail`. Or `showPanels()` démarre un `CADisplayLink` sur **chaque** `InkView` (une par `NSScreen`), et chaque `step()` appelle `InkRing.shared.drain`. Avec deux écrans il y a deux consommateurs : le premier display link déclenché emporte tout, l'autre trouve la file vide. Les deux liens tournant sur `RunLoop.main`, il n'y a pas de course mémoire — mais l'invariant fonctionnel est rompu, et l'écart s'aggrave quand les écrans n'ont pas la même cadence (120 Hz interne / 60 Hz externe).

Deux conséquences composées : chaque vue convertit avec **son** `eventToLocal` (`OverlayController.swift:114-119`), donc un point drainé par le mauvais panneau est construit hors de ses bornes et clippé ; et le `.down` n'initialise `livePoints` que sur une seule vue — celle qui ne l'a pas reçu jette tous ses `.drag` sur le `guard !livePoints.isEmpty` (`InkView.swift:162`). Rien dans le chemin d'encre n'utilise `Coordinates.screen(containingEventLocation:)`, qui existe (`Coordinates.swift:71`) mais n'est appelé que par `SnapshotBench`.

Observé en configuration deux écrans — le « fini quand » de T0.5 : environ un tracé sur deux ne dessine rien, les autres sont amputés de la moitié de leurs points, le trait ne démarre pas sous le curseur. `totalStrokes` monte de deux pour un geste. **Invisible sur une machine mono-écran** : le défaut ne se voit qu'en salle de recette.

Correction retenue : **un seul consommateur, qui diffuse à tous les panneaux**. La diffusion est préférable au routage par point, qui couperait en deux tout trait traversant la frontière inter-écrans à cause du `guard` l. 162 ; le clipping est fait par le WindowServer, pas par du code applicatif.

```swift
// InkView : plus de drainage, plus de onStrokeBegan ; consume et commitFrame internes
func consume(_ event: InkEvent) { /* corps actuel MOINS la ligne onStrokeBegan */ }
func commitFrame() {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    live.path = pathFromLivePoints()
    CATransaction.commit()
}

// OverlayController : un seul pump
private func pump() {
    var latest: UInt64 = 0, n = 0
    InkRing.shared.drain { ev in
        if ev.eventKind == .down { self.strokeDidBegin(ev) }   // capture C11 : UNE seule fois
        for panel in self.panels.values { panel.inkView.consume(ev) }
        latest = max(latest, ev.enqueuedTicks); n += 1
    }
    if n > 0 {
        for panel in self.panels.values { panel.inkView.commitFrame() }
        LatencyHistogram.shared.record(
            millis: SessionClock.millis(from: latest, to: SessionClock.hostTicksNow()))
    }
    afterFrame()
}
var totalStrokes: Int { panels.values.map(\.inkView.strokeCount).max() ?? 0 }
```

Trois pièges à ne pas manquer :
- **`onStrokeBegan` doit sortir de `consume`** (`InkView.swift:157`) : il lance `SnapshotBench.capture` (`OverlayController.swift:103-111`) ; diffusé à N panneaux, un seul trait déclencherait N captures ScreenCaptureKit concurrentes et fausserait l'étalonnage C11.
- **`totalStrokes` doit cesser d'être une somme** (`OverlayController.swift:184`) : avec la diffusion chaque panneau valide sa copie, le rapport (`RunReport.swift:40`) et le menu (`StatusItemController.swift:106`) rendraient N pour un geste.
- **Le display link unique ne doit pas dépendre d'un panneau qui peut disparaître** : si le pilote vit sur la vue de l'écran principal et que cet écran est débranché, `rebuildPanels` (l. 88-92) appelle `stopRendering` sur l'orphelin et le pump meurt en silence. Réélire un pilote dans `rebuildPanels`.

Bénéfice collatéral : `LatencyHistogram.record` cesse d'être appelé une fois par panneau (voir point 11).

Vérification en une ligne : sur deux écrans, tracer 20 traits sur l'écran secondaire ; les 20 doivent démarrer sous le curseur et aucun ne doit apparaître sur l'écran principal.

### 3. `requestReset` et l'entrée en passthrough libèrent un mouseUp orphelin — C6, bloquant

**`Input/OptionGate.swift:243`** (`consumePendingReset`), déclenché depuis `EventTap.swift:162` et `main.swift:66-88`.

Même racine que le point 1, par deux autres chemins. (a) `consumePendingReset()` remet `strokeActive = false` sans mémoriser qu'un clic est en vol : après un `.tapDisabledByTimeout` / `.tapDisabledByUserInput`, ou une entrée en `passthrough` (verrouillage d'écran, économiseur, veille, changement d'utilisateur), le `leftMouseUp` du geste en cours trouve `strokeActive == false` et part à l'application. (b) Le garde `guard currentMode != .passthrough else { return .pass }` (l. 136) est franchi **avant** toute lecture du verrou : même sans reset, tout mouseUp d'un tracé capturé passe dès que le mode bascule. Le § 6.2 place le même garde en tête, mais il ne prévoit pas qu'on entre en passthrough au milieu d'un tracé — le prototype, lui, le fait sur cinq notifications système.

Le dépassement de budget du tap est le scénario **nominal** de T0.8, provoqué exprès.

Correction minimale, alignée sur le § 6.2 qui ne remet pas le verrou à plat — retirer le `requestReset` de `EventTap.swift:157-164` :

```swift
if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    if let port = machPort { CGEvent.tapEnable(tap: port, enable: true) }
    reArmCount.wrappingAdd(1, ordering: .relaxed)
    // Pas de requestReset : le verrou doit tenir jusqu'au mouseUp (C6). Rester
    // « bloque en capture » ne dure que jusqu'au prochain leftMouseDown, seul
    // point de decision d'entree (§ 6.2).
    return nil
}
```

Si l'on tient à conserver la remise à plat pour le cas où le mouseUp a été perdu pendant que le tap était désarmé, elle doit se souvenir du clic en vol — et la suppression doit vivre **après** le garde passthrough, jamais dedans :

```swift
private func consumePendingReset() {
    if pendingReset.exchange(false, ordering: .acquiring) {
        if strokeActive { suppressUntilUp = true }   // le meme drapeau qu'au point 1
        strokeActive = false
        mouseDownInApp = false
    }
}
```

Ne toucher ni au garde `passthrough`, ni à la sémantique de `.pass` en passthrough : le § 6.2 les prescrit tels quels.

### 4. Le calibrage WebGL du témoin ne converge jamais et s'effondre au plancher — C3b, bloquant

**`temoins/index.html:269`**.

Le contrôleur vise `TARGET_MS = 15` avec une bande morte de ±1,5 ms, donc [13,5 ; 16,5]. Sur un écran verrouillé au vsync 60 Hz, le delta de rAF vaut 16,67 ms quand la page tient la cadence — donc `dt > TARGET_MS + 1.5` est vrai **à chaque frame**, et `glLoad--` s'exécute à 60 Hz. En moins de dix secondes `glLoad` tombe de 60 au plancher de 4 et y reste : l'incrémentation exige `dt < 13,5 ms`, valeur qu'un écran 60 Hz ne produit jamais. La cible est dans le trou de quantification du vsync, aucun état atteignable ne satisfait la condition d'arrêt. Sur un panneau 120 Hz le contrôleur oscille (8,33 → incrémente → 16,67 → décrémente) et la charge devient bimodale.

Le § 4.3 demande « assez de travail GPU pour que toute couche de composition supplémentaire se voie » : à `glLoad = 4` le fragment shader fait quatre itérations, le GPU est au repos, et une couche supplémentaire ne coûte rien de mesurable. Le JSON exporté montre `"glLoad": 4` sur tous les relevés, la médiane des trois états est identique à 16,67 ms près, « vs réf. » affiche +0,0 % en vert et `verdicts().c3b` renvoie PASS. **C3b est déclaré passé sans jamais avoir été mesuré.**

Calibrer sur le taux de frames perdues, avec un vsync mesuré à vide et des pas multiplicatifs :

```js
// état ajouté : vsyncMs: null, calWindow: [], calibrated: false
if (state.mode === 'load') {
  resizeGL();
  // 1) Mesure du vsync natif à charge minimale
  if (state.vsyncMs === null) {
    if (glReady) { gl.uniform1i(uLoad, 1); gl.uniform1f(uTime, now * 0.001);
                   gl.drawArrays(gl.TRIANGLES, 0, 3); }
    if (dt > 0) state.calWindow.push(dt);
    if (state.calWindow.length >= 60) {
      const s = state.calWindow.slice().sort((a, b) => a - b);
      state.vsyncMs = s[30]; state.calWindow = [];
    }
    return;
  }
  if (glReady) { gl.uniform1i(uLoad, state.glLoad); gl.uniform1f(uTime, now * 0.001);
                 gl.drawArrays(gl.TRIANGLES, 0, 3); }
  // 2) Calibrage sur le taux de frames perdues, jamais pendant un relevé
  if (!state.sampling && dt > 0) {
    state.calWindow.push(dt);
    if (state.calWindow.length >= 120) {
      const dropped = state.calWindow.filter(d => d > state.vsyncMs * 1.5).length / 120;
      const prev = state.glLoad;
      if (dropped < 0.02)      state.glLoad = Math.min(512, Math.ceil(state.glLoad * 1.35));
      else if (dropped > 0.08) state.glLoad = Math.max(8, Math.floor(state.glLoad / 1.20));
      if (state.glLoad === prev && dropped >= 0.02 && dropped <= 0.08) state.calibrated = true;
      state.calWindow = [];
    }
  }
}
```

Deux répercussions ailleurs dans le fichier :
- `finishRun` doit exporter `vsyncMs`, `glLoad` et `calibrated`, sinon un relevé pris avant convergence est indiscernable d'un relevé valide ;
- `startRun` doit **refuser de démarrer** tant que `calibrated` est faux — c'est ce garde-fou, plus que le contrôleur, qui empêche un PASS non mesuré sur un critère bloquant.

Remarque qui dépasse le contrôleur : la médiane des `dt` de rAF est elle-même quantifiée au vsync, donc elle ne peut pas résoudre une dégradation de 5 %. Une fois la charge rétablie, le seuil du § 4.4 doit se lire sur le **taux de frames perdues** des trois états, pas sur `medianMs`, sans quoi `renderResults` continuera d'afficher « +0,0 % » quel que soit le coût de composition.

(La crainte que l'optimiseur du pilote supprime la boucle du shader n'est pas fondée : `a` dépend de `gl_FragCoord` et de `uTime` et alimente `fragColor`.)

### 5. `glLoad` dérive entre les relevés : les trois états de C3b ne comparent pas la même charge — C3b, bloquant

**`temoins/index.html:270`**.

Le calibrage est gelé pendant un relevé (`if (!state.sampling …)`) mais tourne librement **entre** les relevés — y compris pendant que l'opérateur lance Regarde, ordonne le calque, trace. Le § 4.4 compare la médiane de l'état 3 à celle de l'état 1 en supposant une charge GPU identique ; or entre les deux, le contrôleur a réagi à la dégradation causée par Regarde en abaissant `glLoad`. La différence mesurée est la somme algébrique du coût de composition et de l'allègement du shader — deux effets de signes opposés. Le champ `glLoad` est enregistré par relevé (l. 333) mais rien ne le compare d'un relevé à l'autre et rien n'avertit.

Symptôme : « vs réf. » affiche « -2,3 % » en vert alors que le calque est visiblement composité ; le JSON montre `glLoad: 60` sur `1-reference` et `glLoad: 22` sur `3-trace-continu`.

Correction, à appliquer avec le point 4 (geler une charge collée au plancher ne mesurerait toujours rien) :
1. calibrer **une seule fois**, à l'entrée en mode charge, puis geler définitivement — `state.glLoadLocked` positionné à la fin de la phase de calibrage, condition l. 269 devenant `if (!state.sampling && state.glLoadLocked == null && dt > 0)` ;
2. ne **pas** réarmer le calibrage dans le handler `reset` (l. 458-461), sinon les relevés d'avant et d'après l'effacement redeviennent incomparables ;
3. enregistrer `refreshHz` en plus de `glLoad` dans chaque relevé (l. 328-335) et dans `payload()`, marquer en rouge dans `renderResults()` et **forcer `c3b: 'NON MESURÉ'` dans `verdicts()`** tout relevé dont `glLoad` ou `refreshHz` diffère de `1-reference`, avec la mention « charge différente — non comparable ».

### 6. Le watchdog confond « l'utilisateur ne bouge pas » et « le tap est mort » — C10, majeur, avec une fenêtre C2

**`Input/EventTap.swift:264`**.

`lastEventTicks` n'est mis à jour que dans `handle()` (l. 167), donc uniquement quand un événement du masque arrive ; le masque ne contient que des entrées utilisateur, il n'existe aucune source périodique. Quand l'utilisateur ne touche à rien pendant 30 s — il lit son écran, il regarde une vidéo, ou il exécute précisément le protocole de C10 « laisser tourner 30 min » — `idleMs` dépasse 30 000 alors que le tap est sain, et `checkHealth` déclenche `reinstallOnTapThread` (l. 264-267), qui détruit le `CFMachPort`, retire la source de la run loop et recrée tout. Cela se répète toutes les 30 s d'inactivité. Le mécanisme censé protéger de la panne silencieuse est celui qui la provoque : chaque cycle arme la course du point 8 et expose le thread à la mort du point 7.

Symptôme : le journal affiche « watchdog : actif mais muet — réinstallation complète » régulièrement pendant une session normale ; le compteur de ré-armements du rapport ne veut plus rien dire pour C10. Et à chaque reconstruction il existe une fenêtre de quelques millisecondes sans tap installé : **un ⌥⌘-glisser démarré dans cette fenêtre passe intégralement à l'application testée — échec de C2, causé par le watchdog lui-même.**

Croiser avec l'inactivité réelle de la session (`.anyInputEventType` n'existe pas en Swift) :

```swift
private var silentStreak = 0

private func systemIdleSeconds() -> Double {
    let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseDragged,
                                .keyDown, .flagsChanged, .scrollWheel]
    return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                               eventType: $0) }.min() ?? .infinity
}
```

En remplacement des l. 262-267 :

```swift
// Le silence du tap n'est un symptôme que si le système, lui, voit du trafic.
guard idleMs > 30_000, systemIdleSeconds() < 5.0 else { silentStreak = 0; return }
silentStreak += 1
if silentStreak == 1 {
    log.error("watchdog : muet alors que le systeme voit du trafic — re-armement simple")
    CGEvent.tapEnable(tap: port, enable: true)      // geste non destructif
    reArmCount.wrappingAdd(1, ordering: .relaxed)
    return
}
silentStreak = 0
log.error("watchdog : toujours muet a la seconde detection — reinstallation complete")
reinstallOnTapThread()
```

Ajouter un compteur **distinct** de reconstructions, incrémenté dans `reinstallOnTapThread()` après un `install()` réussi, exposé en `var rebuilds: UInt64`, présent dans `healthLine()` et dans le champ `tap` du `RunReport` à côté de `reArmements`. Sans lui, C10 se mesure aujourd'hui sur un tap qui a pu être détruit et recréé soixante fois sans que rien ne le dise.

### 7. Une réinstallation ratée tue définitivement le thread du tap — C10, majeur

**`Input/EventTap.swift:277`**.

Le thread du tap exécute `CFRunLoopRun()` (l. 80), qui retourne dès que la run loop n'a plus aucune source — le commentaire l. 78-79 le dit. `reinstallOnTapThread` poste un bloc qui appelle `uninstall()` puis `install()` ; `uninstall()` retire la seule source (l. 131). Si `install()` échoue — permission révoquée en cours de session, autorisation perdue après une re-signature, cas décrit au § 4.2 — la run loop se vide, `CFRunLoopRun()` retourne, le thread **sort**. Dès lors `tapRunLoop` pointe sur une run loop dont le thread n'existe plus : chaque `CFRunLoopPerformBlock` ultérieur (une tentative toutes les 5 s, `checkHealth` voyant `machPort == nil`) empile un bloc jamais exécuté. `start()` ne peut pas relancer : `guard thread == nil` (l. 69) est faux pour toujours.

Symptôme : on révoque puis re-accorde Surveillance de la saisie pendant que l'application tourne (ou l'autorisation saute après un build, le quotidien du lot 0) ; le journal affiche une fois « réinstallation impossible », puis « watchdog : aucun port » toutes les 5 secondes indéfiniment. Redonner la permission ne change rien, seul un relancement repart.

Correction principale — ne jamais détruire avant d'avoir reconstruit, dans le bloc de `reinstallOnTapThread` :

```swift
guard let newPort = CGEvent.tapCreate(/* mêmes arguments qu'install() */) else {
    log.error("reinstallation impossible — l'ancien tap est conserve"); return
}
let newSrc = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newPort, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), newSrc, .commonModes)
CGEvent.tapEnable(tap: newPort, enable: true)
uninstall()                       // retire l'ancienne source APRES l'ajout de la nouvelle
machPort = newPort; source = newSrc
installed.store(true, ordering: .releasing)
```

La run loop n'est alors jamais vide, même un instant, et sur échec on garde le tap existant.

En ceinture, pour couvrir l'échec d'installation au démarrage (l. 77) : ajouter une source factice **avant** `CFRunLoopRun()` et supprimer le `guard ok else { return }` —

```swift
var ctx = CFRunLoopSourceContext()
let keepAlive = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &ctx)
CFRunLoopAddSource(CFRunLoopGetCurrent(), keepAlive, .commonModes)
CFRunLoopRun()
```

— et armer `startWatchdog()` inconditionnellement dans `main.swift` (l. 36-37 ne l'arme que si `start()` a réussi). Ne pas remplacer par une boucle `while !shouldStop { CFRunLoopRunInMode(...) }` : inutile avec la source factice, et consommatrice de 100 % d'un cœur sans elle. Si l'on tient à pouvoir relancer le thread, `thread` doit devenir un état protégé, pas un `var` écrit depuis le thread du tap et lu depuis le thread principal.

### 8. `machPort` et `source` sont lus depuis le thread principal alors qu'ils sont écrits depuis le thread du tap — C10, course mémoire

**`Input/EventTap.swift:245`**, et `EventTap.swift:289` (`isEnabled`).

`machPort` et `source` sont déclarés « touchées uniquement sur le thread du tap » (l. 32-35), et le commentaire de `reinstallOnTapThread` (l. 270-271) affirme que « toucher machPort depuis le thread principal serait une course avec le callback ». C'est exactement ce que fait `checkHealth` deux fonctions plus haut : le watchdog est un `Timer` sur `RunLoop.main` (l. 240), sa première ligne est `guard let port = machPort` (l. 245), suivie de `CGEvent.tapIsEnabled` (l. 251) et parfois de `CGEvent.tapEnable` (l. 257). Même accès dans `isEnabled` (l. 289), appelé une fois par seconde par `StatusItemController.refresh()` et par `RunReport.json()`. En face, `install()` et `uninstall()` réassignent depuis le thread du tap (l. 121-122, 137-138). `machPort` est un `var CFMachPort?` : la lecture émet un retain sur la valeur chargée pendant que le thread du tap émet le release en la remplaçant par nil — course sur le compteur de références, le retain pouvant porter sur un objet déjà libéré. Même quand le retain gagne, le port peut avoir été invalidé par `CFMachPortInvalidate` (l. 135) entre le chargement et l'appel.

Le chemin n'est pas théorique : le point 6 le fait emprunter toutes les 30 s d'inactivité réelle.

Symptôme : plantage sporadique (`EXC_BAD_ACCESS` dans `swift_retain` / `CFRetain`) après plusieurs minutes, sans lien apparent avec une action ; ou icône de barre de menus qui passe au rouge de façon fugace alors que le tap fonctionne. Impossible à reproduire à la demande.

Confiner le port au thread du tap **sans** perdre la sonde `tapIsEnabled` et **sans** verrou dans `handle()` :

```swift
private let armedFlag = Atomic<Bool>(false)   // ecrit uniquement sur le thread du tap
var isEnabled: Bool { armedFlag.load(ordering: .acquiring) }   // remplace la l. 289
```

`armedFlag.store(true, ordering: .releasing)` après le `CGEvent.tapEnable` d'`install()` (l. 119) et après le ré-armement du callback (l. 158) ; `false` dans `uninstall()` (l. 139). Puis déplacer `checkHealth` en entier sur le thread du tap, en décidant de la réinstallation sur `installed` (déjà atomique) :

```swift
private func checkHealth() {
    let idleMs = SessionClock.millis(from: lastEventTicks.load(ordering: .relaxed),
                                     to: SessionClock.hostTicksNow())
    guard installed.load(ordering: .acquiring), let rl = tapRunLoop else {
        log.error("watchdog : tap absent — tentative de reinstallation")
        reinstallOnTapThread(); return
    }
    CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue) { [weak self] in
        guard let self, let port = self.machPort else { self?.reinstallHere(); return }
        let enabled = CGEvent.tapIsEnabled(tap: port)
        self.armedFlag.store(enabled, ordering: .releasing)
        // … logique des points 6 et 7, exécutée ici
    }
    CFRunLoopWakeUp(rl)
}

/// Thread du tap uniquement.
private func reinstallHere() {
    uninstall()
    if install() { log.notice("tap reinstalle par le watchdog") }
    else { log.error("reinstallation impossible — verifier Surveillance de la saisie") }
}
```

Ne rien changer à `handle()` : il lit `machPort` l. 158 depuis le thread du tap, ce qui est correct, et y mettre un verrou violerait le budget du § 6.2. Corriger le commentaire l. 32 pour qu'il redevienne vrai, et noter dans RESULTATS.md que la parade complète à R9 reste au lot 7 : cette correction supprime la course, elle ne clôt pas C10.

### 9. « Afficher / masquer le calque » se retire seul au bout de 0,35 s — C8 et C9 non mesurables

**`Overlay/OverlayController.swift:168`** (`afterFrame`) et `:187-189` (`debugToggle`).

`debugToggle()` appelle `showPanels()` sans lever aucun drapeau d'affichage forcé. Dès la frame suivante, `afterFrame()` teste `guard visible, !isArmed, !isStroking` : l'affichage ayant été forcé sans modificateur tenu, la garde passe, `hideWorkItem` est nil, `scheduleHide()` est armé, et le calque disparaît un tiers de seconde plus tard. Le filet de sécurité ne distingue pas « une transition de désarmement s'est perdue » de « l'affichage a été demandé explicitement ».

Le comportement est en outre **non déterministe**, parce que `hidePanels()` (l. 157) ne remet pas `hideWorkItem` à nil après exécution : au tout premier toggle après lancement `hideWorkItem == nil`, le filet se déclenche et le calque s'évapore ; après un premier geste ⌥⌘ complet, `hideWorkItem` reste non nil et la condition l. 169 devient fausse, donc le toggle tient. Le même oubli désarme le filet lui-même — il ne fonctionne aujourd'hui que parce que `stateChanged` (l. 126) remet `hideWorkItem = nil` à chaque armement.

Symptôme : l'opérateur clique « Afficher / masquer le calque » par-dessus Safari en plein écran natif (C8) ou avec Stage Manager actif (C9) ; le calque clignote et disparaît. Il conclut que le panneau ne survit pas au plein écran ou qu'il est happé par Stage Manager — faux négatif sur deux critères. Au deuxième essai, après avoir tracé une fois, le même clic fonctionne : le diagnostic devient irreproductible. « Un critère non mesuré est un critère échoué » (§ 4.6).

```swift
private var pinned = false

func debugToggle() {
    pinned.toggle()
    if pinned {
        hideWorkItem?.cancel(); hideWorkItem = nil
        showPanels()
    } else if !OptionGate.shared.isArmed, !OptionGate.shared.isStroking {
        // Ne jamais arracher le calque sous un geste en cours : la porte continuerait
        // de capturer et l'utilisateur tracerait a l'aveugle.
        hidePanels()
    }
}

private func afterFrame() {
    guard visible, !pinned, !OptionGate.shared.isArmed, !OptionGate.shared.isStroking else { return }
    if hideWorkItem == nil { scheduleHide() }
}

private func scheduleHide() {
    hideWorkItem?.cancel()
    guard !pinned else { hideWorkItem = nil; return }
    let item = DispatchWorkItem { [weak self] in
        MainActor.assumeIsolated {
            guard let self else { return }
            self.hideWorkItem = nil                      // <-- manquant aujourd'hui
            guard !OptionGate.shared.isArmed, !OptionGate.shared.isStroking else { return }
            guard !self.pinned else { return }
            self.hidePanels()
        }
    }
    hideWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideGrace, execute: item)
}
```

Le `guard !pinned` en tête de `scheduleHide` est ce qui évite la régression symétrique : épingler, tracer un geste ⌥⌘, relâcher — le désarmement masquerait un calque explicitement épinglé. Vérifier que `rebuildPanels()` respecte le pin : il appelle `showPanels()` si `visible`, ce qui reste correct puisque `visible` demeure vrai tant que le pin tient.

### 10. Après un `requestReset`, le trait vivant n'est jamais effacé et se rallonge au geste suivant — rendu, majeur

**`Input/EventTap.swift:162`**, effet observé dans `Overlay/InkView.swift:162`.

`requestReset()` ne touche que l'état de la porte. Le seul chemin qui nettoie `InkView` est `onControlKey(.escape)` → `cancelLiveStroke()` (`OverlayController.swift:57`). Sur `.tapDisabledByTimeout` / `.tapDisabledByUserInput`, ou sur entrée en passthrough, `livePoints` garde les N points du tracé abandonné et `live.path` reste posé. Les panneaux finissent par être retirés, donc la chose est invisible — jusqu'à la pression suivante de ⌥⌘ : `showPanels()` ordonne le panneau avec l'ancien `live.path`, et les `mouseMoved` capturés pendant la visée sont poussés avec `kind = .drag` (`OptionGate.swift:169`). `consume` trouve `livePoints` non vide, franchit le `guard` l. 162 et **allonge le trait abandonné jusqu'au curseur, sans qu'aucun bouton ne soit enfoncé**.

Symptôme : le tap dépasse son budget une fois pendant un tracé — le scénario que T0.8 demande de provoquer. Le trait se fige. À la pression suivante de ⌥⌘, le trait fantôme réapparaît et suit le curseur en l'air ; le `mouseDown` suivant le fait disparaître d'un coup.

```swift
// OptionGate
/// Notifie que le verrou a ete remis a plat : le rendu doit abandonner le trait en cours.
/// Transition rare (desarmement du tap, veille, verrouillage), jamais par point : le § 6.4
/// n'interdit un franchissement de frontiere que dans le chemin par point.
var onResetRequested: (@Sendable () -> Void)?

func requestReset() {
    pendingReset.store(true, ordering: .releasing)
    strokeFlag.store(false, ordering: .releasing)
    armedFlag.store(false, ordering: .releasing)
    onResetRequested?()
}
```

```swift
// OverlayController.setUp(), a cote du cablage de onStateChanged
OptionGate.shared.onResetRequested = {
    DispatchQueue.main.async { OverlayController.shared.forEachView { $0.cancelLiveStroke() } }
}
```

Cela couvre `EventTap.swift:162` et les trois entrées en passthrough de `main.swift` (67, 78, 87) sans les modifier. La course avec le drainage est bénigne dans les deux ordres : si le drain précède l'annulation, les points restants sont ajoutés puis effacés ; s'il la suit, les `.drag` résiduels retombent sur le `guard !livePoints.isEmpty`, désormais cohérent avec l'état de la porte.

Ce constat ne fait pas échouer C5 (le `mouseDown` suivant vide `livePoints` avant d'ajouter son point) : à corriger avant T0.8 parce qu'il pollue la manipulation d'acceptation, pas parce qu'il bloque le GO.

### 11. L'histogramme de latence n'enregistre qu'un échantillon par frame, et c'est le meilleur point du lot — C7, majeur

**`Overlay/InkView.swift:127`** (et 138-142).

Le display link accumule `latestEnqueued = max(latestEnqueued, event.enqueuedTicks)` sur tous les points de la frame, puis appelle `record()` une fois avec ce max. La latence étant `now − enqueuedTicks`, prendre le **max des instants d'entrée** revient à prendre le **minimum des latences du lot** : le point le plus ancien du drainage — celui qui a attendu tout l'intervalle du display link, donc le pire, donc celui qui intéresse un p95 — est systématiquement jeté.

Trois biais qui vont tous dans le même sens, flatter le p95 :
- un seul échantillon par frame : avec 8 points de souris par frame à 60 Hz, 500 points tracés ne produisent que ~62 échantillons, alors que le critère de fin de T0.7 est « un p95 chiffré après 500 points tracés » ;
- le max au lieu de chaque point ;
- l'origine est `enqueuedTicks` (entrée dans le callback du tap) et non `event.hostTicks` (`CGEvent.timestamp`), alors que T0.7 et l'en-tête de `LatencyHistogram` disent « de `CGEvent.timestamp` au commit » — le segment matériel → livraison au tap, précisément celui qu'un tap inséré en tête peut allonger, est exclu.

À quoi s'ajoute, dès qu'il y a deux écrans, un enregistrement **par panneau** ayant reçu des points (voir point 2).

Symptôme : le rapport C7 affiche un p95 de 2 à 4 ms et « objectif < 16 ms : atteint » sur un tracé dont la traîne visible derrière le curseur dépasse nettement une frame. Le compteur « échantillons » plafonne au nombre de frames.

1. Un échantillon par événement drainé, sans allocation par frame : `private var stamps: [UInt64] = []` réservé une fois dans `init` (`stamps.reserveCapacity(8192)`, capacité du ring), vidé par `removeAll(keepingCapacity: true)` en tête du pump, alimenté dans la closure de `drain`, parcouru **après** `CATransaction.commit()`.
2. Origine de la mesure : viser `CGEvent.timestamp` comme l'exige T0.7, mais retenir `event.hostTicks` seulement s'il tombe dans la fenêtre de validité de `SessionClock.stamp` (origine `.hardware`) **et** s'il précède l'instant du commit ; sinon se replier sur `enqueuedTicks`. Sans ce garde, `SessionClock.millis(from:to:)` renvoie 0 pour tout horodatage synthétique daté du futur et injecte des échantillons à 0 ms. Compter ces replis (comme `SessionClock.fallbackCount`) et les exposer dans le JSON : un p95 dont on ignore la proportion d'échantillons repliés n'est pas interprétable.
3. `StatusItemController.swift:105` : remplacer `%llu pts` par `%llu ech.` — `s.count` compte des échantillons, jamais des points tracés. Vérifier de même que `newPoints` (l. 118, 126) compte des événements drainés et non des points ajoutés au tracé : le filtre des 0,75 px (l. 165) et le `guard !livePoints.isEmpty` (l. 162) rejettent des événements qui incrémentent quand même le compteur.
4. Ne pas s'alarmer si le p95 corrigé remonte vers 16 ms : c'est la quantification intrinsèque d'un rendu à 60 Hz, pas une régression. En consigner l'explication dans RESULTATS.md pour que le verdict C7 du lot 0 reste comparable à celui du lot 2.

### 12. La queue vivante n'est jamais bornée : le chemin `CAShapeLayer` est reconstruit intégralement à chaque frame — C3b, à trancher par la mesure

**`Overlay/InkView.swift:133`** et `:175`.

Le § 6.4 impose trois choses pour la couche vivante : décimation RDP, tête du trait figée périodiquement, et queue de ~200 points. Seule la première est implémentée, et seulement à la fin du trait (`commitStroke`, l. 185). Pendant le trait, `livePoints` croît sans borne — le filtre à 0,75 pt (l. 165) réduit la pente, il ne plafonne rien — et `pathFromLivePoints()` alloue un `CGMutablePath` neuf et rejoue `addLines(between:)` sur la totalité des points à chaque cycle du display link. Le coût client est négligeable (97 µs à 20 000 points, mesuré) ; le coût qui compte est celui du **render server**, qui re-tessellise et re-trace N segments à joints ronds par frame, dans le processus partagé avec l'application testée. Le § 4.4 état 3 imposant un trait continu de 30 s, N atteint plusieurs milliers à quelques dizaines de milliers de points.

Symptôme attendu : la dégradation mesurée n'est pas un plateau mais une rampe — les 5 dernières secondes du relevé sont pires que les 5 premières, et le chiffre dépend de la durée du relevé.

**Étape préalable obligatoire : instrumenter, pas corriger à l'aveugle.** Journaliser `livePoints.count` en fin de trait pendant l'état 3, et relever la dégradation sur les 5 premières puis les 5 dernières secondes du même relevé. Si les deux tranches sont équivalentes, le défaut est cosmétique et il ne faut pas y toucher.

Si la mesure confirme la rampe : figer des tranches directement dans `committedPath` **n'est pas la bonne correction**, parce que `committed.shouldRasterize = true` (l. 80) invaliderait et re-rasteriserait la couche entière à chaque tranche, plusieurs fois par seconde — un coût plein écran potentiellement pire que celui qu'on supprime. Deux options tenables : désactiver `shouldRasterize` tant qu'un trait est vivant et le réactiver dans `commitStroke` ; ou figer les tranches dans une **troisième couche non rasterisée**, fusionnée dans `committed` seulement à la fin du trait — cette seconde option laissant `cancelLiveStroke()` et `undoLastStroke()` intacts, puisque les tranches figées ne rejoignent jamais `strokes` avant la fin du trait.

Deux griefs à ne **pas** poursuivre : la dérive de latence associée vaut 22 µs entre 500 et 5 000 points, soit 0,045 intervalle d'un histogramme à 0,5 ms contre un seuil de 33 ms — invisible par construction, C7 n'est pas concerné ; et `reserveCapacity(4096)` (l. 55) est sans objet, l'`append` est sur le thread principal, hors du callback du tap, amorti O(1), et la capacité survit à `removeAll(keepingCapacity: true)`.

## Corrections mineures

| # | Fichier · ligne | Ce qui cloche | Correction |
|---|---|---|---|
| a | `Tools/make-cert.sh:41-48` | Le p12 est fabriqué à mot de passe vide (`-passout pass:`) et `security import … -P ""` échoue systématiquement sur macOS 26.1 : `SecKeychainItemImport: MAC verification failed during PKCS12 import`. Sous `set -euo pipefail`, le script meurt là ; aucun certificat n'existe dans le trousseau, et `build-app.sh:35` renvoie « Lance d'abord ./Tools/make-cert.sh ». Le rituel de signature stable du § 4.2 n'a jamais pu s'exécuter. **Vérifié empiriquement, avec OpenSSL 3.6.3 comme avec LibreSSL 3.3.6.** | Générer le p12 avec un mot de passe non vide (`-passout pass:regarde-dev`) et l'importer avec le même `-P`. Testé : « 1 identity imported. » rc=0, certificat retrouvé. Ni `-legacy`, ni `-macalg sha1`, ni `-k` ne sont en cause. |
| b | `Bench/SnapshotBench.swift:120` | `captureImage()` rafraîchit `cachedContent` dès qu'il a plus de 30 s, donc quasiment à chaque capture — l'inverse de ce que promet sa doc (l. 32-37 : « jamais au clic »). L'énumération `SCShareableContent` (dizaines à centaines de ms) est comptée entre `requestedAtTicks` et `capturedAtTicks` : le nombre publié comme « latence propre de `captureImage` » mesure en réalité « `SCShareableContent` + `captureImage` », par intermittence. Médiane 34 ms / pire 486 ms sans cause visible, non reproductible. Fiabilité de l'instrument T0.9, aucun critère bloquant. | Dans l'ordre : (1) ajouter `Task.detached { await SnapshotBench.shared.warmUp() }` au bloc `didChangeScreenParametersNotification` (`OverlayController.swift:40-43`) **avant** de retirer le TTL, sinon on capture le mauvais écran via le repli `?? content.displays.first` ; (2) remplacer l. 118-123 par `guard let content = cachedContent else { throw BenchError.noShareableContent }`, et faire remettre `cachedContent = nil` par `warmUp()` en cas d'échec ; (3) sortir l'encodage PNG de l'isolation acteur (`try write(image, to: url)`, l. 103) dans un `Task.detached` après le stamp `done` — sans quoi deux traits espacés de 200 ms continueront de produire une latence fantaisiste pour le second, l'acteur sérialisant l'attente dans la mesure. |
| c | `Input/OptionGate.swift:219-221` | Le commentaire de `cancelStroke` décrit un comportement que le code ne réalise pas. | Le rendre vrai en même temps que le point 1. |
| d | `Metrics/LatencyHistogram.swift:114-116`, `Permissions/Preflight.swift:138,145-148` | Les boîtes ASCII sont désalignées — plus largement que le seul `%-28@` : les lignes en `%6.2f` et `%llu` font 62 à 64 caractères contre une bordure de 68. Aucun critère, aucune condition de fin de tâche. | Compter les colonnes face à la bordure, ou renoncer aux cadres. Un `pad()` sur les seuls `%@` ne suffit pas (mesuré : toutes les lignes tombent alors à 59 dans une boîte de 68). |

## Ce qui a été vérifié et tient

**La porte à verrou elle-même, hors des trois trous ci-dessus.** `decide` est bien la transcription littérale du § 6.2 demandée par T0.6 : `leftMouseDown` est le seul point de décision d'entrée, `capture = armed && !mouseDownInApp` y est calculé une fois et tient jusqu'au `mouseUp`, et `capture = strokeActive` au `mouseUp` **quel que soit l'état du modificateur** — c'est C6, et il passe pour le déclencheur nominal (relâchement de ⌥⌘). Les trois défauts rapportés portent tous sur des déclencheurs latéraux (Échap, désarmement du tap, passthrough).

**Le masque du tap volontairement étroit.** Bouton droit, boutons auxiliaires et molette n'y sont pas, et c'est cohérent : le `switch` normatif du § 6.2 ne traite que `leftMouseDown/Up/Dragged` et `mouseMoved`, avec `default: break`. Les ajouter serait inerte (`EventTap.handle` les renverrait via son `default: return Unmanaged.passUnretained(event)`) puis nuisible : une règle `if armed || strokeActive { return .swallow }` n'est pas un verrou et produirait un `rightMouseUp` orphelin dès que ⌥⌘ est relâché — exactement ce que C6 interdit. Et `targetRect` valant `.infinite` au lot 0, avaler la molette sous ⌥⌘ la supprimerait sur toute la machine. Arbitrage à instruire au lot 2, quand `targetRect` désignera réellement la fenêtre cible.

**`mouseMoved` poussé avec `kind = .drag`.** Deux verrous en série empêchent qu'un `mouseMoved` allonge un trait : `capture = armed && !mouseDownInApp` côté porte (si le bouton a été enfoncé vers l'application, `mouseDownInApp` est vrai), et `guard !livePoints.isEmpty` côté vue. Le seul état où cela mordrait est celui du point 10, dont la cause est ailleurs. Ajouter un genre `.hover` aujourd'hui serait une anticipation du lot 2, pas une correction.

**`TargetRectBox` (`OptionGate.swift:52-66`).** Le piège d'exclusivité annoncé est impossible : avec `private var slots` dans une `private final class` mono-fichier, l'application est statique — `nm -u` ne montre aucun `swift_beginAccess` dans le binaire. Même en forçant l'application dynamique, le désassemblage montre un `swift_beginAccess` **sans** `swift_endAccess`, signature d'un accès instantané qui n'entre jamais dans l'ensemble des accès actifs ; et cet ensemble est thread-local, donc l'exclusivité dynamique n'est pas un détecteur de courses inter-threads. 16 millions d'accès croisés en `-O -wmo -enforce-exclusivity=checked` : zéro piège. La déchirure théorique du double tampon est dormante — `setTargetRect` n'a aucun appelant, `slots` reste `(.infinite, .infinite)` pour toute la durée du lot 0. Le remplacement proposé par un `[CGRect]` introduisait, lui, un use-after-free réel sur le thread du tap (`_ArrayBufferV20_consumeAndCreateNew` réalloue pendant que le tap tient l'ancien pointeur). **Ne pas y toucher.**

**`DispatchQueue.main.async` depuis le callback du tap (`OptionGate.swift:195`).** L'allocation existe et le § 6.2 écrit « zéro allocation » sans exception, mais le mécanisme de panne n'existe pas : ~32 octets vont en nano-zone, dont le chemin courant est un CAS sans verrou ; quand `_malloc_lock_s` est effectivement pris, c'est un `os_unfair_lock` avec donation de priorité vers un thread `.userInteractive`, section critique de quelques microsecondes — trois à quatre ordres de grandeur sous le seuil de `kCGEventTapDisabledByTimeout`. Et l'instrument qui trancherait existe déjà : le `defer` en tête de `handle()` chronomètre chaque passage, `pireCallbackMs` est affiché dans le menu et exporté dans le `RunReport`. La correction proposée (`CFRunLoopSourceSignal` + `CFRunLoopWakeUp(CFRunLoopGetMain())`) était pire : verrou de la source, `__CFRunLoopLock` de la run loop principale — réellement détenu par le thread principal — et un `mach_msg_send`.

**La conversion de coordonnées (`OverlayController.swift:114-119` + `Coordinates.swift:31-57`).** Le mélange d'un `screen.frame` figé à la construction et d'une hauteur de retournement lue en direct **n'est pas** un défaut : c'est ce qui rend la conversion exacte. Les deux termes décrivent des choses différentes — `globalFlipHeight` l'espace des événements (déjà exprimé dans la nouvelle géométrie), `frame.minY` la position réelle du panneau (qui n'a pas bougé). Position globale = `minY + ((H_new − y_ev) − minY) = H_new − y_ev`, les `minY` s'annulent : erreur nulle sur tous les écrans. « Homogénéiser les dates » ferait passer le décalage de 0 à 135 pt sur l'écran principal et sur tout écran aligné en bas.

**`realign` qui ne transforme pas les chemins posés.** macOS n'applique aucune homothétie au contenu des fenêtres lors d'un changement de mode mis à l'échelle : les pixels physiques ne bougent pas, seule la conversion point↔pixel change. Il n'existe donc aucune transformation affine unique qui réancrerait les marques ; le « correctif » casserait les cas aujourd'hui justes (barre de menus, Dock, fenêtre de taille fixe près de l'origine). Le modèle d'ancrage des marques anciennes est le sujet du lot 2, pas un oubli du lot 0.

**`contentsScale` non fixé sur les trois calques créés à la main.** Le fait est exact — AppKit ne propage rien aux sous-couches (`window=2.0 rootLayer=2.0 committed=1.0 live=1.0 badges=1.0`, mesuré) — mais `contentsScale` gouverne `contents` et la sortie de `-drawInContext:`, pas la tessellation d'un path par le render server. Rendu comparatif à travers `CARenderer` vers une texture Metal 2x : trois `CAShapeLayer` identiques à `contentsScale` 0,5 / 1,0 / 2,0 donnent le même trait au pixel de périphérique près (7 px d'étalement, 3 niveaux), quand un calque témoin dessiné via `-drawInContext:` à 1,0 est visiblement mou (10 px, 9 niveaux). Le code touche la seule échelle qui gouverne réellement le cache : `rasterizationScale`. Deviendra pertinent au lot 2 quand `badges` portera des `CATextLayer`.

**`shouldRasterize` sur la couche `committed`.** L'arithmétique mémoire alarmiste est fausse d'un facteur 4 (`screen.frame.size` est en points, pas en pixels : ~31 Mo, pas 123), le cache n'existe que pendant que ⌥⌘ est tenu (les panneaux sont `orderOut` entre les gestes, ADR-0010), et `committed.path` ne change qu'au `mouseUp` — une poignée de commits contre ~1800 deltas de rAF pendant l'état 3. Les deux « parades » proposées étaient l'une non compilable (`CGPath.transformed(by:)` n'existe pas), l'autre régressive (`committed.frame = boundingBox` décale tous les traits posés, `bounds.origin` restant à zéro). Le grief connexe sur « plusieurs centaines de milliers de points cumulés » ignore le filtre à 0,75 px et la décimation RDP à epsilon 0,6.

**`rasterizationScale = window?.backingScaleFactor ?? 2.0` évalué avec `window == nil`.** Le symptôme est inversé : 2,0 sur un écran 1x est du suréchantillonnage, pas du sous-échantillonnage — le trait `committed` est au pire identique à `live`, jamais plus mou. Deux rattrapages existent, `viewDidChangeBackingProperties()` et `layoutLayers()` rappelé par `realign` à chaque `didChangeScreenParameters`, et ce dernier écrit déjà entre `CATransaction.begin/setDisableActions(true)/commit`. Le repli `NSScreen.main?.backingScaleFactor` proposé serait pire : cette application ne devient jamais key.

**Le préflight et le doctor.** `canActuallyCreateTap()` n'est pas une dérive : c'est la mise en œuvre littérale de « chaque ligne du doctor exécute l'opération réelle, pas son préflight » (§ 4.7) et d'ADR-0005. Son effet incrémental est nul, `EventTap.install()` faisant quelques millisecondes plus tard un `tapCreate` strictement plus exigeant (`.defaultTap`, masque incluant `keyDown` et `flagsChanged`). La passer en `.defaultTap` comme proposé créerait un tap consommateur armé en tête de chaîne HID que personne ne draine, invalidé sans avoir été désarmé — une fenêtre où la souris de l'utilisateur peut être retenue à chaque lancement. Le `allSatisfy` généralisé produirait, lui, un conseil actif faux (« retire puis remets l'entrée dans Surveillance de la saisie » pour un problème d'Accessibilité). Le bloc ⚠ des l. 153-162 nomme déjà la permission manquante, son chemin dans Réglages et sa raison : le critère de fin de T0.3 est tenu. Le tri-état « refusée / jamais demandée » appartient au lot 1, et le témoin `everRequested` proposé ne serait jamais écrit puisque le lot 0 n'émet aucun `request` — il ferait basculer toute permission **révoquée** en « jamais demandée », cassant exactement T0.3.

**`SnapshotBench.warmUp()` au lancement et au réveil.** C'est le § 11.3 lot 1 et la parade R1 mot pour mot (« prise de contact TCC hors chemin de session, jamais au raccourci »). L'alerte ne peut pas resurgir au réveil : le statut n'est plus indéterminé. Le garde `CGPreflightScreenCaptureAccess()` proposé tuerait le banc C11 sur une machine neuve — `warmUp` sortirait tôt depuis les quatre points d'appel, `cachedContent` resterait nil, l'autorisation ne serait plus jamais sollicitée.

**Le bucket de débordement de `LatencyHistogram`.** Il est d'indice maximal, donc l'ordre des rangs est préservé et la valeur rendue est un **minorant** du quantile réel : la saturation ne produit qu'une seule valeur, 199,75 ms, soit six fois le seuil — le verdict est FAIL, jamais un faux PASS. Le patch `bucketCount = 401` laissait la garde à `>= bucketCount` : un échantillon de [200 ; 200,5) aurait atterri dans le bucket de débordement **sans** incrémenter `overflow`, et `return s.maxMs` aurait affiché « p95 4310 ms » pour un dépassement de 200,2 ms.

**`SnapshotBench` réentrant.** L'index dupliqué n'écrase aucune image : le nom est `c11-%03d-t%.3f.png`, une collision exigerait deux `mouseDown` dont le `sessionTime` coïncide à la milliseconde. Le § 4.5 apparie par le SessionTime gravé, pas par l'index, et `shotsJSON()` émet le nom de fichier construit dans l'appel courant. La latence mesurée (`requestedAtTicks` → `capturedAtTicks`, deux locales) est indifférente au réordonnancement. L'« emplacement pré-inséré » proposé aurait fait apparaître chaque capture en vol comme une capture échouée avec `"latenceMs": 0.0` dans le livrable.

**Le repli `?? content.displays.first` du banc.** En recopie vidéo, les deux `SCDisplay` sont présents (§ 3.3) : le `first(where:)` trouve sa cible. `warmUp` est appelé au lancement, au réveil et à l'activation du banc, qui ouvre le protocole T0.9. Et le `throw` proposé transformerait un PNG rare et inutilisable en perte totale de la mesure.

**⌘Z et Échap diffusés à tous les panneaux.** `cancelLiveStroke()` sur une vue sans trait vivant est un no-op strict, et deux vues ne peuvent pas porter simultanément un trait vivant. Le reste du grief est un symptôme dérivé du point 2 — la sémantique d'annulation multi-écran est du lot 2 (S21). Le correctif proposé référençait un `onStrokeCommitted` inexistant, laissait `strokeOrder` désynchronisé après « Effacer tout » et après un débranchement d'écran, et son repli `first { $0.inkView.hasContent }` sélectionne une vue qui n'a que des traits déjà posés.

**Le rafraîchissement 1 Hz de la barre de menus.** Trois lectures de `tapIsEnabled` et deux `String(format:)` par seconde sont une redondance, pas un défaut mesurable : sur 28 s utiles à 60 fps, 28 frames perturbées ne déplacent pas la médiane et décalent le p95 de 28 rangs sur 1680. La mesure C3b se fait témoin en plein écran natif, barre de menus masquée. Et le correctif déplaçait le remplissage vers un `menuWillOpen` qui n'existe nulle part dans les sources — les deux éléments seraient restés bloqués sur « … », supprimant le témoin permanent du § 4.2. Le watchdog T0.8 impose de toute façon du trafic CGS périodique sur le thread principal.

**`emit()` sur stderr.** Le p95 s'affiche dans le menu (`latencyItem`, rafraîchi chaque seconde) et le JSON est écrit sur disque par `RunReport.json()` (l. 70-71) avant d'être rendu ; les captures C11 vont dans `~/Regarde-lot0/c11`. `Preflight.logReport()` double en `os_log`, canal documenté par `build-app.sh:82`. Reste une gêne réelle mais mineure : trois entrées de menu ne produisent aucun retour visible quand l'application est lancée par `open`.

**`build-app.sh:62` et `:67-71`.** Signer avec une identité réelle embarque les internal requirements ; `codesign -d -r-` imprime alors une ligne `designated =>` non commentée, sans avoir besoin de `-r` à la signature — vérifié sur un bundle reproduisant la commande du script (rc=0, `grep` matche) et sur `/bin/ls`, Ghostty, Docker. Le `#` observé venait d'un `.build/test-bundle` linker-signed jamais passé par le script. Ajouter un `-r=` explicite changerait le contenu mémorisé par TCC au premier build et ferait sauter Surveillance de la saisie — la panne même que le § 4.2 cherche à éviter. Quant à la boucle d'attente : aucun handler SIGTERM n'est installé, donc la terminaison est immédiate (mesuré : 0 itération sur 20, mort en 72 ms), et `open` sans `-n` réactive l'instance existante au lieu d'en créer une seconde (mesuré : même PID après remplacement du bundle sous ses pieds). Il ne peut pas y avoir deux taps concurrents.

**`set-key-partition-list -k ""` (`make-cert.sh:53`).** `-k` n'est utilisé que pour déverrouiller ; sur un trousseau déverrouillé il est ignoré (rc=0 même avec un mot de passe totalement faux, mesuré). Le trousseau de session d'un compte interactif est déverrouillé par définition. Le vrai blocage est en amont, ligne 41-48 (voir mineur **a**).

**Le témoin, hors calibrage.** `alignClock` enregistre `wallMs − pageNow`, c'est-à-dire `performance.timeOrigin`, constant pour la vie de la page : un second clic n'écrase aucune information. Le compteur de frames journalise `{frame, now}` à chaque frame et exporte 4000 entrées contiguës, dont la différence des `now` donne l'intervalle de rafraîchissement mesuré sur la machine du relevé — le biais d'une frame entre journalisation et présentation est dérivable du relevé lui-même, et l'horodatage rAF suivant n'est pas l'instant de présentation de la frame précédente.

## Angles morts de cette revue

**Le comportement du curseur quand `mouseMoved` est consommé.** Sous ⌥⌘ armé, la porte avale les `mouseMoved` (conformément au § 6.2). Une lecture de code ne peut pas dire si le curseur système continue de se déplacer, ni si l'état de survol de l'application testée se fige de façon gênante à l'œil pendant le geste. Si le curseur se figeait, cela invaliderait le § 6.2 lui-même et serait la découverte du GO/NO-GO n°1 — le seul moyen de le savoir est de garder le code tel quel et de le regarder.

**La fréquence réelle de `kCGEventTapDisabledByTimeout`.** Tout le raisonnement sur le budget du callback (allocations, verrous, coût du `String(format:)`) repose sur des ordres de grandeur, pas sur une mesure. `pireCallbackMs` et `reArmements` sont instrumentés : ce sont eux, et non la lecture du code, qui diront si le budget du § 6.2 tient sous une souris à 1000 Hz. À lire après chaque session, même quand rien n'a semblé anormal.

**Le coût GPU réel de la couche de composition.** Personne ne sait aujourd'hui, sur cette machine, ce que coûte un `NSPanel` transparent plein écran ordonné au-dessus d'une page WebGL chargée. C'est la question que C3b existe pour trancher, et elle ne se tranchera qu'avec un témoin calibré (points 4 et 5) — donc pas avant que ces deux corrections soient faites et vérifiées.

**Plein écran natif, Space, Stage Manager (C8, C9).** Le comportement d'un `.nonactivatingPanel` `.borderless` de niveau élevé face au plein écran natif de Safari et face à Stage Manager ne se déduit d'aucune ligne de code : il dépend du WindowServer et de la version du système. Le point 9 rend la manipulation possible, il ne prédit pas son résultat.

**La stabilité de l'autorisation TCC entre deux builds.** Le chemin fixe et l'identité stable sont en place dans les scripts, mais le rituel n'a jamais tourné jusqu'au bout sur cette machine (mineur **a**) : le certificat n'existe pas dans le trousseau. Tant que `make-cert.sh` n'aboutit pas, on ne sait pas si Surveillance de la saisie survit réellement à un rebuild — et c'est la première chose que le § 4.2 demande de savoir.

**Le multi-écran à cadences différentes.** Le point 2 est établi par lecture, mais l'ordre d'ordonnancement de deux `CADisplayLink` 120 Hz / 60 Hz sur la même run loop, et le comportement de la diffusion corrigée sur un trait à cheval sur la frontière, ne se vérifient qu'avec les deux écrans branchés. C'est le « fini quand » de T0.5, et il n'a pas d'équivalent sur portable seul.

**La latence perçue par rapport à la latence mesurée.** Même corrigé (point 11), l'histogramme mesure du callback du tap au commit `CATransaction` — pas jusqu'à la présentation à l'écran. L'écart entre le p95 chiffré et la traîne visible du trait derrière le curseur ne se lira qu'à l'œil, et c'est ce jugement-là qui compte pour le GO.