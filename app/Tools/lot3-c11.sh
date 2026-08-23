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
        --depouiller) DEPOUILLER="$2"; shift 2 ;;
        -h|--help)  sed -n '2,31p' "$0"; exit 0 ;;
        *) echo "✗ option inconnue : $1"; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOT0="$(cd "${ROOT}/../prototypes/lot0" && pwd)"
BIN="${ROOT}/.build/debug/Regarde"
# `--depouiller <dossier-de-run>` rejoue le dépouillement — monotonie et verdict —
# sur les artefacts d'une campagne déjà faite, sans témoin, sans session, sans
# clic. Né le 23 août : la session 19:19 avait tout produit et le banc s'était
# abstenu sur un défaut d'appariement du script lui-même ; corriger le script
# sans pouvoir rejouer ses données aurait exigé une campagne de plus par
# correction.
if [[ -n "${DEPOUILLER:-}" ]]; then
    DEPOT="$(cd "${DEPOUILLER}" && pwd)"
    RUN="$(basename "${DEPOT}")"
    SORTIE="$(dirname "${DEPOT}")"
    for f in lectures.txt c11.json; do
        [[ -f "${DEPOT}/${f}" ]] || { echo "✗ ${DEPOT}/${f} absent — pas un dossier de run"; exit 2; }
    done
    echo "── Banc C11 · dépouillement seul · ${RUN} ──"
else
    RUN="c11-$(date +%Y%m%d-%H%M%S)-$$"
    DEPOT="${SORTIE}/${RUN}"
    mkdir -p "${DEPOT}" && chmod 700 "${DEPOT}"

    echo "── Banc C11 · ${RUN} ──"
    echo "  dépôt   ${DEPOT}"
    echo "  marques ${MARQUES} · ponts ${PONTS}"
fi

if [[ -z "${DEPOUILLER:-}" ]]; then

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
# Les onglets témoin RÉSIDUELS sont fermés d'abord. Un onglet d'une campagne
# précédente — ou un /index.html nu ouvert à la main — ressemble trait pour
# trait au bon : le 23 août, un ⌃⌥D est parti vers l'un d'eux et le relevé du
# vrai onglet n'est jamais arrivé.
# Le port du banc est interpolé ; 8765 est celui de `serve-temoin.sh`, la voie
# manuelle — c'est un de ses onglets résiduels qui a reçu le ⌃⌥D du 23 août.
osascript >/dev/null 2>&1 \
    -e 'tell application "Google Chrome"' \
    -e '  repeat with w in windows' \
    -e "    close (tabs of w whose URL contains \"127.0.0.1:${PORT}\")" \
    -e '    close (tabs of w whose URL contains "127.0.0.1:8765")' \
    -e '  end repeat' \
    -e 'end tell' || true
open -a "Google Chrome" \
     "http://127.0.0.1:${PORT}/index.html?run=${RUN}&plan=c11&mode=compteur&duree=900&hud=0&auto=armer&depot=run"
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
echo "  Puis clique ${PONTS} fois au centre de l'écran, sans modificateur —"
echo "  les clics doivent atterrir SUR LA PAGE, pas sur un terminal, et à des"
echo "  intervalles IRRÉGULIERS : c'est leur rythme qui permet de les apparier."
echo "  Enfin trace ${MARQUES} marques en ⌥⌘-glisser, et ferme par ⌃⌥F."
echo
read -r -p "  Appuie sur Entrée quand la session est publiée… " _

# ── 4 bis. Faire déposer la page, APRÈS coup ─────────────────────────────────
#
# C'est l'ordre qui compte, et il était faux. La page était ouverte avec
# `duree=30` : son plan s'achevait et elle déposait trente secondes après
# l'armement — donc avant même que Regarde soit lancé. Les clics du pont, tracés
# ensuite, n'étaient dans aucun dépôt, et le banc s'abstenait pour « 0 clic vu
# par la page » alors que la page les avait bien vus.
#
# Le plan dure maintenant quinze minutes, et c'est ICI qu'on demande le dépôt,
# une fois le travail fait. ⌃⌥D est le verbe de dépôt du témoin ; ⌃⌥S, F, M et L
# sont interdits, Regarde les capte en raccourcis globaux.
echo
echo "── Dépôt du relevé de la page ──"
# Et on VÉRIFIE, au lieu de le découvrir au verdict. Les deux premiers essais
# renvoient ⌃⌥D eux-mêmes — l'activation de Chrome prend parfois plus d'une
# seconde en plein écran, et les deux premières campagnes ont chacune coûté un
# aller-retour humain pour un simple raccourci à renvoyer. Le dépôt peut manquer pour
# trois raisons — Chrome pas au premier plan, plan déjà clos, page rechargée — et
# les trois se rattrapent en dix secondes si on les nomme tout de suite.
for essai in 1 2 3; do
    # Le serveur d'abord : s'il est mort — durée de vie atteinte, machine en
    # veille — la page peut bien déposer, rien n'arrive. Le relancer suffit, la
    # page retient son état et le prochain dépôt passe.
    if ! curl -s --max-time 1 "http://127.0.0.1:${PORT}/sante" >/dev/null 2>&1; then
        echo "  ⚠ le serveur du témoin ne répond plus — relance"
        nohup python3 "${LOT0}/Tools/temoin-serveur.py" --port "${PORT}" \
              --racine "${LOT0}/temoins" --depot "${SORTIE}" --duree-max 3600 \
              >> "${SORTIE}/serveur.log" 2>&1 &
        sleep 1
    fi
    if [[ ${essai} -lt 3 ]]; then
        osascript <<'AS' >/dev/null 2>&1 || true
tell application "Google Chrome" to activate
delay 2
tell application "System Events" to key code 2 using {control down, option down}
AS
        sleep 2
    fi
    ALIGNS="$(python3 - "${SORTIE}/${RUN}" <<'CHK'
import glob, json, os, sys
n = 0
for f in glob.glob(os.path.join(sys.argv[1], "*.json")):
    try: o = json.load(open(f))
    except Exception: continue
    n += len((o.get("c11") or {}).get("clockAligns") or [])
print(n)
CHK
)"
    [[ "${ALIGNS}" -gt 0 ]] && break
    echo "  ⚠ aucun clic dans le dépôt (essai ${essai}/3)."
    if [[ ${essai} -eq 2 ]]; then
        echo "    Passe sur Chrome et fais ⌃⌥D à la main, puis reviens ici."
        read -r -p "    Entrée pour revérifier… " _
    fi
done
if [[ "${ALIGNS}" -gt 0 ]]; then
    echo "  ✓ ${ALIGNS} clic(s) déposé(s) par la page"
else
    echo "  ✗ la page n'a déposé aucun clic — le pont d'horloge ne pourra pas se faire."
    echo "    Les clics doivent être NUS (sans modificateur) et atterrir sur la page"
    echo "    en plein écran, pas sur le terminal."
fi

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

fi  # fin du mode campagne complète

# ── 5 bis. La monotonie des numéros lus ──────────────────────────────────────
#
# Le contrôle qui manquait, et qui a trouvé un défaut que le journal ne pouvait
# pas voir. Les marques sont tracées dans l'ordre du temps ; le compteur du
# témoin ne décroît jamais. Si le numéro lu sur la marque N+1 est inférieur ou
# égal à celui de la marque N, une des deux images vient du mauvais instant.
#
# Mesuré le 23 août 2026 : sur dix marques, la deuxième portait un numéro
# INFÉRIEUR à la première — une image 1,40 s trop tôt, rendue par le repli de
# tolérance qui avait écrasé l'image exacte du premier passage. Le bloc
# EXTRACTION annonçait pourtant « 548 ms » d'âge, et rien d'autre ne clochait.
echo
echo "── Monotonie des numéros ──"
if python3 - "${DEPOT}/lectures.txt" <<'MONO'
import sys
lignes = [l.split() for l in open(sys.argv[1]) if l.strip()]
lus = [(n, int(v)) for n, v in lignes if v.isdigit()]
if len(lus) < 2:
    print("  ⚠ moins de deux réglettes lues — contrôle impossible")
    sys.exit(0)
casses = [(a, b) for (a, va), (b, vb) in zip(lus, lus[1:]) if vb <= va]
for a, b in casses:
    print(f"  ✗ {a} → {b} : le numéro ne croît pas")
if casses:
    print(f"  {len(casses)} rupture(s) — au moins une image vient du mauvais instant.")
    print("  C'est un refus opposable : la chaîne d'extraction se trompe de frame.")
    sys.exit(1)
ecarts = [vb - va for (_, va), (_, vb) in zip(lus, lus[1:])]
print(f"  ✓ {len(lus)} numéros strictement croissants "
      f"(écarts de {min(ecarts)} à {max(ecarts)} images)")
MONO
then MONOTONE=0; else MONOTONE=1; fi

[[ -z "${DEPOUILLER:-}" ]] && cp "${FRAMES}/c11.json" "${DEPOT}/" 2>/dev/null || true

# ── 6. Les quatre refus, et la ligne de base ─────────────────────────────────
echo
MONOTONE="${MONOTONE}" python3 - "${DEPOT}" "${SORTIE}/${RUN}" <<'PY'
import glob, json, os, statistics, sys

depot, depotPage = sys.argv[1], sys.argv[2]
refus = []

# Le rapport du banc, côté Regarde.
try:
    c11 = json.load(open(os.path.join(depot, "c11.json")))
except Exception as e:
    print(f"✗ c11.json illisible : {e}"); sys.exit(3)

# Refus 5 — les numéros lus ne croissent pas.
#
# Ajouté le 23 août 2026, après qu'il eut trouvé ce que rien d'autre ne voyait :
# une image 1,40 s trop tôt sur la deuxième marque de dix, pendant que le bloc
# EXTRACTION annonçait un âge de 548 ms et qu'aucun autre indicateur ne bougeait.
# C'est le seul contrôle qui compare la CHAÎNE à elle-même plutôt qu'à ses
# propres déclarations.
if os.environ.get("MONOTONE", "0") not in ("0", ""):
    refus.append("les numéros lus sur les réglettes ne croissent pas : au moins "
                 "une image vient du mauvais instant. Voir le détail plus haut.")

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

# APPARIEMENT PAR AMAS DE DÉCALAGES — troisième forme, chacune tuée par la mesure.
#
#   Par RANG (jusqu'au 23 août au matin) : la page voit des clics que Regarde ne
#   voit pas, le premier intrus décale tous les suivants. 16 993 ms de dispersion
#   sur un pont sain.
#
#   Par FENÊTRE CONTIGUË (le même jour) : suppose que les clics communs forment un
#   bloc d'un seul tenant. Cassée le soir même : un clic vu par Regarde seul en
#   fin de session, un clic vu par la page seule, et la meilleure fenêtre mariait
#   l'un à l'autre — 9,6 s de dispersion sur un pont sain, avec un message qui
#   accusait la régularité des clics de l'utilisateur.
#
#   Par AMAS : le vrai appariement partage un MÊME décalage. On calcule tous les
#   A_i − P_j et l'amas le plus peuplé dans une fenêtre de 100 ms EST
#   l'appariement — aucune hypothèse de contiguïté, les intrus des deux côtés
#   restent simplement sans vis-à-vis. Éprouvé sur les deux dépôts réels du
#   23 août : 5 paires sur 13 clics de page, puis 9 sur 12.
#
# L'ESTIMATEUR est le PLANCHER de l'amas, pas sa médiane. Côté Regarde,
# l'horodatage est matériel — il date le clic. Côté page, performance.now() est
# lu dans le gestionnaire, APRÈS l'ordonnancement du fil principal : le retard
# est strictement positif et variable — 48 ms d'étendue mesurée sur une session
# de 19 s en pleine charge. Le décalage vrai s'approche donc par le bas, et la
# qualité du pont se juge sur les clics proches du plancher : il en faut au
# moins DEUX à moins de dispersionMaxMs l'un de l'autre.
decalages = []
if ponts and aligns:
    P = [q["t"] for q in ponts]
    A = [a["pageNow"] / 1000.0 for a in aligns]
    paires = sorted((A[i] - P[j], i, j) for i in range(len(A)) for j in range(len(P)))
    def amas(candidats):
        meilleur = []
        for k in range(len(candidats)):
            vus_i, vus_j, retenu = set(), set(), []
            for o, i, j in candidats[k:]:
                if o - candidats[k][0] >= 0.100: break
                if i in vus_i or j in vus_j: continue
                vus_i.add(i); vus_j.add(j); retenu.append((o, i, j))
            if len(retenu) > len(meilleur): meilleur = retenu
        return meilleur
    premier = amas(paires)
    if len(premier) >= 2:
        # Le rival se cherche AILLEURS SUR L'AXE DES DÉCALAGES, sans écarter les
        # clics du premier amas : des clics au métronome forment des amas de même
        # taille à chaque multiple de l'intervalle, avec les MÊMES clics. Retirer
        # les paires du premier amas les faisait disparaître, et l'ambiguïté avec.
        lo = premier[0][0] - 0.2
        hi = premier[-1][0] + 0.2
        second = amas([c for c in paires if c[0] < lo or c[0] > hi])
        if len(second) >= len(premier):
            refus.append(f"appariement du pont ambigu : deux amas de {len(premier)} paires "
                         "à des décalages différents — clique IRRÉGULIÈREMENT, c'est le "
                         "motif des intervalles qui départage")
        else:
            offs = sorted(o for o, _, _ in premier)
            plancher = offs[0]
            retenus = [o for o in offs if (o - plancher) * 1000 <= c11["dispersionMaxMs"]]
            sans_a = len(A) - len(premier)
            sans_p = len(P) - len(premier)
            print(f"  pont       {len(premier)} clics appariés — {len(A)} vus par la page, "
                  f"{len(P)} par Regarde ({sans_a} et {sans_p} sans vis-à-vis)")
            print(f"             décalage {plancher*1000:.2f} ms au plancher · "
                  f"{len(retenus)} clic(s) à moins de {c11['dispersionMaxMs']} ms du plancher · "
                  f"étendue de l'amas {(offs[-1]-plancher)*1000:.2f} ms")
            if len(retenus) < 2:
                refus.append(f"un seul clic au plancher du pont ({c11['dispersionMaxMs']} ms) : "
                             "le décalage ne peut pas être confirmé — refais les clics du pont "
                             "dans un moment calme, juste après l'ouverture de session")
            else:
                decalages = retenus
if not decalages and not refus:
    refus.append(f"pont d'horloge insuffisant : {len(ponts)} clic(s) vus par Regarde, "
                 f"{len(aligns)} par la page — il en faut au moins deux appariés")

# Refus 3 — une marque antérieure à la première entrée conservée du journal.
premiere = None
for f in pages:
    try: o = json.load(open(f))
    except Exception: continue
    j = o.get("journal") or {}
    if j.get("t"): premiere = min(premiere or 1e18, j["t"][0] / 1000.0)
releves = c11.get("releves", [])
if premiere is not None and decalages:
    # Le plancher : voir l'estimateur ci-dessus — la médiane inclurait le retard
    # de livraison de la page, strictement positif.
    med = min(decalages)
    trop_tot = [r for r in releves if r["t"] + med < premiere]
    if trop_tot:
        refus.append(f"{len(trop_tot)} marque(s) antérieures à la première entrée "
                     "conservée du journal de page — l'anneau avait déjà bouclé, "
                     "leur numéro de frame n'est plus dans le fichier")

# ── Ligne de base ────────────────────────────────────────────────────────────
print()
print("── Ligne de base — chaîne PONCTUELLE du lot 2 ──")
print("  Cette latence mesure le FILET RAM, qui capture au relâchement. Depuis le")
print("  lot 3 il n'est plus le chemin normal : l'image publiée vient du FICHIER, à")
print("  l'instant du mouseDown. Un dépassement ici ne dit rien de C11 — c'est la")
print("  monotonie des réglettes, plus haut, qui juge la chaîne continue.")
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
