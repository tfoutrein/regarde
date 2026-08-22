#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# La frontière B2, vérifiée mécaniquement
#
# « La règle est absolue et ne souffre aucune exception d'optimisation : le thread
# du tap ne touche JAMAIS un CVPixelBuffer. » (plan, second piège du lot 3)
#
# Un EXC_BAD_ACCESS intermittent dans CVPixelBufferRelease, dont la fréquence
# dépend de l'activité de l'écran, coûte des soirées entières à diagnostiquer
# parce qu'il n'est pas reproductible à la demande. Une règle qu'on ne peut que
# se rappeler est une règle qu'on oublie ; celle-ci se vérifie en une seconde.
#
# Le contrôle est lexical et il l'assume : il regarde si un type de tampon
# APPARAÎT dans le code exécutable de `Input/`. C'est grossier, et c'est
# précisément ce qu'il faut — la frontière est une règle de fichier, pas une
# subtilité de flot de contrôle.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="${ROOT}/Sources/Regarde/Input"

echo "── Frontière B2 ──"

# Les commentaires sont retirés : ce fichier PARLE de CVPixelBuffer pour dire
# qu'il n'y touche pas, et cette phrase ne doit pas faire échouer le contrôle.
FAUTES=$(grep -rnE "CVPixelBuffer|CVImageBuffer|CMSampleBuffer|IOSurface" "${INPUT}"/*.swift 2>/dev/null \
         | grep -vE ":[0-9]+: *(//|///|\*)" | grep -vE "^\s*[0-9]+: *//" || true)

if [[ -n "${FAUTES}" ]]; then
    echo "  ✗ un type de tampon apparaît dans le code de Input/ :"
    echo "${FAUTES}" | sed 's/^/      /'
    echo
    echo "  Le tap pousse un triplet dans un anneau lock-free, et rien d'autre."
    echo "  L'appariement se fait sur encodeQueue, seule propriétaire des frames."
    exit 5
fi
echo "  ✓ aucun type de tampon dans le code exécutable de Input/"

# L'autre moitié : l'anneau de frames doit GARDER sa file, et pas seulement le
# promettre en commentaire.
GARDES=$(grep -c "dispatchPrecondition" "${ROOT}/Sources/Regarde/Capture/FrameRing.swift" 2>/dev/null || echo 0)
if [[ "${GARDES}" -lt 3 ]]; then
    echo "  ✗ seulement ${GARDES} garde(s) de file dans FrameRing — on en attend au moins 3"
    exit 5
fi
echo "  ✓ ${GARDES} gardes dispatchPrecondition dans FrameRing"

# Et le tap ne doit rien réveiller : pas de saut vers le main actor depuis son
# callback. C'est la règle du lot 0, dont B2 est la version dure.
REVEILS=$(grep -nE "MainActor\.run|DispatchQueue\.main|Task \{ @MainActor" "${INPUT}/EventTap.swift" 2>/dev/null \
          | grep -vE ":[0-9]+: *//" || true)
if [[ -n "${REVEILS}" ]]; then
    echo "  ⚠ le tap saute vers le main actor :"
    echo "${REVEILS}" | sed 's/^/      /'
fi
echo
echo "La frontière tient."
