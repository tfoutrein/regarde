#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# S46 — le rapport de référence est conforme, et le rester se vérifie
#
# Deux contrôles, et le second garde le premier honnête :
#
#   1. Les SIX sections du contrat de rendu existent, dans l'ordre, et toute
#      section manquante est NOMMÉE — pas « non conforme », mais « il manque
#      Récapitulatif ». Un contrôle qui ne nomme pas fait perdre le temps qu'il
#      prétend économiser.
#
#   2. L'empreinte du fichier est celle inscrite dans lot4-seuils.md. C'est la
#      cible que S49 devra reproduire octet pour octet : si quelqu'un retouche
#      la référence sans mettre à jour le seuil, ce contrôle rougit AVANT que
#      le moteur de rendu n'apprenne à viser une cible qui a bougé.
#
# Usage : lot4-conformite.sh [chemin]   (défaut : le rapport de référence)
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
ICI="$(cd "$(dirname "$0")" && pwd)"
RAPPORT="${1:-${ICI}/lot4-rapport-reference.md}"
SEUILS="${ICI}/../../docs/lot4-seuils.md"

[[ -f "${RAPPORT}" ]] || { echo "✗ rapport introuvable : ${RAPPORT}"; exit 2; }

echo "── Conformité du rapport : $(basename "${RAPPORT}") ──"

# Les six sections du contrat, dans l'ordre du rendu. « Marque » est un TYPE de
# section : au moins une occurrence « ## Marque N — … ».
ECHEC=0

python3 - "${RAPPORT}" <<'PY' || ECHEC=1
import re, sys
texte = open(sys.argv[1], encoding="utf-8").read()
manquantes, desordre = [], []

if not re.search(r"^# Feedback #\d+ — ", texte, re.M):
    manquantes.append("l'en-tête « # Feedback #N — … »")

sections = [
    ("Comment lire ce rapport", r"^## Comment lire ce rapport$"),
    ("Contexte",                r"^## Contexte$"),
    ("Marques",                 r"^## Marque \d+ — "),
    ("Commentaires généraux",   r"^## Commentaires généraux$"),
    ("Récapitulatif",           r"^## Récapitulatif$"),
    ("Suite",                   r"^## Suite$"),
]
positions = []
for nom, motif in sections:
    m = re.search(motif, texte, re.M)
    if not m:
        manquantes.append(nom)
    else:
        positions.append((m.start(), nom))
        print(f"  ✓ {nom}")

for (a, na), (b, nb) in zip(positions, positions[1:]):
    if b < a:
        desordre.append(f"{nb} apparaît avant {na}")

ok = True
for nom in manquantes:
    print(f"  ✗ il manque : {nom}"); ok = False
for d in desordre:
    print(f"  ✗ ordre : {d}"); ok = False
sys.exit(0 if ok else 1)
PY

# L'empreinte, contre le seuil écrit.
ATTENDUE=$(grep -oE "SHA-256 [0-9a-f]{64}" "${SEUILS}" 2>/dev/null | head -1 | cut -d' ' -f2)
REELLE=$(shasum -a 256 "${RAPPORT}" | cut -d' ' -f1)
if [[ -z "${ATTENDUE}" ]]; then
    echo "  ⚠ aucune empreinte dans lot4-seuils.md — contrôle d'empreinte sauté"
elif [[ "${REELLE}" == "${ATTENDUE}" ]]; then
    echo "  ✓ empreinte conforme au seuil de S46 (${REELLE:0:12}…)"
else
    # Sur un fichier AUTRE que la référence (un rendu de S49 en cours de mise au
    # point), l'écart est l'information cherchée, pas une erreur du contrôle.
    echo "  ✗ empreinte ${REELLE:0:12}… ≠ seuil ${ATTENDUE:0:12}…"
    ECHEC=1
fi

if [[ ${ECHEC} -eq 0 ]]; then echo "── conforme ──"; else echo "── NON conforme ──"; exit 1; fi
