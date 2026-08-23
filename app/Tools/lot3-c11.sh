#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Banc C11 — S31
#
# CE BANC NE REND PAS DE VERDICT C11, ET C'EST DÉLIBÉRÉ.
#
# La chaîne du lot 2 capture par `SCScreenshotManager` dans une tâche détachée au
# relâchement. Le lot 0 lui a mesuré 49,1 ms de médiane et 120,9 ms au pire
# (prototypes/lot0/RESULTATS.md) : elle est structurellement hors de la tolérance
# visée. Lui faire rendre un PASS serait mentir ; lui faire rendre un FAIL serait
# accuser la mauvaise chose — ce n'est pas l'appariement qui échoue, c'est le
# chemin qui n'a jamais prétendu être celui-là.
#
# Ce que ce banc établit :
#
#   le SEUIL, écrit avant toute mesure    en unités de compteur, dans
#                                         Bench/C11Bench.swift, et repris tel quel
#                                         en S39. Un seuil écrit après coup est un
#                                         seuil ajusté au résultat.
#   la LIGNE DE BASE                      latence propre du chemin ponctuel, et
#                                         écart en frames de compteur.
#   QUATRE REFUS opposables               un banc qui ne sait pas s'abstenir
#                                         n'établit rien.
#
# Le verdict tombe en S39, sur la chaîne continue, qui est la seule à pouvoir le
# soutenir.
#
# ⚠ ÉTAT : écrit, jamais exécuté en entier. Chacune de ses briques est vérifiée
#   séparément — le décodeur par `--reglette-test` (40 vérifications), le témoin
#   par `lot3-temoin.sh`, le dépôt par le serveur. L'enchaînement, lui, demande la
#   machine : Chrome en plein écran, l'Accessibilité, et Regarde lancé.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PORT=8799
MARQUES=8
PONTS=5
SORTIE="${HOME}/Regarde-lot0/c11"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)     PORT="$2"; shift 2 ;;
        --marques)  MARQUES="$2"; shift 2 ;;
        --ponts)    PONTS="$2"; shift 2 ;;
        --sortie)   SORTIE="$2"; shift 2 ;;
        -h|--help)  sed -n '2,31p' "$0"; exit 0 ;;
        *) echo "✗ option inconnue : $1"; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOT0="$(cd "${ROOT}/../prototypes/lot0" && pwd)"
BIN="${ROOT}/.build/debug/Regarde"
RUN="c11-$(date +%Y%m%d-%H%M%S)-$$"
DEPOT="${SORTIE}/${RUN}"
mkdir -p "${DEPOT}" && chmod 700 "${DEPOT}"

echo "── Banc C11 · ${RUN} ──"
echo "  dépôt   ${DEPOT}"
echo "  marques ${MARQUES} · ponts ${PONTS}"

# ── 0. Le seuil, AVANT toute mesure ──────────────────────────────────────────
# Il est imprimé et consigné ici, avant qu'une seule image existe. C'est la seule
# façon d'établir qu'il n'a pas été ajusté au résultat.
echo
echo "── Le seuil, écrit avant la première mesure ──"
python3 - "${DEPOT}/seuil.txt" <<'PY'
import sys
seuil = """Le numéro gravé dans l'image doit tomber dans l'intervalle des numéros rendus par
la page entre la frame encodée précédant le mouseDown et la suivante.

Il est en UNITÉS DE COMPTEUR, pas en millisecondes. Le § 4.5 du plan fixait 16 ms —
une frame à 60 fps — mais ce chiffre a été écrit pour un captureImage ponctuel. Le
flux continu du lot 3 tourne à 15 fps, soit 66,7 ms entre deux frames encodées :
aucune extraction ne peut être plus fine que cet intervalle, et un seuil de 16 ms
rendrait C11 infaisable par construction plutôt que difficile.

Sur la chaîne PONCTUELLE du lot 2, il n'y a pas de frame encodée. Le banc publie
l'écart en frames de compteur comme LIGNE DE BASE et ne rend AUCUN verdict.
"""
open(sys.argv[1], "w").write(seuil)
print(seuil)
PY

# ── 1. Préalables ────────────────────────────────────────────────────────────
[[ -x "${BIN}" ]] || { echo "✗ binaire absent : ${BIN} — lance d'abord swift build"; exit 2; }
command -v python3 >/dev/null || { echo "✗ python3 introuvable"; exit 2; }
[[ -d "/Applications/Google Chrome.app" ]] || { echo "✗ Chrome introuvable"; exit 2; }

# ── 2. Refus n°4, contrôlé AVANT de commencer ────────────────────────────────
# `--visible-capture` fait apparaître le calque dans les captures. Une image qui
# porte l'encre de la marque par-dessus la réglette n'est plus une mesure.
if pgrep -fl "Regarde" 2>/dev/null | grep -q -- "--visible-capture"; then
    echo "✗ REFUS — Regarde tourne avec --visible-capture : le calque apparaîtrait"
    echo "  dans les images, et la réglette serait mesurée sous l'encre."
    exit 5
fi

# ── 3. Témoin ────────────────────────────────────────────────────────────────
echo
echo "── Témoin ──"
SIG="$(curl -s --max-time 1 "http://127.0.0.1:${PORT}/sante" 2>/dev/null || true)"
if [[ "${SIG}" != *'regarde-temoin'* ]]; then
    nohup python3 "${LOT0}/Tools/temoin-serveur.py" --port "${PORT}" \
          --racine "${LOT0}/temoins" --depot "${SORTIE}" --duree-max 3600 \
          > "${SORTIE}/serveur.log" 2>&1 &
    for _ in $(seq 1 50); do
        curl -s --max-time 1 "http://127.0.0.1:${PORT}/sante" >/dev/null 2>&1 && break
        sleep 0.1
    done
fi
open -a "Google Chrome" \
     "http://127.0.0.1:${PORT}/index.html?run=${RUN}&plan=c11&mode=compteur&duree=30&hud=0&auto=armer&depot=run"
sleep 3
osascript -e 'tell application "Google Chrome" to activate' >/dev/null
osascript <<'AS' >/dev/null 2>&1 || echo "  ⚠ menu Présentation inatteignable — plein écran à la main"
tell application "System Events" to tell process "Google Chrome"
    click menu item "Activer le mode plein écran" of menu 1 of menu bar item "Présentation" of menu bar 1
end tell
AS
sleep 2

# ── 4. Le pont d'horloge ─────────────────────────────────────────────────────
# Un clic NU, horodaté aux deux bouts : la page l'enregistre dans `clockAligns`
# (un clic dans la scène appelle `alignClock`), et le tap de Regarde en note
# l'horodatage matériel sur son chemin de passe-plat. Plusieurs clics donnent
# plusieurs estimations du MÊME décalage, et c'est leur dispersion qui dit si le
# pont vaut quelque chose.
echo
echo "── Pont d'horloge — ${PONTS} clics nus ──"
echo "  Lance Regarde avec --c11-bench et ouvre une session (⌃⌥S) AVANT de continuer."
echo "  Puis clique ${PONTS} fois au centre de l'écran, sans modificateur."
echo "  Enfin trace ${MARQUES} marques en ⌥⌘-glisser, et ferme par ⌃⌥F."
echo
read -r -p "  Appuie sur Entrée quand la session est publiée… " _

# ── 5. Dépouillement ─────────────────────────────────────────────────────────
DERNIERE="$(ls -1dt "${HOME}/Regarde/sessions"/*/ 2>/dev/null | head -1)"
[[ -n "${DERNIERE}" ]] || { echo "✗ aucune session publiée"; exit 3; }
FRAMES="${DERNIERE}frames"
[[ -f "${FRAMES}/c11.json" ]] || {
    echo "✗ ${FRAMES}/c11.json absent — Regarde tournait-il avec --c11-bench ?"; exit 3; }

echo
echo "── Lecture des réglettes ──"
: > "${DEPOT}/lectures.txt"
# Les images ENTIÈRES, pas les recadrages. La réglette fait 2176 px de large,
# dessinée une fois, centrée en bas de l'écran ; les recadrages font 560 à 1120 px
# et aucun ne peut la contenir. Lire `marque-*.png` refusait donc toujours —
# « image trop petite » — et le refus ressemblait à un problème de cadrage.
shopt -s nullglob
PLEINS=("${FRAMES}"/plein-*.png)
if [[ ${#PLEINS[@]} -eq 0 ]]; then
    echo "✗ aucune image entière (plein-*.png) dans ${FRAMES}"
    echo "  Elles ne sont écrites qu'avec --c11-bench : Regarde tournait-il en mode banc ?"
    exit 3
fi
for png in "${PLEINS[@]}"; do
    [[ -e "${png}" ]] || continue
    printf "  %-16s " "$(basename "${png}")"
    if SORTIE_LECTURE="$("${BIN}" --lire-reglette "${png}" 2>&1)"; then
        V="$(echo "${SORTIE_LECTURE}" | awk '/^V /{print $2}')"
        echo "V=${V}"
        echo "$(basename "${png}") ${V}" >> "${DEPOT}/lectures.txt"
    else
        echo "${SORTIE_LECTURE}" | tr '\n' ' '; echo
        echo "$(basename "${png}") refus" >> "${DEPOT}/lectures.txt"
    fi
done

cp "${FRAMES}/c11.json" "${DEPOT}/" 2>/dev/null || true

# ── 6. Les quatre refus, et la ligne de base ─────────────────────────────────
echo
python3 - "${DEPOT}" "${SORTIE}/${RUN}" <<'PY'
import glob, json, os, statistics, sys

depot, depotPage = sys.argv[1], sys.argv[2]
refus = []

# Le rapport du banc, côté Regarde.
try:
    c11 = json.load(open(os.path.join(depot, "c11.json")))
except Exception as e:
    print(f"✗ c11.json illisible : {e}"); sys.exit(3)

# Refus 4 — la capture visible.
if c11.get("captureVisible"):
    refus.append("--visible-capture était actif : le calque apparaît dans les images")

# Refus 2 — fallbackCount a bougé.
d0, d1 = c11["fallbackCountDebut"], c11["fallbackCountFin"]
if d1 != d0:
    refus.append(f"fallbackCount a bougé pendant la mesure : {d0} → {d1}. "
                 "Des horodatages matériels ont été rejetés — pilote tiers ou "
                 "événement synthétique (C12). Les marques concernées sont datées "
                 "d'un repli, pas du geste.")

# Refus 1 — la dispersion du pont.
ponts = c11.get("ponts", [])
pages = sorted(glob.glob(os.path.join(depotPage, "*.json")))
aligns = []
for f in pages:
    try: o = json.load(open(f))
    except Exception: continue
    aligns += (o.get("c11") or {}).get("clockAligns", []) or []

decalages = []
if ponts and aligns:
    n = min(len(ponts), len(aligns))
    # Appariés dans l'ordre : les clics sont séquentiels des deux côtés.
    for i in range(n):
        decalages.append(aligns[i]["pageNow"] / 1000.0 - ponts[i]["t"])
if len(decalages) < 2:
    refus.append(f"pont d'horloge insuffisant : {len(ponts)} clic(s) vus par Regarde, "
                 f"{len(aligns)} par la page — il en faut au moins deux appariés")
else:
    dispersion = (max(decalages) - min(decalages)) * 1000
    print(f"  pont       {len(decalages)} clics · décalage médian "
          f"{statistics.median(decalages)*1000:8.2f} ms · dispersion {dispersion:.2f} ms")
    if dispersion > c11["dispersionMaxMs"]:
        refus.append(f"dispersion du pont {dispersion:.1f} ms > {c11['dispersionMaxMs']} ms — "
                     "un pont plus flou que la grandeur mesurée ne mesure rien")

# Refus 3 — une marque antérieure à la première entrée conservée du journal.
premiere = None
for f in pages:
    try: o = json.load(open(f))
    except Exception: continue
    j = o.get("journal") or {}
    if j.get("t"): premiere = min(premiere or 1e18, j["t"][0] / 1000.0)
releves = c11.get("releves", [])
if premiere is not None and decalages:
    med = statistics.median(decalages)
    trop_tot = [r for r in releves if r["t"] + med < premiere]
    if trop_tot:
        refus.append(f"{len(trop_tot)} marque(s) antérieures à la première entrée "
                     "conservée du journal de page — l'anneau avait déjà bouclé, "
                     "leur numéro de frame n'est plus dans le fichier")

# ── Ligne de base ────────────────────────────────────────────────────────────
print()
print("── Ligne de base — chaîne PONCTUELLE du lot 2 ──")
if releves:
    lat = sorted((r["arrivee"] - r["t"]) * 1000 for r in releves)
    med = lat[len(lat)//2]
    print(f"  latence mouseDown → image   médiane {med:6.1f} ms · "
          f"min {lat[0]:.1f} · max {lat[-1]:.1f} ms   ({len(lat)} marques)")
    attendu = 40 <= med <= 130
    print(f"  plage attendue au lot 0     40 à 130 ms — {'✓ conforme' if attendu else '⚠ HORS PLAGE'}")
else:
    print("  aucun relevé")

lectures = {}
p = os.path.join(depot, "lectures.txt")
if os.path.exists(p):
    for ligne in open(p):
        nom, val = ligne.split()[0], ligne.split()[1]
        lectures[nom] = val
lues = [v for v in lectures.values() if v != "refus"]
print(f"  réglettes lues              {len(lues)}/{len(lectures)}"
      + ("" if len(lues) == len(lectures) else "  ⚠ des refus, voir lectures.txt"))

# ── Verdict : il n'y en a pas, et c'est écrit ───────────────────────────────
print()
if refus:
    print("── LE BANC S'ABSTIENT ──")
    for r in refus: print(f"  ✗ {r}")
    sys.exit(5)
print("── Aucun refus opposable ──")
print("  Le banc ne rend PAS de verdict C11 : la chaîne ponctuelle du lot 2 est")
print("  structurellement hors tolérance (40 à 130 ms mesurés au lot 0). Ce qui")
print("  précède est une LIGNE DE BASE. Le verdict tombe en S39, sur la chaîne")
print("  continue, avec le seuil écrit dans seuil.txt AVANT cette mesure.")
PY
echo
echo "  dépôt : ${DEPOT}"
