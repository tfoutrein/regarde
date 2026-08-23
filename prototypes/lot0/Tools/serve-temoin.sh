#!/usr/bin/env bash
# Sert le temoin 1 en local et l'ouvre dans Chrome.
#
# Servi en HTTP plutot qu'ouvert en file:// pour trois raisons : navigator.clipboard
# exige un contexte securise (127.0.0.1 en est un, file:// non), le comportement de
# requestAnimationFrame sous file:// n'est pas garanti identique, et depuis S29 la
# page DEPOSE son etat par POST — ce qu'un file:// ne peut pas faire.
#
# Ce script est desormais un enrobage de `temoin-serveur.py`. `python3 -m http.server`
# ne convient plus : il ne definit que do_GET et do_HEAD, donc un POST recoit 501. Le
# piege n'est pas qu'il refuse, c'est qu'il reste JOIGNABLE — la page se charge
# normalement et seul le depot echoue, en fin de mesure, sans rien dire.
#
# Pour une campagne automatisee, prefere `app/Tools/lot3-temoin.sh`, qui pilote tout.
# Celui-ci reste la voie manuelle.

set -euo pipefail
ICI="$(cd "$(dirname "$0")" && pwd)"
LOT0="$(cd "${ICI}/.." && pwd)"

PORT="${1:-8765}"
DEPOT="${REGARDE_DEPOT:-$HOME/Regarde-lot0/temoin}"
URL="http://127.0.0.1:${PORT}/index.html"

mkdir -p "${DEPOT}"
chmod 700 "${DEPOT}"

# 127.0.0.1 et non localhost : sur macOS `localhost` resout ::1 en premier alors que
# le serveur ecoute en IPv4, ce qui ajoute un aller-retour de repli a chaque requete.
SIGNATURE="$(curl -s --max-time 1 "http://127.0.0.1:${PORT}/sante" 2>/dev/null || true)"
if [[ "${SIGNATURE}" == *'"serveur":"regarde-temoin"'* || "${SIGNATURE}" == *'"serveur": "regarde-temoin"'* ]]; then
    echo "→ Serveur du temoin deja en place sur ${PORT}, reutilisation."
elif [[ -n "${SIGNATURE}" ]]; then
    # Le cas le plus courant, et de loin : un `python3 -m http.server` d'avant S29,
    # ou d'un tout autre projet, resté en fond depuis des jours. Le dire suffisait
    # mal — il faut aussi montrer QUI occupe le port et donner le geste exact.
    echo "✗ Un serveur repond sur ${PORT}, mais ce n'est pas celui du temoin."
    echo "  Il ne sait pas recevoir les depots : la page se chargerait normalement"
    echo "  et seul le depot echouerait, en fin de mesure."
    echo
    OCCUPANT="$(lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null | tail -n +2)"
    if [[ -n "${OCCUPANT}" ]]; then
        echo "  Qui occupe le port :"
        echo "${OCCUPANT}" | sed 's/^/    /'
        PID="$(echo "${OCCUPANT}" | awk '{print $2}' | head -1)"
        echo
        echo "  Pour l'arreter :  kill ${PID}"
    fi
    echo "  Ou choisis un autre port : $0 <port>"
    exit 2
else
    echo "→ Serveur sur ${PORT} (Ctrl-C pour arreter) — depot dans ${DEPOT}"
    python3 "${ICI}/temoin-serveur.py" --port "${PORT}" \
            --racine "${LOT0}/temoins" --depot "${DEPOT}" --duree-max 7200 &
    SRV=$!
    trap 'kill ${SRV} 2>/dev/null || true' EXIT
    for _ in $(seq 1 50); do
        curl -s --max-time 1 "http://127.0.0.1:${PORT}/sante" >/dev/null 2>&1 && break
        sleep 0.1
    done
fi

if [[ -d "/Applications/Google Chrome.app" ]]; then
    open -a "Google Chrome" "${URL}"
else
    echo "⚠  Chrome introuvable — ouverture dans le navigateur par defaut."
    echo "   Le temoin 1 doit tourner dans Chrome : c'est le chemin de composition a mesurer."
    open "${URL}"
fi

cat <<EOF

Temoin 1 : ${URL}
Depot    : ${DEPOT}

  1  horloge   C3   la trotteuse doit tourner pendant le trace
  2  charge    C3b  relever 3 etats, puis les 3 memes en ordre inverse
  3  compteur  C11  la reglette porte le numero, lisible par machine

Les modes 2 et 3 sont un SEUL moteur depuis S29 : le compteur tourne desormais
par-dessus la charge. Un banc C11 qui ne mesurait que sur ecran au repos ne
mesurait rien de ce qui justifie le produit.

Verbes de pilotage — tous en Controle+Option, apparies sur la touche PHYSIQUE :

  ⌃⌥R  relever        ⌃⌥D  deposer        ⌃⌥X  fin de plan
  ⌃⌥G  reglette       ⌃⌥N  chiffres       ⌃⌥A  aligner l'horloge
  ⌃⌥H  panneau        ⌃⌥Z  reset fuites   ⌃⌥1/2/3  mode

⌃⌥S, ⌃⌥F, ⌃⌥M et ⌃⌥L sont INTERDITS ici : Regarde les enregistre en raccourcis
globaux, et ils ne parviendraient jamais a la page.

Passer en plein ecran AVANT toute mesure, par le menu Presentation — le mode
fenetre n'emprunte pas le meme chemin de composition, et ⌃⌘F ne suffit pas.
EOF

wait 2>/dev/null || true
