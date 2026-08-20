#!/usr/bin/env bash
# Etat reel du prototype, en une commande.
#
# Repond a la question du § 4.2 — « le tap est-il vivant ? » — sans ouvrir un menu
# a la souris. C'est la premiere chose a lancer avant de soupconner quoi que ce soit.
#
# Ne PAS confondre avec `Regarde0 --doctor` : lance depuis un terminal, le binaire
# herite des autorisations du terminal parent et ses preflights mesurent la mauvaise
# identite. Ce script-ci interroge l'application REELLEMENT en cours d'execution.

set -uo pipefail

APP_NAME="Regarde0"
JOURNAL="${HOME}/Regarde-lot0/journal.txt"

if ! pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    echo "✗ ${APP_NAME} ne tourne pas.   →  ./Tools/start.sh"
    exit 1
fi

PID="$(pgrep -x "${APP_NAME}")"
echo "✓ ${APP_NAME} en cours d'execution (pid ${PID})"

# Les titres du menu sont rafraichis chaque seconde, menu ferme : lisibles sans clic.
HEALTH="$(osascript 2>/dev/null <<'EOF'
tell application "System Events"
  tell process "Regarde0"
    try
      set lst to menu items of menu 1 of menu bar item 1 of menu bar 1
      return (name of item 1 of lst) & linefeed & (name of item 2 of lst)
    on error
      return "etat illisible — l'Accessibilite est-elle accordee au Terminal ?"
    end try
  end tell
end tell
EOF
)"

ICON="$(osascript -e 'tell application "System Events" to tell process "Regarde0" to return title of menu bar item 1 of menu bar 1' 2>/dev/null)"
case "${ICON}" in
    "◎") STATE="au repos, tap actif" ;;
    "◍") STATE="calque a l'ecran" ;;
    "◉") STATE="TAP MORT" ;;
    *)   STATE="inconnu" ;;
esac

echo "  icone ${ICON}  —  ${STATE}"
echo "${HEALTH}" | sed 's/^/  /'

echo
echo "Permissions au dernier demarrage (identite reelle de l'application) :"
if [[ -f "${JOURNAL}" ]]; then
    sed -n '/^Permissions/,/Creation effective/p' "${JOURNAL}" | sed 's/^/  /'
    if grep -q "Le tap n'a pas pu demarrer" "${JOURNAL}"; then
        echo
        echo "  ⚠ Le tap a echoue au demarrage. Voir ${JOURNAL}"
    fi
else
    echo "  (aucun journal — l'application n'a jamais demarre depuis cette version)"
fi

echo
if curl -s -o /dev/null -w "" --max-time 1 http://localhost:8765/index.html 2>/dev/null; then
    echo "✓ Temoin servi sur http://localhost:8765/index.html"
else
    echo "✗ Temoin non servi.   →  ./Tools/serve-temoin.sh"
fi
