#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Les marques publiées ne doivent pas ressurgir au ré-armement
#
# Un panneau retiré de l'écran est GELÉ : il ignore les ordres de dessin, y compris celui
# qui le vide après une publication. Il réapparaissait donc avec son contenu périmé, et ne
# s'en débarrassait qu'au premier point du tracé suivant — sur le seul écran où l'on
# traçait, les autres gardant leurs fantômes indéfiniment.
#
# Le contrôle est quantitatif : on compte les pixels d'encre à trois instants, et c'est le
# retour au niveau du témoin qui prouve l'effacement. « Je n'ai rien vu » ne prouverait
# rien, puisque le défaut n'apparaît qu'après un délai.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS="$ROOT/../prototypes/lot0/.build/harness"
INK="$ROOT/.build/count-ink"
OUT="$ROOT/.build/lot2"
REGION="100,100,900,600"
mkdir -p "$OUT"

pkill -x Regarde 2>/dev/null || true
sleep 1
osascript <<'AS' >/dev/null
tell application "TextEdit"
    activate
    if (count of documents) = 0 then make new document
    set bounds of front window to {100, 100, 1000, 700}
end tell
AS
sleep 2

screencapture -x -R"$REGION" "$OUT/fantome-temoin.png"
BASE=$("$INK" "$OUT/fantome-temoin.png" | grep -o '^[0-9]*')
echo "témoin (scène nue)        $BASE px"

# `--visible-capture` : sans lui le calque est absent des captures, et c'est justement lui
# qu'on mesure ici.
open -a "$HOME/Applications/Regarde.app" --args --visible-capture
sleep 5
osascript -e 'tell application "TextEdit" to activate' >/dev/null
sleep 1

"$HARNESS" ghost --x 300 --y 250 --hold 6000 &
HP=$!
sleep 1.2
screencapture -x -R"$REGION" "$OUT/fantome-pendant.png"
DUR=$("$INK" "$OUT/fantome-pendant.png" | grep -o '^[0-9]*')
echo "pendant le tracé          $DUR px"

sleep 7
screencapture -x -R"$REGION" "$OUT/fantome-rearme.png"
AFTER=$("$INK" "$OUT/fantome-rearme.png" | grep -o '^[0-9]*')
echo "au ré-armement            $AFTER px"
wait $HP || true

echo
if [ "$DUR" -gt "$((BASE + 500))" ] && [ "$AFTER" -le "$((BASE + 100))" ]; then
    echo "✓ l'encre s'affiche pendant le tracé et ne revient pas au ré-armement"
    exit 0
else
    echo "✗ l'encre publiée ressurgit au ré-armement"
    exit 1
fi
