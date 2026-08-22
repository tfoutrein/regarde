# Lot 3 — passage du livrable

> **État : le code est complet, le livrable n'est pas passé.** Ce document existe
> pour dire précisément ce qui manque, et pourquoi ce qui manque ne pouvait pas
> être produit autrement. Il se remplit à la première campagne sur machine.

**Critère du plan** (§ 7.4, S42) : « Sur une page animée, 8 marques pendant
l'animation : les 8 images montrent l'état exact désigné, vérifié contre un
enregistrement témoin. Traitement final < 3 s. RSS < 200 MiB, CPU < 3 %, disque
< 500 MiB pour 10 min. Débranchement d'écran en pleine session : les marques de cet
écran ont leur image. »

---

## Ce qui est fait, et ce qui l'établit

| Session | Livré | Ce qui l'établit |
|---|---|---|
| S29 | Témoin lisible par machine, dépôt sans `execute javascript` | Décodage du GPU et d'un PNG, deux décodeurs indépendants d'accord · 18 refus du serveur vérifiés |
| S30 | Horloge de session recalée à l'`arming`, `originContinuous`, `Mark.t` | 18 vérifications d'autotest |
| S31 | Décodeur de réglette, banc C11, seuil écrit d'avance | 40 vérifications, dont 20 bits retournés → 20 refus |
| S32 | Modèle temporel, `assetTime`, plan de burst | 22 vérifications · contre-épreuve : retirer la soustraction fait tomber 9 |
| S33 | Rotation portrait et recopie vidéo refusées nommément | 9 vérifications · contre-épreuve sur la décision de recopie |
| S34 | Un `SCStream` par écran, filtre reconstruit à chaud | journal — `lot3-flux.sh` |
| S35 | HEVC par segment, GOP 1 s, manifeste à côté du `.mov` | manifeste relisible après coup |
| S36 | Débranchement à chaud, finalisation immédiate | `lot3-debranchement.sh` |
| S37 | Frontière B2, anneau sous double garde | `lot3-frontiere-b2.sh` — contrôle mécanique |
| S38 | Frame boîtée décrite là où elle sert | 8 vérifications |
| S39 | Extraction, tolérances asymétriques, écart mesuré | `lot3-extraction.sh` — contrôle mécanique |
| S40 | Plan de burst sous double critère | modèle prouvé en S32, branché en S40 |

**314 vérifications d'autotest, 0 échouée, 0 avertissement de compilation.**

Trois invariants sont vérifiés **mécaniquement** plutôt que rappelés : le tap ne
touche aucun tampon, l'anneau garde sa file, et il n'existe qu'une seule porte vers
l'asset. Chacun a sa contre-épreuve — on le casse, le contrôle rougit en nommant le
fichier et la ligne.

---

## Ce qui manque, et pourquoi

Tout ce qui reste demande **la machine** : deux écrans, l'autorisation
d'enregistrement, Chrome en plein écran natif, l'Accessibilité, et du temps réel qui
passe. Aucune de ces choses ne se simule, et les simuler produirait un passage qui
dit « vert » sans avoir rien mesuré — exactement ce que ce projet refuse.

| Point du critère | Verdict | Ce qu'il faut faire |
|---|---|---|
| 8 marques sur page animée, état exact désigné | **non mesuré** | `lot3-c11.sh`, témoin en mode compteur, plein écran |
| Traitement final < 3 s | **non mesuré** | bloc `EXTRACTION` du journal, ligne « durée » |
| RSS < 200 MiB | **non mesuré** | `lot3-budgets.sh` — **deux écrans obligatoires**, l'anneau est par flux |
| CPU < 3 % | **non mesuré** | `lot3-budgets.sh` |
| disque < 500 MiB / 10 min | **non mesuré** | `lot3-budgets.sh` |
| Débranchement : les marques ont leur image | **non mesuré** | `lot3-debranchement.sh` |
| C3b en plein écran (dette du lot 0) | **non mesuré** | `lot3-temoin.sh` — six relevés, deux ordres |

---

## Ce qui reste ouvert par ailleurs

- **La cadence du relevé du 21 août.** Un relevé est sorti à 70,07 fps — 58 % du
  natif sur 120 Hz, sous le plancher de 70 %. La forme de la distribution (médiane
  10,5 ms pour une moyenne de 14,3) ressemble à de la dérive thermique, et une
  hypothèse se tient : le calibrage converge sur une fenêtre d'une seconde alors que
  le relevé dure soixante fois plus. Consigné dans `prototypes/lot0/RESULTATS.md`,
  à trancher avant de conclure sur C3b.
- **S16** — Developer ID et notarisation, bloqué sur un compte Apple Developer.
- **S44 et S45** — pré-roll et marques rétroactives, le bloc de marge du § 6.3. Le
  critère de fin du lot ne les mentionne pas : ils sont livrés ensemble ou décalés
  ensemble, après le GO/NO-GO n°2.
- **La recette manuelle (S43)** n'est pas écrite. Elle vient après ce passage, et le
  lot 2 a établi qu'elle trouve ce qu'aucun scénario automatisé ne voit — onze
  défauts, dont deux nés de correctifs de la veille.

---

## La position honnête

Le lot 3 est **complet en code et instrumenté**, pas **validé**. La différence n'est
pas rhétorique : le lot 2 était livré le 20 août et ne s'est révélé utilisable que le
21, après soixante-quatre tests manuels qui ont trouvé onze défauts. Rien n'autorise
à croire que le lot 3 en contient moins.

`v0.3.0` ne se pose pas sur ce commit. Il se posera sur celui qui remplira le tableau
ci-dessus.
