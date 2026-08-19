---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 1 et 8
---

# ADR-0002 — Regarde est distribuée hors App Sandbox, signée Developer ID et notarisée

## Contexte

Trois briques du produit sortent du bac à sable par nature. Le `CGEventTap` du § 4.1 est un tap
`.defaultTap` qui **consomme** les événements souris quand ⌥⌘ est maintenu : il exige
l'Accessibilité en plus d'Input Monitoring (§ 4.2). La détection du projet interroge
`proc_pidinfo` sur les processus voisins pour retrouver le `cwd` de la session d'agent, et lit
`~/.claude/sessions/`. Le rapport s'écrit dans un répertoire de projet quelconque, choisi à
l'exécution, parfois sous `~/Documents`. À quoi s'ajoute le sidecar `regarde-mcp`, exécutable
lancé non pas par l'application mais par l'agent, dans son propre contexte.

Le mode de distribution se tranche au lot 1, pas au lot 8 : les octrois TCC sont attachés à
l'identité de signature, et R9 liste la re-signature parmi les causes d'un tap désactivé
silencieusement. Une identité changeante fait redemander les quatre permissions à chaque
compilation.

## Décision

Regarde est distribuée hors App Sandbox, avec Hardened Runtime, signée par une identité
Developer ID stable adoptée dès le lot 1, notarisée et agrafée, diffusée en DMG. Le sidecar
`regarde-mcp` suit exactement le même traitement. Aucune publication au Mac App Store n'est
envisagée, ni maintenant ni plus tard.

## Options envisagées

### Option A — Hors sandbox, Developer ID notarisé, DMG (retenue)
- **Pour** : les quatre autorisations TCC deviennent demandables ; `proc_pidinfo`, l'API
  Accessibilité et l'écriture dans un chemin arbitraire fonctionnent sans détour ; le sidecar
  peut être lancé par n'importe quel agent depuis n'importe où ; aucune revue humaine entre une
  correction et sa mise à disposition.
- **Contre** : toute la chaîne de distribution est à la charge du projet, et la notarisation
  s'ajoute à chaque livraison.

### Option B — App Sandbox et Mac App Store
- **Pour** : installation en un clic, mises à jour prises en charge, confiance immédiate.
- **Contre** : trois incompatibilités dures, pas trois frictions. Une application sandboxée ne
  peut pas lire l'arbre d'accessibilité d'un autre processus, ce qui supprime à la fois le tap
  consommateur et l'injection dans l'agent
  ([ADR-0018](0018-presse-papiers-et-injection-best-effort.md)). `proc_pidinfo` sur les
  processus voisins est hors du conteneur, ce qui ramène la détection de projet à git et au titre
  de fenêtre ([ADR-0017](0017-detection-projet-trois-etats.md)). L'écriture dans un projet
  quelconque imposerait un signet de sécurité par projet, obtenu par un panneau d'ouverture —
  incompatible avec un mode éclair qui promet 8 secondes. Le sidecar, lancé par un processus
  tiers, ne peut pas vivre dans le conteneur. Et la revue App Store n'accepte pas un tap qui
  consomme des événements.

### Option C — App Sandbox, distribution directe hors Store
- **Pour** : posture de sécurité affichable sans dépendre de la revue Apple.
- **Contre** : les incompatibilités de l'option B sont celles du sandbox lui-même, pas de la
  revue. On paierait donc l'intégralité du coût pour zéro bénéfice de distribution. Perte sèche.

### Option D — Signature ad hoc, sans notarisation
- **Pour** : rien à payer, rien à soumettre ; c'est ce que fait le lot 0 pour le prototype.
- **Contre** : Gatekeeper bloque un DMG téléchargé, y compris sur la deuxième machine de
  l'auteur, ce qui rend le critère de réussite du lot 8 inatteignable. Surtout, une identité ad
  hoc n'est pas stable : les octrois TCC ne survivent pas d'une compilation à l'autre. Le coût
  réel n'est pas la notarisation, c'est de reconfigurer quatre permissions à chaque itération.

## Justification

L'option B n'est pas écartée pour son coût mais pour son résultat : une version sandboxée
n'aurait ni tap consommateur, ni Accessibilité, ni détection fiable du projet. Ce serait un
autre produit portant le même nom, pas une variante contrainte. L'option C montre que le sandbox
et le Store sont deux questions distinctes, et que le sandbox seul n'apporte ici aucun gain.

L'option D fixe la vraie raison de choisir Developer ID : la stabilité de l'identité de signature
est une propriété de développement avant d'être une propriété de distribution. Le prototype du
lot 0 peut vivre en ad hoc parce qu'il ne teste qu'un geste ; le lot 1 ne le peut plus.

## Conséquences

- **Positives** : les quatre permissions du doctor sont demandables et leurs octrois survivent
  aux montées de version ; le sidecar reste utilisable application fermée
  ([ADR-0015](0015-sidecar-mcp-stdio-disque-source-de-verite.md)) ; aucun délai de revue entre
  une correction et son installation.
- **Négatives** — le prix à payer, assumé : la notarisation devient une étape obligatoire de
  chaque livraison, avec le multiplicateur ×2,0 déjà appliqué à la ligne « signature et TCC » du
  calibrage, et 3 j budgétés au lot 8 ; le sidecar est un second binaire à durcir, signer et
  notariser, avec sa propre identité TCC — d'où le test explicite d'un projet sous `~/Documents`
  au lot 6, un sidecar refusé par Gatekeeper se manifestant côté agent par un canal MCP muet ; la
  ré-autorisation mensuelle de la capture d'écran est certaine et non contournable, l'entitlement
  `com.apple.developer.persistent-content-capture` n'étant pas accordé hors Store, ce qui impose
  la prise de contact TCC hors chemin de session et une ligne de documentation au lot 8 ;
  l'adhésion payante au Programme Développeur devient une dépendance permanente pour publier, et
  la mise à jour reste un retéléchargement manuel du DMG.
- **Ce que ça ferme** : le Mac App Store définitivement, donc la découverte et les achats
  intégrés ; et l'espoir d'une installation sans autorisation manuelle — quatre demandes TCC dont
  deux exigent une relance, ce que le risque R1 classe en probabilité certaine et impact élevé
  sur le premier contact.

## Signal de révision

Le premier signal est un résultat du lot 0 : si C1 à C6 échouent et que le produit se replie sur
un chemin d'entrée sans tap (§ 4.2), l'incompatibilité la plus visible disparaît — restent
`proc_pidinfo` et l'écriture hors conteneur, donc le sandbox reste fermé, mais l'arbitrage mérite
d'être refait plutôt que hérité. Le second est observable à chaque livraison : si les quatre
permissions sont redemandées après une simple montée de version signée avec la même identité
Developer ID, la prémisse « une identité stable protège les octrois » est fausse et l'intérêt de
la signature stable en développement s'effondre.

## Références

- Spécification § 4.1 (ligne Sandbox), § 4.2, § 11.3 lots 1, 6 et 8, § 12 R1 et R9, § 14.
- [ADR-0001](0001-application-macos-native-swift.md), [ADR-0005](0005-cgeventtap-arbitre-unique.md),
  [ADR-0015](0015-sidecar-mcp-stdio-disque-source-de-verite.md),
  [ADR-0017](0017-detection-projet-trois-etats.md), [ADR-0020](0020-confidentialite-capture-continue.md).
