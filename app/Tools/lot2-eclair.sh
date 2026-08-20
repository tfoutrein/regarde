#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Mode éclair — S27, spécification § 2.1
#
# Le mode qui doit battre ⌘⇧4 : aucune session ouverte, aucun raccourci préalable.
# On prend ⌥⌘, on trace, on relâche, et le dossier existe.
#
# Ce que le script prouve : que ⌥⌘ arme sur la fenêtre regardée sans qu'on ait rien
# ouvert, que la rafale reste un seul dossier, et que la publication part au relâchement.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS="$ROOT/../prototypes/lot0/.build/harness"
JOURNAL="$HOME/Regarde/journal.txt"
BEFORE=$(ls -1 "$HOME/Regarde/sessions" 2>/dev/null | wc -l | tr -d ' ')

pkill -x Regarde 2>/dev/null || true
sleep 1

osascript <<'AS' >/dev/null
tell application "TextEdit"
    activate
    if (count of documents) = 0 then make new document
    set text of front document to ""
    set bounds of front window to {120, 120, 1200, 820}
end tell
AS
sleep 1

open -a "$HOME/Applications/Regarde.app"
sleep 5
osascript -e 'tell application "TextEdit" to activate' >/dev/null
sleep 2

echo "→ Aucune session ouverte — ⌥⌘ doit armer quand même"
grep -E "cible suivie|tap démarré" "$JOURNAL" | tail -2 || true

echo
echo "→ Rafale de quatre marques, sans ⌃⌥S"
"$HARNESS" lot2 --x 300 --y 300
sleep 4

echo
echo "── Journal ──"
grep -E "marque |outil :|éclair|cible " "$JOURNAL" | tail -16

AFTER=$(ls -1 "$HOME/Regarde/sessions" 2>/dev/null | wc -l | tr -d ' ')
echo
echo "→ Dossiers avant : $BEFORE, après : $AFTER"
if [ "$AFTER" -eq "$((BEFORE + 1))" ]; then
    echo "✓ La rafale a produit UN dossier, pas quatre"
else
    echo "✗ $((AFTER - BEFORE)) dossiers créés"
fi
LAST=$(ls -1dt "$HOME/Regarde/sessions"/*/ | head -1)
ls -1 "$LAST/frames" 2>/dev/null | sed 's/^/   /'
