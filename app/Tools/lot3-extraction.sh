#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# S39 — l'extraction, et l'invariant qui la garde
#
# UNE SEULE PORTE VERS L'ASSET. `AVAssetImageGenerator` ne doit apparaître que
# dans le fichier qui porte `assetTime` — sinon il existe un second endroit où
# demander une image, et donc un second endroit où se tromper de temps. C'est
# exactement B1 : un décalage constant, invisible sur écran statique.
#
# Le contrôle exclut les COMMENTAIRES. Trois fichiers PARLENT du générateur pour
# expliquer pourquoi ils ne l'appellent pas ; les compter ferait échouer un
# contrôle qui a raison.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/Sources/Regarde"
PORTEUR="AssetFrames.swift"

echo "── Une seule porte vers l'asset ──"

# On retire les lignes de commentaire avant de chercher : `//`, `///`, et les
# lignes de bloc `*`.
FAUTES=""
while IFS= read -r f; do
    [[ "$(basename "$f")" == "${PORTEUR}" ]] && continue
    # `grep -n` sur un fichier UNIQUE ne préfixe pas le nom : la ligne commence
    # directement par le numéro. Un motif attendant un deux-points initial ne
    # matcherait rien, et le contrôle échouerait sur ses propres commentaires.
    HITS=$(grep -nE "AVAssetImageGenerator" "$f" | grep -vE "^[0-9]+: *(///|//|\*)" || true)
    [[ -n "${HITS}" ]] && FAUTES+="${f}:\n${HITS}\n"
done < <(grep -rl "AVAssetImageGenerator" "${SRC}" 2>/dev/null || true)

if [[ -n "${FAUTES}" ]]; then
    echo "  ✗ AVAssetImageGenerator apparaît hors de ${PORTEUR} :"
    printf "%b" "${FAUTES}" | sed 's/^/      /'
    exit 5
fi
echo "  ✓ AVAssetImageGenerator n'est appelé que dans ${PORTEUR}"

# Les tolérances doivent y être posées explicitement, et dans le bon sens.
AVANT=$(grep -c "requestedTimeToleranceBefore = .zero" "${SRC}/Capture/${PORTEUR}" || echo 0)
APRES=$(grep -c "requestedTimeToleranceAfter = .zero" "${SRC}/Capture/${PORTEUR}" || echo 0)
if [[ "${AVANT}" -lt 1 || "${APRES}" -lt 1 ]]; then
    echo "  ✗ les tolérances ne sont pas posées explicitement"
    echo "    Les deux à zéro : le générateur rend la frame dont l'intervalle CONTIENT"
    echo "    l'instant demandé. Avec .positiveInfinity avant, il rendait l'image clé"
    echo "    précédente — mesuré à 812 ms d'écart, sous le GOP d'une seconde."
    exit 5
fi
echo "  ✓ tolérances explicites — zéro des deux côtés"

# Et un seul appel de génération : un par marque rouvrirait l'asset à chaque fois.
# Commentaires exclus ici aussi : l'en-tête du fichier EXPLIQUE pourquoi il n'y a
# qu'un appel, et compter cette phrase ferait échouer le contrôle qu'elle décrit.
APPELS=$(grep -nE "generateCGImagesAsynchronously" "${SRC}/Capture/${PORTEUR}" \
         | grep -vcE "^[0-9]+: *(///|//|\*)" || echo 0)
if [[ "${APPELS}" -ne 1 ]]; then
    echo "  ✗ ${APPELS} appels à generateCGImagesAsynchronously — on en veut exactement un"
    exit 5
fi
echo "  ✓ un seul appel de génération, à qui l'on passe tous les temps"

echo
echo "L'invariant tient. Le reste — l'écart demandé/obtenu par marque — se lit"
echo "dans le bloc EXTRACTION du journal après une vraie session."
