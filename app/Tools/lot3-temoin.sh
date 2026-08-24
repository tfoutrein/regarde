#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# S29 — le témoin, du démarrage à froid au dépôt validé, en une commande
#
# Le « fini quand » de S29, mot pour mot : « Une commande dépose sur disque, sans
# `execute javascript`, un journal de 60 s portant les couples (numéro de frame,
# now), le numéro de la première entrée conservée et le nombre d'entrées jetées,
# pendant que le canvas de charge tourne — et la même commande dépose un relevé
# C3b complet ; la cadence effective reste entre 70 et 90 % du natif. »
#
# CE QUE CE SCRIPT NE FAIT JAMAIS :
#
#   `osascript … execute javascript`   c'est toute la raison d'être de S29. Cette
#       voie exige d'activer « Autoriser JavaScript depuis les Apple Events » dans
#       Chrome, qui donne l'exécution de JavaScript dans TOUS les onglets, y compris
#       ceux où l'on est authentifié. La page dépose elle-même par POST, et le
#       pilotage passe par des frappes clavier — qui n'exigent que l'Accessibilité.
#
#   recharger ou fermer la page        un rechargement perd `vsyncMs` et
#       `glLoadLocked` ; le calibrage repart, la charge n'est plus la même, et tous
#       les relevés suivants deviennent incomparables. Une campagne = une vie de page.
#
#   conclure sur B1                    S29 POSE l'instrument. Le verdict C11 se
#       rend en S39, sur la chaîne continue. Un banc qui conclut trop tôt est un
#       banc qui ment.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PORT=8765
DUREE=60
PLAN=c11
SORTIE="${HOME}/Regarde-lot0/temoin"
GARDER=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)            PORT="$2"; shift 2 ;;
        --duree)           DUREE="$2"; shift 2 ;;
        --plan)            PLAN="$2"; shift 2 ;;
        --sortie)          SORTIE="$2"; shift 2 ;;
        --garder-serveur)  GARDER=1; shift ;;
        -h|--help)         sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "✗ option inconnue : $1"; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOT0="$(cd "${ROOT}/../prototypes/lot0" && pwd)"
BASE="http://127.0.0.1:${PORT}"

# ── 1. Préalables ────────────────────────────────────────────────────────────
echo "── Préalables ──"
command -v python3 >/dev/null || { echo "✗ python3 introuvable"; exit 2; }
command -v curl    >/dev/null || { echo "✗ curl introuvable"; exit 2; }
[[ -d "/Applications/Google Chrome.app" ]] || {
    echo "✗ Chrome introuvable dans /Applications."
    echo "  Le témoin doit tourner dans Chrome : c'est le chemin de composition mesuré."
    exit 2; }
[[ -f "${LOT0}/temoins/index.html" ]] || { echo "✗ témoin introuvable : ${LOT0}/temoins/index.html"; exit 2; }
mkdir -p "${SORTIE}" && chmod 700 "${SORTIE}" || { echo "✗ dépôt non créable : ${SORTIE}"; exit 2; }
echo "  ✓ python3, curl, Chrome, témoin, dépôt"

# ── 2. Clé de corrélation ────────────────────────────────────────────────────
RUN="c11-$(date +%Y%m%d-%H%M%S)-$$"
DEPOT="${SORTIE}/${RUN}"
echo
echo "── Campagne ──"
echo "  run    ${RUN}"
echo "  dépôt  ${DEPOT}"
echo "  plan   ${PLAN} · durée ${DUREE} s · port ${PORT}"

# Le script connaît TOUS les chemins attendus avant d'ouvrir quoi que ce soit :
# aucun scan de répertoire, aucun « le fichier le plus récent », donc aucune
# confusion possible avec une campagne précédente.
# Le serveur VERSIONNE les dépôts répétés : un second « 02-etat » devient
# « 02-etat~1.json », puis ~2, et le fichier sans suffixe reste la PREMIÈRE
# photo, à jamais. Trouvé le 24 août : la boucle de calibrage relisait 40 fois
# le dépôt initial — calibrated y était False pour l'éternité — pendant que la
# page avait convergé au cinquième dépôt. Lire un état, c'est lire la DERNIÈRE
# version.
dernier() { # nom -> chemin du dépôt le plus récent portant ce nom
    ls -1 "${DEPOT}/$1.json" "${DEPOT}/$1~"*.json 2>/dev/null         | sort -t'~' -k2 -n | tail -1
}
attendre() { # nom, délai en secondes
    local n="$2" i=0
    while [[ -z "$(dernier "$1")" ]]; do
        i=$((i + 1)); [[ ${i} -gt $((n * 4)) ]] && return 1
        sleep 0.25
    done
    return 0
}
lire() { python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
for c in sys.argv[2].split('.'):
    d = d[int(c)] if isinstance(d, list) else d.get(c)
    if d is None: print(''); sys.exit(0)
print(d)" "$(dernier "$1")" "$2" 2>/dev/null || echo ""; }

# ── 3. Serveur, avec contrôle de SIGNATURE ───────────────────────────────────
echo
echo "── Serveur ──"
SIG="$(curl -s --max-time 1 "${BASE}/sante" 2>/dev/null || true)"
if [[ -z "${SIG}" ]]; then
    nohup python3 "${LOT0}/Tools/temoin-serveur.py" --port "${PORT}" \
          --racine "${LOT0}/temoins" --depot "${SORTIE}" --duree-max 7200 \
          > "${SORTIE}/serveur.log" 2>&1 &
    for _ in $(seq 1 50); do
        SIG="$(curl -s --max-time 1 "${BASE}/sante" 2>/dev/null || true)"
        [[ -n "${SIG}" ]] && break
        sleep 0.1
    done
    [[ -n "${SIG}" ]] || { echo "✗ le serveur n'a pas démarré — voir ${SORTIE}/serveur.log"; exit 2; }
    echo "  ✓ démarré (log : ${SORTIE}/serveur.log)"
else
    echo "  · un serveur répond déjà"
fi

# Jamais de réutilisation aveugle. Un ancien `python3 -m http.server` sur ce port
# laisserait la page se charger et ne ferait échouer que le dépôt, en fin de mesure.
python3 - "${SIG}" "${SORTIE}" <<'PY' || exit 2
import json, sys
try:
    s = json.loads(sys.argv[1])
except Exception:
    print("✗ le serveur du port ne rend pas de signature JSON — ce n'est pas celui du témoin.")
    print("  Réponse :", sys.argv[1][:160]); sys.exit(1)
if s.get("serveur") != "regarde-temoin":
    print(f"✗ serveur inattendu : {s.get('serveur')!r}"); sys.exit(1)
if s.get("protocole") != 2:
    print(f"✗ protocole {s.get('protocole')!r} ≠ 2 — serveur d'une autre génération."); sys.exit(1)
import os
if os.path.realpath(s.get("depot","")) != os.path.realpath(sys.argv[2]):
    print(f"✗ le serveur dépose ailleurs : {s.get('depot')}\n  attendu : {sys.argv[2]}"); sys.exit(1)
print(f"  ✓ signature conforme — pid {s.get('pid')}, protocole 2")
PY
[[ ${GARDER} -eq 1 ]] || echo "  · le serveur s'arrêtera seul (--garder-serveur pour le laisser)"

# ── 4. Démarrage à froid ─────────────────────────────────────────────────────
echo
echo "── Page ──"
URL="${BASE}/index.html?run=${RUN}&plan=${PLAN}&mode=compteur&duree=${DUREE}&hud=0&auto=armer&depot=run"
open -a "Google Chrome" "${URL}"
attendre "00-session" 20 || { echo "✗ 00-session.json absent après 20 s — la page a-t-elle chargé ?"; exit 3; }
echo "  ✓ 00-session.json déposé"

# ── 5. Collision de raccourcis ───────────────────────────────────────────────
# Bon marché, et il attrape la régression le jour où quelqu'un déplacera un verbe.
python3 - "${DEPOT}/00-session.json" <<'PY' || exit 7
import json, sys
d = json.load(open(sys.argv[1]))
interdits = {"ctrl+alt+S", "ctrl+alt+F", "ctrl+alt+M", "ctrl+alt+L"}
pris = {v["combo"] for v in d.get("verbes", [])} & interdits
if pris:
    print(f"✗ verbe(s) en collision avec un raccourci GLOBAL de Regarde : {sorted(pris)}")
    print("  Voir app/Sources/Regarde/Input/HotKeyCenter.swift — ⌃⌥S/F/M/L sont enregistrés")
    print("  par RegisterEventHotKey et priment sur l'application au premier plan.")
    sys.exit(1)
print(f"  ✓ {len(d.get('verbes', []))} verbes, aucune collision avec ⌃⌥S/F/M/L")
PY

# ── 6. Géométrie et format ───────────────────────────────────────────────────
python3 - "${DEPOT}/00-session.json" <<'PY' || exit 4
import json, sys
d = json.load(open(sys.argv[1]))
if d.get("protocole") != 2: print(f"✗ protocole {d.get('protocole')} ≠ 2"); sys.exit(1)
r = d["reglette"]
if not r["active"]:
    print(f"✗ réglette inactive — {r['refus']}"); sys.exit(1)
def crc8(G):
    c = 0xA5
    for b in (G & 0xFF, (G >> 8) & 0xFF, (G >> 16) & 0x0F):
        c ^= b
        for _ in range(8): c = ((c << 1) ^ 0x2F) & 0xFF if c & 0x80 else (c << 1) & 0xFF
    return c
for v in r["vecteurs"]:
    G = v["V"] ^ (v["V"] >> 1)
    if v["G"] != G or v["crc"] != crc8(G):
        print(f"✗ vecteur V={v['V']} en désaccord avec la table de référence"); sys.exit(1)
o = r["origineNatifPx"]
print(f"  ✓ réglette active — module {r['module']} px, empreinte {o['w']}×{o['h']} en ({o['x']}, {o['y']})")
print(f"  ✓ les {len(r['vecteurs'])} vecteurs du format s'accordent")
PY

# ── 7. Plein écran ───────────────────────────────────────────────────────────
# Le seul geste que la page ne peut pas faire elle-même : l'API Fullscreen exige un
# geste utilisateur, et le chemin visé est le plein écran NATIF de Chrome. Ni ⌃⌘F ni
# l'attribut AXFullScreen ne le déclenchent — par le menu, comme établi le 20 août.
echo
echo "── Plein écran ──"
osascript -e 'tell application "Google Chrome" to activate' >/dev/null
sleep 1
osascript <<'AS' >/dev/null 2>&1 || echo "  ⚠ menu Présentation inatteignable — passe en plein écran à la main"
tell application "System Events" to tell process "Google Chrome"
    click menu item "Activer le mode plein écran" of menu 1 of menu bar item "Présentation" of menu bar 1
end tell
AS
sleep 2

verbe() { osascript -e "tell application \"System Events\" to key code $1 using {control down, option down}" >/dev/null; }
VR=15; VD=2; VX=7; VG=5; V3=20      # R, D, X, G, 3 — codes PHYSIQUES

verbe ${VD}                          # ⌃⌥D : déposer l'état
attendre "02-etat" 10 || { echo "✗ 02-etat.json absent — les frappes atteignent-elles la page ?"; exit 5; }
PLEIN="$(lire 02-etat pleinEcran)"
echo "  pleinEcran = ${PLEIN}"
[[ "${PLEIN}" == "True" ]] || echo "  ⚠ mode fenêtre — le chemin de composition n'est pas celui du plein écran natif"

# ── 8. Calibrage ─────────────────────────────────────────────────────────────
echo
echo "── Calibrage de la charge ──"
for _ in $(seq 1 40); do
    verbe ${VD}; sleep 2
    [[ "$(lire 02-etat c3b.calibrated)" == "True" ]] && break
done
echo "  vsyncMs            $(lire 02-etat c3b.vsyncMs)"
echo "  refreshHz          $(lire 02-etat c3b.refreshHz)"
echo "  glLoadLocked       $(lire 02-etat c3b.glLoadLocked)"
echo "  chargeInsuffisante $(lire 02-etat c3b.chargeInsuffisante)"
[[ "$(lire 02-etat c3b.chargeInsuffisante)" == "True" ]] && {
    echo "✗ charge GPU insuffisante — le calibrage a atteint sa butée sans faire peiner la machine."
    echo "  Un relevé pris là-dessus ne mesure rien."; exit 5; }

# ── 9. Paire de coût — LA preuve de cadence de S29 ───────────────────────────
echo
echo "── Coût de la réglette ──"
verbe ${VG}; sleep 0.5; verbe ${VR}                       # éteinte
attendre "04-sans-reglette" $((DUREE + 30)) || { echo "✗ 04-sans-reglette.json absent"; exit 3; }
echo "  ✓ sans réglette  $(lire 04-sans-reglette c3b.runs.0.effectiveFps) fps"
sleep 2
verbe ${VG}; sleep 0.5; verbe ${VR}                       # rallumée
attendre "05-avec-reglette" $((DUREE + 30)) || { echo "✗ 05-avec-reglette.json absent"; exit 3; }
echo "  ✓ avec réglette  $(lire 05-avec-reglette c3b.runs.1.effectiveFps) fps"

# ── 10. Journal de 60 s, en mode compteur ────────────────────────────────────
echo
echo "── Journal de ${DUREE} s ──"
verbe ${V3}; sleep 0.5; verbe ${VR}
attendre "06-compteur" $((DUREE + 40)) || { echo "✗ 06-compteur.json absent"; exit 3; }
verbe ${VD}

# ── 11 à 13. Fin de plan, puis validation ────────────────────────────────────
verbe ${VX}
attendre "fin" 15 || echo "  ⚠ fin.json absent"

echo
echo "── Ce qui a été déposé ──"
ls -1 "${DEPOT}"/*.json 2>/dev/null | while read -r f; do
    printf "  %-28s %8s octets\n" "$(basename "$f")" "$(wc -c < "$f" | tr -d ' ')"
done

# ── 12. Dire ce qui a été jeté — sans condition ──────────────────────────────
echo
python3 - "${DEPOT}" <<'PY'
import glob, json, os, sys
d = sys.argv[1]
cands = sorted(glob.glob(os.path.join(d, "*.json")))
best, bn = None, None
for f in cands:
    try: o = json.load(open(f))
    except Exception: continue
    j = o.get("journal") or {}
    if j.get("entrees", 0) > (best or {}).get("entrees", -1): best, bn = j, os.path.basename(f)
if not best:
    print("✗ aucun journal déposé"); sys.exit(1)
alerte = best["jetees"] > 0 or best["decimation"] > 1 or best["motifTroncature"]
p = "⚠ " if alerte else "  "
print(f"{p}journal   ecrites={best['ecrites']}  jetees={best['jetees']}  capacite={best['capacite']}   ({bn})")
print(f"{p}          entrees={best['entrees']}  continu={'oui' if best['continu'] else 'NON'}"
      f"  decimation={best['decimation']}  jeteesDepot={best['jeteesDepot']}"
      f"  motif={best['motifTroncature'] or '—'}")
if best["entrees"]:
    t = best["t"]; couv = (t[-1] - t[0]) / 1000
    print(f"{p}          frames {best['premiereFrame']}..{best['derniereFrame']}"
          f"   couverture {couv:.2f} s   {best['entrees']/max(couv,1e-9):.1f} fps")
PY

# ── 14. Résumé ───────────────────────────────────────────────────────────────
echo
echo "── Résumé ──"
echo "  run           ${RUN}"
echo "  dépôt         ${DEPOT}"
echo "  refreshHz     $(lire fin c3b.refreshHz)"
echo "  glLoadLocked  $(lire fin c3b.glLoadLocked)"
echo "  relevés       $(python3 -c "
import json,sys
d=json.load(open('${DEPOT}/fin.json'))
for r in d['c3b']['runs']: print(f\"                {r['label']:24} {r['effectiveFps']:7.2f} fps  charge {r['glLoad']}\")
" 2>/dev/null || echo "(aucun)")"
echo
echo "S29 pose l'instrument. Le verdict C11 se rend en S39, sur la chaîne continue."
