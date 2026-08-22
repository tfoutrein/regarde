#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# S41 — les quatre budgets, mesurés et non espérés
#
# Le critère du lot 3 en donne quatre, et chacun a une raison d'être :
#
#   RSS    < 200 MiB          l'anneau de 4 frames à pleine résolution pèse
#                             ~120 MiB à lui seul. À DEUX écrans il double, et
#                             c'est là que le budget se joue — mesurer sur un seul
#                             écran donnerait un chiffre rassurant et faux.
#   CPU    < 3 %              l'outil ne doit pas fausser le test de performance
#                             qu'on fait avec lui (R8).
#   disque < 500 MiB / 10 min 6,2 Mb/s en HEVC, soit 46,7 MiB/min.
#   final  < 3 s              entre ⌃⌥F et le dossier publié. Au-delà, le calcul
#                             du § 6.6 est déjà perdu.
#
# CE QUE CE SCRIPT NE FAIT PAS : conclure à votre place sur C3b. La cadence se
# mesure dans le témoin, avec `lot3-temoin.sh`, et le verdict demande six relevés
# dans les deux ordres. Ici on mesure ce qui se lit de l'EXTÉRIEUR du processus.
#
# ⚠ Écrit, jamais exécuté : il faut deux écrans, l'autorisation d'enregistrement
#   et dix minutes de session réelle.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

DUREE=600
COURT=0
INTERVALLE=5
SORTIE="${HOME}/Regarde-lot0/budgets"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --duree)  DUREE="$2"; shift 2 ;;
        --court)  DUREE=60; COURT=1; shift ;;
        --sortie) SORTIE="$2"; shift 2 ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        *) echo "✗ option inconnue : $1"; exit 2 ;;
    esac
done

mkdir -p "${SORTIE}"; chmod 700 "${SORTIE}"
RUN="budgets-$(date +%Y%m%d-%H%M%S)"
RELEVE="${SORTIE}/${RUN}.tsv"

PID="$(pgrep -x Regarde | head -1 || true)"
[[ -n "${PID}" ]] || { echo "✗ Regarde ne tourne pas"; exit 2; }

# Deux écrans, sinon le RSS mesuré ne veut rien dire : l'anneau est par flux.
ECRANS=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c "Resolution:" || echo 0)
if [[ "${ECRANS}" -lt 2 && "${COURT}" -eq 0 ]]; then
    echo "✗ ${ECRANS} écran(s) détecté(s) — il en faut DEUX."
    echo "  L'anneau de frames est par flux : sur un seul écran, le RSS mesuré serait"
    echo "  rassurant et faux. Utilise --court pour un essai de mise au point."
    exit 5
fi

echo "── S41 · budgets · ${DUREE} s · pid ${PID} · ${ECRANS} écran(s) ──"
echo
echo "  Ouvre une session (⌃⌥S) avec quelque chose qui BOUGE, laisse tourner,"
echo "  pose quelques marques, puis ⌃⌥F. Le relevé s'arrête tout seul."
echo
read -r -p "  Entrée pour démarrer le relevé… " _

TMP="${TMPDIR:-/tmp}"
printf "t\trss_kio\tpcpu\tdisque_octets\n" > "${RELEVE}"
DEBUT=$(date +%s)
while :; do
    MAINTENANT=$(date +%s); T=$((MAINTENANT - DEBUT))
    [[ "${T}" -ge "${DUREE}" ]] && break
    pgrep -x Regarde >/dev/null || { echo "  ⚠ Regarde s'est arrêté à t=${T}s"; break; }
    LIGNE=$(ps -o rss=,pcpu= -p "${PID}" 2>/dev/null | tr -s ' ' | sed 's/^ //')
    RSS=$(echo "${LIGNE}" | cut -d' ' -f1); CPU=$(echo "${LIGNE}" | cut -d' ' -f2)
    OCTETS=$(find "${TMP}" -path "*regarde*" -name "*.mov" -exec stat -f%z {} \; 2>/dev/null \
             | awk '{s+=$1} END {print s+0}')
    printf "%s\t%s\t%s\t%s\n" "${T}" "${RSS:-0}" "${CPU:-0}" "${OCTETS:-0}" >> "${RELEVE}"
    printf "\r  t=%4ss  RSS %6s MiB  CPU %5s %%  disque %6s MiB" \
           "${T}" "$(( ${RSS:-0} / 1024 ))" "${CPU:-0}" "$(( ${OCTETS:-0} / 1048576 ))"
    sleep "${INTERVALLE}"
done
echo; echo

python3 - "${RELEVE}" "${DUREE}" <<'PY'
import sys, statistics
lignes = [l.split("\t") for l in open(sys.argv[1]).read().splitlines()[1:] if l.strip()]
if not lignes:
    print("✗ aucun relevé"); sys.exit(3)
duree = int(sys.argv[2])
rss = [int(l[1]) / 1024 for l in lignes]
cpu = [float(l[2]) for l in lignes]
disque = [int(l[3]) / 1048576 for l in lignes]

print("── Les quatre budgets ──")
def verdict(nom, valeur, seuil, unite, note=""):
    ok = valeur <= seuil
    print(f"  {'✓' if ok else '✗'} {nom:28} {valeur:8.1f} {unite:6} contre {seuil} {unite}  {note}")
    return ok

ok = True
ok &= verdict("RSS crête", max(rss), 200, "MiB", "l'anneau pèse ~120 MiB par flux")
ok &= verdict("CPU moyen", statistics.mean(cpu), 3, "%", "R8 — ne pas fausser le test")
# Le disque est extrapolé à 10 min quand le relevé est plus court.
extrapole = max(disque) * (600 / duree) if duree < 600 else max(disque)
ok &= verdict("disque / 10 min", extrapole, 500, "MiB",
              "" if duree >= 600 else f"extrapolé depuis {duree} s")
print()
print("  Le quatrième — traitement final < 3 s — se lit dans le bloc EXTRACTION")
print("  du journal, ligne « durée ». Il ne se mesure pas de l'extérieur.")
print()
if max(cpu) > 10:
    print(f"  ⚠ pointe CPU à {max(cpu):.1f} % — regarder si elle tombe sur une publication")
sys.exit(0 if ok else 5)
PY
echo "  relevé : ${RELEVE}"
