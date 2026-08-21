#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Passage du livrable du lot 2 — S28
#
# Le critère : « 6 marques, 4 outils, 2 écrans dont un externe non-Retina placé à gauche
# (origine négative). 6 PNG au bon endroit, bon numéro, aucun pixel du calque ni du HUD,
# aucun décalage ×2. »
#
# Les deux écrans comptent parce qu'ils ont des échelles DIFFÉRENTES — @2× et @1×. Un
# facteur global supposé quelque part produirait des marques justes sur l'un et décalées
# du double sur l'autre : un défaut invisible tant qu'on teste sur un seul écran.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS="$ROOT/../prototypes/lot0/.build/harness"
JOURNAL="$HOME/Regarde/journal.txt"

pkill -x Regarde 2>/dev/null || true
sleep 1

place() {   # place TextEdit : gauche haut droite bas, espace écran (origine en haut à gauche)
  osascript <<AS >/dev/null
tell application "TextEdit"
    activate
    if (count of documents) = 0 then make new document
    set bounds of front window to {$1, $2, $3, $4}
end tell
AS
}

echo "→ Écran principal (@2×)"
place 120 120 1200 820
sleep 1
open -a "$HOME/Applications/Regarde.app"
sleep 5
osascript -e 'tell application "TextEdit" to activate' >/dev/null
sleep 2

echo "→ ⌃⌥S : session explicite, cible figée"
osascript -e 'tell application "System Events" to key code 1 using {control down, option down}'
sleep 2
grep -E "cible figée" "$JOURNAL" | tail -1 || true

echo "→ Marques 1 à 3 : flèche, cadre, point"
"$HARNESS" triplet --x 300 --y 300 --tools fleche,cadre,point --marks 2,1,4
sleep 2

echo
echo "→ Écran externe (@1×, origine négative)"
place -800 -1250 500 -450
sleep 2
osascript -e 'tell application "TextEdit" to activate' >/dev/null
sleep 2
grep -E "cible" "$JOURNAL" | tail -1 || true

echo "→ Marques 4 à 6 : surlignage, flèche, cadre"
"$HARNESS" triplet --x -600 --y -1100 --tools surlignage,fleche,cadre --marks 5,3,6
sleep 2

echo "→ ⌃⌥F : fermeture"
osascript -e 'tell application "System Events" to key code 3 using {control down, option down}'
sleep 5

echo
echo "── Marques ──"
sed -n '/Marques de la session/,$p' "$JOURNAL" | head -9
echo
echo "── Images ──"
LAST=$(ls -1dt "$HOME/Regarde/sessions"/*/ | head -1)
echo "$LAST"
for f in "$LAST"frames/*.png; do
  printf "   %-14s %s\n" "$(basename "$f")" \
    "$(sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null | grep -oE '[0-9]+$' | paste -sd× -)"
done
# Les vues d'ensemble vivent dans le MÊME dossier que les recadrages. Les compter avec
# eux faisait échouer ce contrôle à chaque exécution depuis leur ajout — huit fichiers
# attendus ici pour six marques — et un contrôle de non-régression rouge en permanence ne
# contrôle plus rien. Une vue d'ensemble n'est pas le recadrage d'une marque : le critère
# porte sur les marques, l'ensemble se compte à côté.
#
# Le `|| true` de chaque ligne n'est pas décoratif. Sous `set -euo pipefail`, un glob sans
# correspondance est passé littéralement à `ls`, qui sort en erreur ; `2>/dev/null` masque
# le message mais pas le code, pipefail le propage et errexit tue le script — c'est-à-dire
# exactement dans le cas que ces contrôles existent pour signaler. Sans lui, une session
# sans aucune marque ne donne pas « ✗ 0 marques » : elle ne donne RIEN, code 1, et le
# `place` final n'est jamais atteint. `wc -l` imprime « 0 » de toute façon, donc la valeur
# reste juste ; seul le statut est neutralisé.
MARQUES=$(ls -1 "$LAST"frames/marque-*.png 2>/dev/null | wc -l | tr -d ' ' || true)
ENSEMBLES=$(ls -1 "$LAST"frames/ensemble*.png 2>/dev/null | wc -l | tr -d ' ' || true)
AUTRES=$(ls -1 "$LAST"frames/*.png 2>/dev/null | grep -cv -e '/marque-' -e '/ensemble' || true)
echo
[ "$MARQUES" -eq 6 ] && echo "✓ 6 marques" || echo "✗ $MARQUES marques au lieu de 6"
# Une vue d'ensemble par écran ANNOTÉ : ce scénario en annote deux, donc deux fichiers.
# Un seul voudrait dire qu'un écran a perdu la sienne — précisément la régression qu'un
# script dont tout l'objet est « deux écrans » existe pour attraper.
[ "$ENSEMBLES" -eq 2 ] && echo "✓ 2 vues d'ensemble, une par écran" \
                       || echo "✗ $ENSEMBLES vue(s) d'ensemble au lieu de 2"
[ "$AUTRES" -eq 0 ] && echo "✓ aucun fichier inattendu" \
                    || echo "✗ $AUTRES fichier(s) inattendu(s) dans frames/"

# Remettre la fenêtre sur l'écran principal, pour ne pas laisser le poste dans un état
# inhabituel.
place 120 120 1200 820
