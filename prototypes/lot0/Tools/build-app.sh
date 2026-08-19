#!/usr/bin/env bash
# Construit Regarde0.app, le signe avec l'identite stable, et l'installe a un CHEMIN FIXE.
#
# Le chemin fixe compte autant que la signature stable (plan § 4.2) : le chemin DerivedData
# change d'un build a l'autre et emmene l'autorisation TCC avec lui.
#
# Usage :
#   ./Tools/build-app.sh              build release, signe, installe, ne lance pas
#   ./Tools/build-app.sh --run        idem puis relance l'application
#   ./Tools/build-app.sh --debug      build debug (symboles, plus lent)

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

CERT_NAME="Regarde Dev"
APP_NAME="Regarde0"
BUNDLE_ID="dev.tfoutrein.regarde.lot0"
INSTALL_DIR="${HOME}/Applications"
INSTALLED="${INSTALL_DIR}/${APP_NAME}.app"

CONFIG="release"
RUN=0
for arg in "$@"; do
    case "${arg}" in
        --debug) CONFIG="debug" ;;
        --run)   RUN=1 ;;
        *) echo "Option inconnue : ${arg}" >&2; exit 2 ;;
    esac
done

if ! security find-identity -v -p codesigning | grep -qF "${CERT_NAME}"; then
    echo "✗ Identite de signature « ${CERT_NAME} » introuvable."
    echo "  Lance d'abord : ./Tools/make-cert.sh"
    exit 1
fi

echo "→ swift build -c ${CONFIG}"
swift build -c "${CONFIG}"
BIN="${ROOT}/.build/${CONFIG}/${APP_NAME}"
[[ -x "${BIN}" ]] || { echo "✗ Binaire introuvable : ${BIN}"; exit 1; }

STAGE="${ROOT}/.build/${APP_NAME}.app"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/Contents/MacOS" "${STAGE}/Contents/Resources"
cp "${BIN}" "${STAGE}/Contents/MacOS/${APP_NAME}"
cp "${ROOT}/Resources/Info.plist" "${STAGE}/Contents/Info.plist"
printf 'APPL????' > "${STAGE}/Contents/PkgInfo"

echo "→ codesign (identite stable, identifiant fige)"
codesign --force --sign "${CERT_NAME}" \
    --identifier "${BUNDLE_ID}" \
    --timestamp=none \
    "${STAGE}" 2>&1 | sed 's/^/   /'

codesign --verify --verbose=1 "${STAGE}" 2>&1 | sed 's/^/   /'

# L'exigence designee est ce que TCC memorise. Si elle change, les autorisations sautent :
# on l'affiche a chaque build pour pouvoir constater une derive au lieu de la subir.
echo "→ Exigence designee (ce que TCC retient) :"
codesign -d -r- "${STAGE}" 2>&1 | grep -E '^designated' | sed 's/^/   /' || true

# Quitter l'instance en cours AVANT de remplacer le bundle : remplacer un .app en cours
# d'execution laisse un processus vivant sur un binaire fantome, et le tap semble « mort »
# pour une raison qui n'a rien a voir avec le code.
if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    echo "→ Arret de l'instance en cours"
    pkill -x "${APP_NAME}" || true
    for _ in $(seq 1 20); do pgrep -x "${APP_NAME}" >/dev/null 2>&1 || break; sleep 0.1; done
fi

mkdir -p "${INSTALL_DIR}"
rm -rf "${INSTALLED}"
cp -R "${STAGE}" "${INSTALLED}"
echo "✓ Installe : ${INSTALLED}"

if [[ "${RUN}" -eq 1 ]]; then
    echo "→ Lancement"
    open "${INSTALLED}"
    echo
    echo "Journal : log stream --predicate 'subsystem == \"${BUNDLE_ID}\"' --level info"
else
    echo
    echo "Lancer :  open \"${INSTALLED}\""
fi

cat <<'RAPPEL'

┌─ Rappel du § 4.2 ────────────────────────────────────────────────────────┐
│ Ne jamais deboguer plus de dix minutes sans avoir verifie que le tap est │
│ vivant. Le compteur d'evenements de T0.4 est le temoin permanent.        │
│                                                                          │
│ Si l'autorisation saute : Reglages > Confidentialite et securite >       │
│ Surveillance de la saisie — retirer l'entree, la remettre, relancer.     │
└──────────────────────────────────────────────────────────────────────────┘
RAPPEL
