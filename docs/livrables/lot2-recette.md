# Recette du lot 2 — tests manuels

Ce que vous validez ici : **tracer sur une application qui tourne, sans la perturber, et
obtenir des images gravées**. Ni voix, ni rapport texte, ni MCP — ce sont les lots 3 à 5.

Comptez **25 à 35 minutes**. Les sections 1 et 2 sont bloquantes : si elles échouent, le reste
n'a pas de sens.

---

## Avant de commencer

```bash
cd ~/DEV/PERSO/AI-DEV/TOOLS/regarde/app
./Tools/build-app.sh --run          # compile, signe, installe, lance
tail -n +1 -f ~/Regarde/journal.txt  # second terminal — TOUT le fichier, puis la suite
```

Prenez une **application de test qui bouge** : une page web avec une animation, une vidéo, un
terminal qui défile. Une fenêtre figée ne prouve rien sur la section 2.

Votre clavier est détecté comme **French**. Trois familles de touches, trois règles :

| Raccourci | Touche à presser | Pourquoi |
|---|---|---|
| `⌃⌥S` `⌃⌥F` `⌃⌥M` `⌃⌥L` | les touches marquées S, F, M, L | résolues par caractère |
| `⌥⌘F` `⌥⌘C` `⌥⌘P` `⌥⌘S` | les touches marquées F, C, P, S | idem |
| `⌥⌘Z` | la touche marquée **Z** | idem — c'est le W du QWERTY |
| `⌥⌘ + 1..6` | les touches **& é " ' ( -** de la rangée du haut | code physique, **sans ⇧** |

Cette dernière ligne est le point le plus discutable du lot : sur AZERTY, les chiffres sont en
position secondaire, mais `⇧` est réservé à autre chose. **Dites-moi si c'est pénible à l'usage** —
c'est le genre de décision qu'on ne peut pas trancher sans l'avoir dans les doigts.

---

## 1. Le socle — bloquant

- [ ] **1.1** L'icône apparaît dans la barre de menus.
      *Si elle manque : elle peut être derrière l'encoche. Débranchez un écran externe pour voir.*
- [ ] **1.2** Menu → **Diagnostic…** : toutes les lignes requises sont vertes, verdict `✓`.
- [ ] **1.3** `grep "tap démarré" ~/Regarde/journal.txt` renvoie une ligne.
      *Écrite au lancement : un `tail -f` ordinaire ne la montre pas, d'où le `-n +1` ci-dessus.*
- [ ] **1.4** `grep "⌃⌥" ~/Regarde/journal.txt` liste les quatre raccourcis, chacun avec un `✓` et
      un code de touche.
- [ ] **1.5** Le journal affiche `cible suivie : <votre application>` et le nom change quand vous
      passez d'une application à l'autre.

## 2. La promesse — ne rien casser. Bloquant.

C'est **la** section qui compte. Un échec ici invalide le produit, pas seulement le lot.

- [ ] **2.1** Sans rien presser, cliquez et glissez normalement dans l'application testée :
      sélection de texte, déplacement, boutons. **Tout se comporte comme d'habitude.**
- [ ] **2.2** L'animation de l'application testée ne marque **aucun à-coup** quand vous tenez `⌥⌘`
      puis quand vous tracez.
- [ ] **2.3** Le curseur de saisie continue de clignoter dans un champ de texte pendant que vous
      tracez. **Le focus n'est jamais volé.**
- [ ] **2.4** Clic droit **hors tracé** : le menu contextuel de l'application s'ouvre normalement.
- [ ] **2.5** Tapez du texte, puis `⌘Z` **seul** : l'application testée annule sa propre frappe.
      *Régression corrigée aujourd'hui — c'est le test le plus important de la section.*
- [ ] **2.6** `⌘S`, `⌘C`, `⌘P` seuls : l'application testée les reçoit normalement.
- [ ] **2.7** Relâchez `⌥⌘` en plein tracé, bouton toujours enfoncé : le trait s'arrête, et
      l'application testée **ne reçoit ni glissement ni relâchement**.
- [ ] **2.8** Après un tracé, le premier clic ordinaire suivant fonctionne du premier coup.

## 3. Le mode éclair — tracer sans rien ouvrir

- [ ] **3.1** Sans avoir pressé `⌃⌥S` : tenez `⌥⌘`. Le calque apparaît (rien de visible, mais le
      tracé va fonctionner).
- [ ] **3.2** `⌥⌘` + glisser : un trait vermillon suit le curseur **sans retard perceptible**.
- [ ] **3.3** Le trait démarre **exactement sous le curseur**, pas à quelques pixels.
- [ ] **3.4** Relâchez `⌥⌘`. Le calque disparaît immédiatement.
- [ ] **3.5** ~1 s plus tard, le HUD annonce `1 marque publiée` et un nom de dossier.
- [ ] **3.6** `ls -t ~/Regarde/sessions | head -1` → un dossier avec `frames/marque-01.png`.
- [ ] **3.7** **Rafale** : tracez trois marques en relâchant `⌥⌘` entre chacune, mais rapidement.
      Les trois atterrissent dans **un seul** dossier, numérotées 1, 2, 3.

## 4. Les quatre outils

`⌥⌘` tenu, appuyez sur la lettre, le HUD annonce l'outil.

- [ ] **4.1** `⌥⌘F` → « Outil : flèche ». Tracez : une flèche avec une pointe **du bon côté**.
- [ ] **4.2** `⌥⌘C` → « Outil : cadre ». Tracez : un rectangle vide.
- [ ] **4.3** `⌥⌘P` → « Outil : point ». Cliquez sans bouger : un disque plein apparaît.
- [ ] **4.4** `⌥⌘S` → « Outil : surlignage ». Tracez : un aplat translucide **qui laisse lire ce
      qu'il recouvre**, bordé d'un liseré net.
- [ ] **4.5** L'outil choisi **reste actif** jusqu'au prochain changement, y compris après avoir
      relâché `⌥⌘`.

## 5. Numérotation et annulation

- [ ] **5.1** Le numéro apparaît **pendant** le tracé, avant même de relâcher le bouton.
- [ ] **5.2** Le numéro ne bouge plus une fois la marque posée.
- [ ] **5.3** **`Échap`** en plein tracé : le trait disparaît, rien n'est posé.
- [ ] **5.4** **Clic droit** en plein tracé : même effet, et **aucun menu contextuel** ne s'ouvre.
- [ ] **5.5** Après une annulation, la marque suivante **reprend le numéro annulé**.
- [ ] **5.6** **`⌥⌘Z`** (touche marquée Z) : la dernière marque posée disparaît.
- [ ] **5.7** Après un `⌥⌘Z`, la marque suivante **ne reprend pas** le numéro supprimé — elle
      laisse un trou. *C'est voulu : vous avez pu prononcer ce numéro à voix haute.*

## 6. Les intentions

- [ ] **6.1** Posez une marque, puis, `⌥⌘` toujours tenu, pressez la touche **&** (le « 1 ») :
      le badge devient `1 · mal aligné`.
- [ ] **6.2** Les six répondent : **&** mal aligné, **é** erreur, **"** manque un état,
      **'** lent, **(** texte à corriger, **-** ne marche pas.
- [ ] **6.3** La touche **è** (le « 7 ») : le HUD dit `7 — hors palette`, et **rien n'est envoyé
      à l'application testée**.
- [ ] **6.4** Une intention frappée **sans aucune marque posée** : le HUD dit `Aucune marque à
      qualifier`.
- [ ] **6.5** **Le cas qui comptait** : tracez une flèche **vers le bord de la fenêtre**, de sorte
      que le curseur finisse dehors. Frappez l'intention. **Elle s'applique quand même.**
- [ ] **6.6** Passez dans un autre programme, tenez `⌥⌘` et pressez **&** : ce programme reçoit le
      raccourci, Regarde ne le prend pas.

## 7. La fenêtre cible

- [ ] **7.1** `⌥⌘` + glisser **hors** de la fenêtre au premier plan : **aucune marque**, et le
      clic part à ce qu'il y a dessous. *C'est le `⌥⌘`-clic dans l'IDE qui ne doit rien casser.*
- [ ] **7.2** `⌥⌘⇧` + glisser hors de la fenêtre : **la marque est posée.** C'est l'échappatoire.
- [ ] **7.3** Déplacez la fenêtre testée. `⌥⌘` arme à son nouvel emplacement en moins d'une
      seconde.
- [ ] **7.4** Changez d'application. Le journal annonce la nouvelle cible, et `⌥⌘` arme sur elle.

## 8. La session explicite

- [ ] **8.1** `⌃⌥S` : le journal affiche `cible figée : <application>`, le HUD annonce l'ouverture.
- [ ] **8.2** Posez trois marques en relâchant `⌥⌘` entre chacune : **rien n'est publié**, contrairement
      au mode éclair.
- [ ] **8.3** Passez dans un autre programme puis revenez : la cible **n'a pas changé**.
- [ ] **8.4** `⌃⌥F` : le HUD annonce `Session terminée — 3 marques`, le journal liste les marques
      et le nombre d'images écrites.
- [ ] **8.5** Le dossier contient exactement trois PNG.
- [ ] **8.6** Après la fermeture, le mode éclair reprend : `⌥⌘` + tracer publie de nouveau tout seul.
- [ ] **8.7** Une marque supprimée par `⌥⌘Z` avant `⌃⌥F` **ne produit aucun fichier**.

## 9. Les écrans

- [ ] **9.1** Tracez sur l'écran externe : le trait apparaît **au bon endroit**, pas décalé du double.
- [ ] **9.2** Un trait commencé sur un écran et poursuivi sur l'autre reste **un seul trait**.
- [ ] **9.3** Débranchez l'écran externe pendant que Regarde tourne : l'icône reste accessible et
      rien ne casse.
- [ ] **9.4** Rebranchez : le calque suit, sans décalage d'échelle.

## 10. Les images produites

Ouvrez les PNG du dernier dossier.

- [ ] **10.1** Une image par marque, nommée `marque-NN.png`.
- [ ] **10.2** La marque est **centrée** dans son image, avec du contexte autour.
- [ ] **10.3** Le badge porte le bon numéro et la bonne intention.
- [ ] **10.4** Le badge **ne recouvre pas** ce que la marque désigne — en particulier la pointe
      d'une flèche.
- [ ] **10.5** Le trait est cerné d'un halo : **sombre sur fond clair, clair sur fond sombre**.
      Testez sur une fenêtre en thème sombre.
- [ ] **10.6** **R12** — posez quatre marques, puis regardez la quatrième image : les trois autres
      étaient à l'écran, **aucune ne doit y figurer**.
- [ ] **10.7** Faites un `⌘⇧4` pendant que le calque est affiché : **l'encre n'apparaît pas** dans
      la capture système.

---

## Ce qui n'existe pas encore — ne le cherchez pas

| Absent | Lot |
|---|---|
| Micro, transcription, fenêtre de parole | 4 et 5 |
| Rapport texte, `feedback.md`, JSON | 3 |
| Serveur MCP, `get_feedback` | 6 |
| Presse-papiers, envoi à Claude Code | 3 |
| Détection du projet cible — tout va dans `~/Regarde/sessions/` | 3 |
| Mode annotation verrouillé (`⌃⌥L`) | ultérieur |
| Verrou du micro (`⌃⌥M`) | 5 |
| Réglages, personnalisation du modificateur | ultérieur |
| Application signée et distribuable | 8, bloqué sur un compte Apple Developer |

## Ce que je veux savoir en retour

1. **Tout échec**, avec le numéro du test et ce que le journal disait au même moment.
2. **Les intentions sur AZERTY** (`⌥⌘` + `& é " ' ( -`) : utilisable, ou insupportable ?
3. **La latence du trait** : imperceptible, ou vous la sentez ?
4. **Le mode éclair** : le délai avant publication est-il trop court pour enchaîner, trop long
   pour être réactif ?
5. Tout ce qui vous a fait hésiter, même sans être un bug — c'est ce qui coûte le plus cher plus tard.
