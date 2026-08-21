#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Vérification visuelle du lot 2 — S20 à S23
#
# Ce que le script prouve, et que l'autotest ne peut pas prouver : que les quatre outils
# ARRIVENT réellement à l'écran, avec la bonne peinture, le bon numéro et la bonne
# intention, après être passés par le tap, la porte, le ring et Core Animation.
#
# L'application est lancée avec `--visible-capture`, sans quoi `sharingType = .none`
# rendrait le calque absent du PNG — R12 fonctionne, c'est justement le problème ici.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS="$ROOT/../prototypes/lot0/.build/harness"
OUT="${1:-$ROOT/.build/lot2}"
SESSIONS="$HOME/Regarde/sessions"
JOURNAL="$HOME/Regarde/journal.txt"

mkdir -p "$OUT"
[ -x "$HARNESS" ] || { echo "harness introuvable : $HARNESS" >&2; exit 1; }

echo "→ Arrêt d'une instance éventuelle"
pkill -x Regarde 2>/dev/null || true
sleep 1

echo "→ Fenêtre cible : TextEdit"
osascript <<'AS'
tell application "TextEdit"
    activate
    if (count of documents) = 0 then make new document
    set bounds of front window to {120, 120, 1200, 820}
end tell
AS
sleep 1

echo "→ Lancement de Regarde en mode capture visible"
open -a "$HOME/Applications/Regarde.app" --args --visible-capture
sleep 3

echo "→ Retour du focus sur la cible"
osascript -e 'tell application "TextEdit" to activate'
sleep 1

echo "→ ⌃⌥S : ouverture de session"
"$HARNESS" hotkey --key 1 >/dev/null 2>&1 || osascript -e 'tell application "System Events" to key code 1 using {control down, option down}'
sleep 2

grep -E "cible |état " "$JOURNAL" | tail -4 || true

echo "→ Scénario : quatre outils, quatre intentions"
# Le harness tourne en arrière-plan et TIENT l'armement 6 s à la fin : le calque
# disparaît au désarmement (ADR-0010), donc la capture doit tomber pendant.
"$HARNESS" lot2 --x 300 --y 300 --hold 6000 &
HARNESS_PID=$!
sleep 6

echo "→ Capture, armement tenu"
screencapture -x "$OUT/lot2-marques.png"
wait $HARNESS_PID

echo "→ ⌃⌥F : fermeture de session"
osascript -e 'tell application "System Events" to key code 3 using {control down, option down}'
sleep 1

sleep 2

echo
echo "── Journal ──"
grep -E "marque |outil :|cible :|intention |chiffre |image" "$JOURNAL" | tail -25

echo
echo "── Artefacts écrits ──"
LAST=$(ls -1dt "$SESSIONS"/*/ 2>/dev/null | head -1 || true)
if [ -n "$LAST" ]; then
    echo "$LAST"
    ls -la "$LAST/frames" 2>/dev/null | tail -8
else
    echo "aucune session écrite"
fi
echo
echo "Capture : $OUT/lot2-marques.png"
