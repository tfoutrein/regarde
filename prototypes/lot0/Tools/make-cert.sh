#!/usr/bin/env bash
# Cree UNE FOIS un certificat de signature de code auto-signe stable, nomme "Regarde Dev".
#
# Pourquoi c'est la premiere chose a faire (plan § 4.2) : TCC identifie une application par
# son identite de signature. Avec `codesign -s -` (ad hoc), cette identite change a chaque
# build, et les autorisations Surveillance de la saisie / Accessibilite sont perdues a chaque
# fois. On passe alors ses soirees a deboguer un tap qui ne demarre pas, pour une raison qui
# n'a aucun rapport avec le code.
#
# Idempotent : ne fait rien si le certificat existe deja.

set -euo pipefail

CERT_NAME="Regarde Dev"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-certificate -c "${CERT_NAME}" "${KEYCHAIN}" >/dev/null 2>&1; then
    echo "✓ Le certificat « ${CERT_NAME} » existe deja dans le trousseau de session."
    security find-identity -v -p codesigning | grep -F "${CERT_NAME}" || {
        echo
        echo "⚠  Il est present mais n'est PAS utilisable pour signer du code."
        echo "   Ouvre Trousseau d'acces, double-clique « ${CERT_NAME} », deplie « Se fier »,"
        echo "   et passe « Signature de code » a « Toujours approuver »."
        exit 1
    }
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "→ Generation d'une paire de cles et d'un certificat auto-signe (10 ans)…"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "${TMP}/key.pem" -out "${TMP}/cert.pem" \
    -subj "/CN=${CERT_NAME}/O=Regarde/C=FR" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    2>/dev/null

openssl pkcs12 -export -legacy \
    -out "${TMP}/regarde-dev.p12" \
    -inkey "${TMP}/key.pem" -in "${TMP}/cert.pem" \
    -name "${CERT_NAME}" -passout pass:

echo "→ Import dans le trousseau de session…"
security import "${TMP}/regarde-dev.p12" \
    -k "${KEYCHAIN}" -P "" \
    -T /usr/bin/codesign -T /usr/bin/security

# Sans cette ligne, codesign ouvre une invite de mot de passe a CHAQUE build.
echo "→ Autorisation de codesign a utiliser la cle sans invite…"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "${KEYCHAIN}" >/dev/null 2>&1 || {
    echo "⚠  set-key-partition-list a echoue. Une invite de mot de passe apparaitra au premier"
    echo "   codesign : coche « Toujours autoriser »."
}

echo "→ Marquage du certificat comme digne de confiance pour la signature de code…"
sudo security add-trusted-cert -d -r trustRoot -p codeSign \
    -k /Library/Keychains/System.keychain "${TMP}/cert.pem" 2>/dev/null || {
    echo
    echo "⚠  add-trusted-cert a echoue (sudo refuse ?)."
    echo "   Solution manuelle : Trousseau d'acces > « ${CERT_NAME} » > Se fier >"
    echo "   Signature de code > Toujours approuver."
}

echo
if security find-identity -v -p codesigning | grep -qF "${CERT_NAME}"; then
    echo "✓ Certificat « ${CERT_NAME} » pret. Identites disponibles :"
    security find-identity -v -p codesigning
else
    echo "⚠  Le certificat est importe mais n'apparait pas comme identite de signature."
    echo "   Passe par Trousseau d'acces comme indique ci-dessus, puis relance ce script."
    exit 1
fi
