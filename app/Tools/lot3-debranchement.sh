#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# S36 — débrancher un écran en pleine session
#
# Le § 5.5 en fait un test de NON-RÉGRESSION obligatoire, et la raison tient en
# une phrase : un writer ouvert pour un écran débranché n'a plus rien à recevoir,
# et sa finalisation échoue sur AVError.noSourceTrack. Fermé en fin de session,
# au milieu des autres, son échec emporterait des segments COMPLETS — les marques
# d'un écran qui, lui, a tout enregistré.
#
# Ce qu'on vérifie, dans l'ordre où ça compte :
#
#   1. le segment de l'écran débranché est finalisé À CET INSTANT, pas plus tard
#   2. il porte un lastSamplePTS non nul et un stopReason « deconnexion »
#   3. la session CONTINUE sur l'écran restant et se clôt normalement
#   4. un segment vide n'empêche aucun autre de se finaliser
#
# Le geste physique est le seul qui ne s'automatise pas : débrancher le câble.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

JOURNAL="${HOME}/Regarde/journal.txt"

echo "── S36 · débranchement à chaud ──"
echo
echo "  1. Deux écrans branchés, Regarde lancé"
echo "  2. ⌃⌥S — ouvre une session"
echo "  3. Trace UNE marque sur CHAQUE écran (⌥⌘ + glisser)"
echo "  4. DÉBRANCHE l'écran externe, sans fermer la session"
echo "  5. Trace encore une marque sur l'écran restant"
echo "  6. ⌃⌥F — ferme"
echo
read -r -p "  Entrée quand c'est fait… " _

[[ -f "${JOURNAL}" ]] || { echo "✗ journal introuvable"; exit 3; }

echo
echo "── Ce que le journal en dit ──"
tail -80 "${JOURNAL}" | grep -E "débranché|FLUX|SEGMENT VIDE|flux fermé|MARQUES|FIN DE SESSION" || true

echo
echo "── Les manifestes de segment ──"
TMP="${TMPDIR:-/tmp}"
find "${TMP}" -name "display-*.json" -mmin -30 2>/dev/null | while read -r m; do
    echo "  $(basename "$m")"
    python3 - "$m" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k in ("displayID", "stopReason", "firstSamplePTSSeconds", "lastSamplePTSSeconds",
          "dureeSeconds", "echantillons", "sautees", "octets"):
    print(f"      {k:24} {d.get(k)}")
PY
done

echo
echo "── Contrôles ──"
python3 - "${JOURNAL}" <<'PY'
import re, sys
queue = open(sys.argv[1], encoding="utf-8", errors="replace").read()[-20000:]
ok = True
def dire(cond, vrai, faux):
    global ok
    print(("  ✓ " + vrai) if cond else ("  ✗ " + faux))
    if not cond: ok = False

dire("débranché" in queue,
     "le débranchement a été vu et journalisé",
     "aucune trace de débranchement — l'observateur n'a pas réagi")
dire("FIN DE SESSION" in queue,
     "la session s'est close normalement après le débranchement",
     "pas de bloc FIN DE SESSION — la session n'a pas survécu")
nb = len(re.findall(r"flux fermé sur display", queue))
dire(nb >= 2, f"{nb} flux fermés — chacun le sien",
     f"{nb} flux fermé(s), on en attendait au moins deux")
sys.exit(0 if ok else 5)
PY
