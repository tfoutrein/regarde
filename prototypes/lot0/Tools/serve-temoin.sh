#!/usr/bin/env bash
# Sert le temoin 1 en local et l'ouvre dans Chrome.
#
# Servi en HTTP plutot qu'ouvert en file:// pour deux raisons : navigator.clipboard
# exige un contexte securise (localhost en est un, file:// non), et le comportement
# de requestAnimationFrame sous file:// n'est pas garanti identique.

set -euo pipefail
cd "$(dirname "$0")/../temoins"

PORT="${1:-8765}"
URL="http://localhost:${PORT}/index.html"

if lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "→ Un serveur ecoute deja sur ${PORT}, reutilisation."
else
    echo "→ Serveur sur ${PORT} (Ctrl-C pour arreter)"
    python3 -m http.server "${PORT}" --bind 127.0.0.1 >/dev/null 2>&1 &
    SRV=$!
    trap 'kill ${SRV} 2>/dev/null || true' EXIT
    for _ in $(seq 1 30); do
        lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1 && break
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

  1  horloge   C3   la trotteuse doit tourner pendant le trace
  2  charge    C3b  relever 3 etats, puis les 3 memes en ordre inverse
  3  compteur  C11  lire le numero grave dans l'image
  R  releve de 30 s        A  aligner l'horloge        H  masquer le panneau

Passer en plein ecran (⌃⌘F) avant toute mesure : le mode fenetre n'emprunte pas
le meme chemin de composition.
EOF

wait 2>/dev/null || true
