#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Confinement à la fenêtre cible et invisibilité aux captures — S22 et R12
#
# Contrôle 1. Deux gestes identiques, hors de la fenêtre cible. Sans ⇧, rien ne doit
# être posé : c'est le ⌥⌘-clic dans l'éditeur, qui ne doit ni créer de marque ni être
# volé à l'IDE. Avec ⇧, la marque doit exister.
#
# Contrôle 2. Quatre marques affichées, armement TENU, capture d'écran ordinaire :
# le compte de pixels vermillon ne doit pas bouger d'un iota par rapport à la scène nue.
# Un témoin est pris avant toute marque, parce que la fenêtre porte déjà du rouge —
# le bouton de fermeture — et qu'un seuil absolu compterait ce rouge-là comme une fuite.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS="$ROOT/../prototypes/lot0/.build/harness"
INK="$ROOT/.build/count-ink"
OUT="${1:-$ROOT/.build/lot2}"
JOURNAL="$HOME/Regarde/journal.txt"
mkdir -p "$OUT"

pkill -x Regarde 2>/dev/null || true
sleep 1

# La cible est volontairement PETITE et en haut à gauche : le premier scénario trace en
# bas à droite, donc franchement dehors.
osascript <<'AS'
tell application "TextEdit"
    activate
    if (count of documents) = 0 then make new document
    set bounds of front window to {60, 60, 560, 420}
end tell
AS
sleep 1

# Sans `--visible-capture` : c'est la configuration réelle, celle où R12 s'applique.
open -a "$HOME/Applications/Regarde.app"
sleep 3
osascript -e 'tell application "TextEdit" to activate'
sleep 1

echo "→ Témoin : la scène avant toute marque"
screencapture -x -R60,60,500,360 "$OUT/r12-temoin.png"
BASE=$("$INK" "$OUT/r12-temoin.png" | grep -o '^[0-9]*' || true)
echo "   $BASE pixels vermillon déjà présents dans la scène"

osascript -e 'tell application "System Events" to key code 1 using {control down, option down}'
sleep 2

echo
echo "→ Contrôle 2 d'abord : quatre marques affichées, armement tenu"
# Avant le contrôle 1, parce qu'un clic hors cible part à l'application dessous et
# l'ACTIVE — c'est le comportement voulu, mais il changerait l'application au premier
# plan sous le contrôle suivant.
"$HARNESS" lot2 --x 150 --y 150 --hold 6000 &
HP=$!
sleep 6
# La région de la fenêtre cible seulement, et non l'écran entier : le HUD porte lui aussi
# une pastille vermillon, et la compter reviendrait à accuser l'encre d'une fuite qui
# n'est pas la sienne. Mesuré : 723 pixels imputés à tort sur la première tentative.
screencapture -x -R60,60,500,360 "$OUT/r12-armee.png"
wait $HP

echo
echo "→ Contrôle 1 : ⌥⌘ hors cible, puis ⌥⌘⇧"
"$HARNESS" outside --x 900 --y 700
sleep 1
NOW=$("$INK" "$OUT/r12-armee.png" | grep -o '^[0-9]*' || true)
echo "   $NOW pixels vermillon pendant que quatre marques sont affichées"

osascript -e 'tell application "System Events" to key code 3 using {control down, option down}'
sleep 1

echo
if [ "$NOW" -le "$BASE" ]; then
    echo "✓ R12 : aucune encre n'a fui dans la capture ($NOW ≤ $BASE)"
else
    echo "✗ R12 : $((NOW - BASE)) pixels d'encre ont fui dans la capture"
fi

echo
echo "── Journal ──"
sed -n '/Marques de la session/,$p' "$JOURNAL" | head -10
