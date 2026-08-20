#!/usr/bin/env bash
# LA commande unique pour une session de test.
#
#   ./Tools/start.sh          construit, installe, lance l'application et le temoin
#   ./Tools/start.sh --quick  ne reconstruit pas : relance seulement
#
# Enchaine tout ce qu'une session demande, dans l'ordre qui evite les faux
# diagnostics : auto-test de la porte d'abord (il ne demande aucune permission et
# echoue vite), puis build signe, puis lancement, puis verification de l'etat reel.

set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP="${HOME}/Applications/Regarde0.app"
PORT=8765
QUICK=0
[[ "${1:-}" == "--quick" ]] && QUICK=1

hr() { printf '─%.0s' {1..72}; echo; }

if [[ "${QUICK}" -eq 0 ]]; then
    hr
    echo "1/4  Auto-test de la porte"
    hr
    # En premier : la logique de la porte ne demande ni permission ni ecran. Si elle
    # est fausse, inutile d'aller plus loin — et on le sait en deux secondes.
    swift build -c release >/dev/null 2>&1
    if ! "${ROOT}/.build/release/Regarde0" --selftest; then
        echo
        echo "✗ L'auto-test echoue. Ne pas passer aux criteres avant correction."
        exit 1
    fi

    hr
    echo "2/4  Construction et signature"
    hr
    "${ROOT}/Tools/build-app.sh" 2>&1 | grep -E "^→ codesign|^✓|designated|^✗" || true
else
    echo "→ Mode rapide : pas de reconstruction."
fi

hr
echo "3/4  Lancement"
hr
pkill -x Regarde0 2>/dev/null && echo "  instance precedente arretee"
for _ in $(seq 1 20); do pgrep -x Regarde0 >/dev/null 2>&1 || break; sleep 0.1; done

open "${APP}"
echo "  application lancee"

if curl -s -o /dev/null --max-time 1 "http://localhost:${PORT}/index.html" 2>/dev/null; then
    echo "  temoin deja servi sur ${PORT}"
    open -a "Google Chrome" "http://localhost:${PORT}/index.html" 2>/dev/null
else
    echo "  demarrage du temoin sur ${PORT}"
    nohup "${ROOT}/Tools/serve-temoin.sh" "${PORT}" >/dev/null 2>&1 &
fi

# Laisser l'application finir son lancement et le watchdog faire une passe.
sleep 4

hr
echo "4/4  Etat"
hr
"${ROOT}/Tools/status.sh"

cat <<'RAPPEL'

────────────────────────────────────────────────────────────────────────
  ⌥⌘ + glisser   tracer            Échap   annuler le trait en cours
  relâcher       rendre la souris  ⌥⌘Z     supprimer le dernier trait

  Protocole de test complet :  PROTOCOLE.md
  Vérifier l'état à tout moment :  ./Tools/status.sh
────────────────────────────────────────────────────────────────────────
RAPPEL
