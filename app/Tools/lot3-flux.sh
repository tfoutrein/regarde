#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# S34 — ce que le flux dit de lui-même
#
# Premier code du lot 3 qu'aucun autotest ne couvre : il faut un écran, une
# autorisation d'enregistrement, et du contenu qui bouge. Ce qui remplace
# l'autotest, c'est un JOURNAL qui dise assez pour qu'une panne se voie sans
# débogueur. Ce script ouvre une session, la laisse tourner, la ferme, et relit
# le journal en cherchant les trois pièges du § 5.2.
#
# Les trois, dans l'ordre où ils coûtent cher :
#
#   1920×1080 SILENCIEUX    sans width/height explicites, la capture sort à cette
#                           taille sans erreur ni avertissement. On ne le
#                           découvre qu'en ouvrant une image et en trouvant le
#                           texte d'un IDE illisible. Le bilan compare le tampon
#                           REÇU aux dimensions DEMANDÉES.
#
#   contentRect qui VARIE   il appartient à la frame, pas au filtre. Une variation
#                           en cours de segment est un événement — changement de
#                           résolution, bascule d'espace — pas du bruit.
#
#   frames qui MANQUENT     ScreenCaptureKit ne livre que sur changement : un
#                           compte bas sur écran figé est NORMAL, un compte bas
#                           sur écran animé ne l'est pas. Le bilan donne le reçu
#                           contre le théorique pour qu'on puisse trancher.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DUREE=20
JOURNAL="${HOME}/Regarde/journal.txt"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --duree) DUREE="$2"; shift 2 ;;
        -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
        *) echo "✗ option inconnue : $1"; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "── S34 · flux de capture, ${DUREE} s ──"
echo
echo "  Ce script ne pilote PAS l'application : il lit ce qu'elle journalise."
echo "  Lance Regarde, puis :"
echo
echo "    1. ⌃⌥S pour ouvrir une session"
echo "    2. laisse tourner ${DUREE} s avec quelque chose qui BOUGE à l'écran"
echo "       (le témoin en mode charge fait l'affaire : prototypes/lot0/Tools/serve-temoin.sh)"
echo "    3. ⌃⌥F pour fermer"
echo
read -r -p "  Entrée quand la session est fermée… " _

[[ -f "${JOURNAL}" ]] || { echo "✗ journal introuvable : ${JOURNAL}"; exit 3; }

echo
echo "── Blocs FLUX du journal ──"
# Le dernier bloc FLUX de chaque écran, et rien d'autre : le journal s'accumule
# d'une session à l'autre, et relire un bloc ancien donnerait un verdict sur une
# session qui n'est pas celle qu'on vient de faire.
awk '/FLUX/{bloc=1} bloc{print} /^$/{bloc=0}' "${JOURNAL}" | tail -40

echo
echo "── Ce qu'il faut y voir ──"
python3 - "${JOURNAL}" <<'PY'
import re, sys

texte = open(sys.argv[1], encoding="utf-8", errors="replace").read()
# On ne regarde que la fin : le journal s'accumule.
queue = texte[-20000:]

controles = []

demande = re.findall(r"demandé\s+(\d+)×(\d+)", queue)
tampon = re.findall(r"tampon réel\s+(\d+)×(\d+)", queue)
if not tampon:
    controles.append(("✗", "aucune frame reçue — le flux n'a rien livré"))
else:
    for (dw, dh), (tw, th) in zip(demande, tampon):
        if (tw, th) == ("1920", "1080") and (dw, dh) != (tw, th):
            controles.append(("✗", f"tampon 1920×1080 pour {dw}×{dh} demandés — "
                                   "width/height ignorés, résolution perdue en silence"))
        elif abs(int(tw) - int(dw)) > 2 or abs(int(th) - int(dh)) > 2:
            controles.append(("✗", f"tampon {tw}×{th} ≠ {dw}×{dh} demandés"))
        else:
            controles.append(("✓", f"dimensions honorées — {tw}×{th}"))

for recues, theoriques in re.findall(r"frames complètes\s+(\d+) sur ~(\d+)", queue):
    r, t = int(recues), int(theoriques)
    if r == 0:
        controles.append(("✗", "zéro frame complète"))
    elif t and r < t * 0.3:
        controles.append(("⚠", f"{r} frames sur ~{t} théoriques — normal si l'écran était "
                               "figé (ScreenCaptureKit ne livre que sur changement), "
                               "anormal s'il bougeait"))
    else:
        controles.append(("✓", f"{r} frames complètes sur ~{t} théoriques"))

for v in re.findall(r"variations\s+(\d+)", queue):
    if int(v) > 0:
        controles.append(("⚠", f"contentRect a varié {v} fois en cours de segment — "
                               "changement de résolution ou bascule d'espace"))
    else:
        controles.append(("✓", "contentRect stable sur tout le segment"))

if not controles:
    print("  Aucun bloc FLUX trouvé dans la fin du journal.")
    print("  La session s'est-elle ouverte ? Cherche « flux non démarré ».")
    sys.exit(3)

for signe, texte_ in controles:
    print(f"  {signe} {texte_}")

if any(s == "✗" for s, _ in controles):
    sys.exit(5)
PY
echo
echo "S34 pose le flux. Il n'écrit encore RIEN sur disque — l'encodage est en S35."
