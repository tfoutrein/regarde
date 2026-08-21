#!/usr/bin/env bash
# Construit Regarde.app, la signe avec le Hardened Runtime, et l'installe à un
# CHEMIN FIXE.
#
# Le chemin fixe compte autant que la signature stable (plan § 4.2) : le chemin
# DerivedData change d'un build à l'autre et emmène l'autorisation TCC avec lui.
#
# Usage :
#   ./Tools/build-app.sh              build release, signe, installe
#   ./Tools/build-app.sh --run        idem puis relance l'application
#   ./Tools/build-app.sh --debug      build debug
#   ./Tools/build-app.sh --no-hardened  sans Hardened Runtime (diagnostic uniquement)

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

CERT_NAME="Regarde Dev"
APP_NAME="Regarde"
BUNDLE_ID="dev.tfoutrein.regarde"
INSTALL_DIR="${HOME}/Applications"
INSTALLED="${INSTALL_DIR}/${APP_NAME}.app"
ENTITLEMENTS="${ROOT}/Resources/${APP_NAME}.entitlements"

CONFIG="release"
RUN=0
HARDENED=1
for arg in "$@"; do
    case "${arg}" in
        --debug)        CONFIG="debug" ;;
        --run)          RUN=1 ;;
        --no-hardened)  HARDENED=0 ;;
        *) echo "Option inconnue : ${arg}" >&2; exit 2 ;;
    esac
done

if ! security find-identity -v -p codesigning | grep -qF "${CERT_NAME}"; then
    echo "✗ Identité de signature « ${CERT_NAME} » introuvable."
    echo "  Lance d'abord : ../prototypes/lot0/Tools/make-cert.sh"
    exit 1
fi

echo "→ swift build -c ${CONFIG}"
# La sortie est CAPTURÉE au passage, et non relue par un second appel : SwiftPM ne
# réémet pas ses avertissements sur un build en cache, si bien qu'une seconde
# invocation en compte toujours zéro. C'est le piège dans lequel la première version de
# ce garde-fou est tombée.
BUILD_LOG="$(mktemp)"
trap 'rm -f "${BUILD_LOG}"' EXIT
# `pipefail` est déjà armé en tête de script : le `set -o pipefail` qui figurait ici était
# mort, et le `set +o pipefail` qui suivait le désarmait pour TOUT le reste — y compris
# `codesign … | sed` plus bas, dont le statut devenait celui de `sed`, donc toujours zéro.
# Une signature en échec (trousseau verrouillé, entitlements déplacés) passait alors
# inaperçue, `--verify` était avalé de la même façon, et le script remplaçait le bundle
# signé par un bundle qui ne l'était pas en annonçant « ✓ Installé ». Au lancement suivant
# l'identité de signature ayant changé, TCC redemandait Accessibilité et Enregistrement de
# l'écran — précisément la panne que le chemin fixe et le certificat stable existent pour
# empêcher. On laisse donc `pipefail` armé de bout en bout.
swift build -c "${CONFIG}" 2>&1 | tee "${BUILD_LOG}"

# Les avertissements se comptent, sinon ils défilent avec le reste et personne ne les
# voit. Deux d'entre eux ont atteint l'auteur avant moi.
WARNINGS="$(grep -cE "warning: " "${BUILD_LOG}" || true)"
if [ "${WARNINGS:-0}" -gt 0 ]; then
    echo
    echo "⚠ ${WARNINGS} avertissement(s) de compilation — à corriger avant de livrer"
    # `|| true` : `head -8` ferme le tube après huit lignes, et au-delà de ce que le
    # tampon absorbe `sed` prend un SIGPIPE. Maintenant que `pipefail` reste armé, ça
    # tuerait le script — au moment précis où il y a beaucoup d'avertissements à lire.
    # Le statut d'un affichage de diagnostic ne veut rien dire de toute façon.
    grep -E "warning: " "${BUILD_LOG}" | sed 's|.*/Sources/Regarde/|   |' | head -8 || true
    echo
fi
BIN="${ROOT}/.build/${CONFIG}/${APP_NAME}"
[[ -x "${BIN}" ]] || { echo "✗ Binaire introuvable : ${BIN}"; exit 1; }

STAGE="${ROOT}/.build/${APP_NAME}.app"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/Contents/MacOS" "${STAGE}/Contents/Resources"
cp "${BIN}" "${STAGE}/Contents/MacOS/${APP_NAME}"
cp "${ROOT}/Resources/Info.plist" "${STAGE}/Contents/Info.plist"
printf 'APPL????' > "${STAGE}/Contents/PkgInfo"

# La version se DÉRIVE du dépôt, elle ne se recopie pas à la main.
#
# Le plist du dépôt a annoncé 0.1.0 pendant les releases v0.2.0 et v0.2.1, parce que rien
# ne reliait les deux : une valeur écrite une fois puis oubliée. Le tag est la source de
# vérité — c'est lui qui nomme la release — et le nombre de commits donne un
# `CFBundleVersion` monotone, ce que la notarisation du lot 8 exigera.
#
# En l'absence de tag (dépôt fraîchement cloné sans historique, archive) on garde les
# valeurs de repli du plist plutôt que d'inventer un numéro : une version fausse est pire
# qu'une version périmée, parce qu'elle a l'air juste.
if VERSION=$(git -C "${ROOT}/.." describe --tags --abbrev=0 2>/dev/null); then
    VERSION="${VERSION#v}"
    BUILD=$(git -C "${ROOT}/.." rev-list --count HEAD)
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" \
                            "${STAGE}/Contents/Info.plist" >/dev/null
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD}" \
                            "${STAGE}/Contents/Info.plist" >/dev/null
    echo "   version ${VERSION} (build ${BUILD})"
else
    echo "   ⚠ aucun tag git — version de repli du plist conservée"
fi

SIGN_ARGS=(--force --sign "${CERT_NAME}" --identifier "${BUNDLE_ID}" --timestamp=none)
if [[ "${HARDENED}" -eq 1 ]]; then
    # `--options runtime` active le Hardened Runtime, exigé par la notarisation.
    # Il peut modifier le comportement TCC : c'est précisément ce que le critère de
    # S15 vérifie — l'application se lance signée ET le doctor reste vert.
    SIGN_ARGS+=(--options runtime --entitlements "${ENTITLEMENTS}")
    echo "→ codesign (Hardened Runtime + entitlements)"
else
    echo "→ codesign (SANS Hardened Runtime — diagnostic)"
fi

codesign "${SIGN_ARGS[@]}" "${STAGE}" 2>&1 | sed 's/^/   /'
codesign --verify --verbose=1 "${STAGE}" 2>&1 | sed 's/^/   /'

# L'exigence désignée est ce que TCC mémorise. Si elle change, les autorisations
# sautent : on l'affiche à chaque build pour constater une dérive au lieu de la subir.
echo "→ Exigence désignée (ce que TCC retient) :"
codesign -d -r- "${STAGE}" 2>&1 | grep -E '^designated' | sed 's/^/   /' || true

if [[ "${HARDENED}" -eq 1 ]]; then
    echo "→ Runtime et entitlements effectifs :"
    codesign -d --entitlements - --xml "${STAGE}" 2>/dev/null \
        | plutil -convert xml1 -o - - 2>/dev/null \
        | grep -E '<key>|<true|<false' | sed 's/^/   /' || echo "   (aucun)"
    codesign -d -v "${STAGE}" 2>&1 | grep -iE 'flags|runtime' | sed 's/^/   /' || true
fi

# Quitter l'instance en cours AVANT de remplacer le bundle : remplacer un .app en
# cours d'exécution laisse un processus vivant sur un binaire fantôme.
if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    echo "→ Arrêt de l'instance en cours"
    pkill -x "${APP_NAME}" || true
    for _ in $(seq 1 20); do pgrep -x "${APP_NAME}" >/dev/null 2>&1 || break; sleep 0.1; done
fi

mkdir -p "${INSTALL_DIR}"
rm -rf "${INSTALLED}"
cp -R "${STAGE}" "${INSTALLED}"
echo "✓ Installé : ${INSTALLED}"

if [[ "${RUN}" -eq 1 ]]; then
    open "${INSTALLED}"
    echo "→ Lancé. Journal : ~/Regarde/journal.txt"
fi
