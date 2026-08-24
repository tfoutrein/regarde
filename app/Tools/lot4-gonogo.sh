#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# S55 — les quatre nombres du GO/NO-GO n°2, face à leurs seuils
#
# Les seuils sont ceux de docs/lot4-seuils.md, écrits en S46 AVANT la première
# mesure. Ce script ne fait qu'imprimer les nombres en face — et REFUSER de
# conclure quand la mesure ne peut pas encore porter :
#
#   · moins de dix jours de relevé            — la fenêtre du § 3.2
#   · moins de vingt tentatives d'injection   — le dernier mètre pas exercé
#   · aucun repli jamais noté                 — zéro mesure l'oubli de
#                                               déclarer, pas la perfection
#
# Usage : lot4-gonogo.sh [--metrics <fichier>]     (défaut : le vrai)
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

METRICS="${HOME}/Library/Application Support/Regarde/metrics.jsonl"
[[ "${1:-}" == "--metrics" ]] && METRICS="$2"

[[ -f "${METRICS}" ]] || { echo "✗ aucun relevé : ${METRICS}"; exit 2; }

python3 - "${METRICS}" <<'PY'
import json, sys, datetime

lignes = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
if not lignes:
    print("✗ relevé vide"); sys.exit(2)

def date(e): return datetime.datetime.fromisoformat(e["at"].replace("Z", "+00:00"))
maintenant = datetime.datetime.now(datetime.timezone.utc)

# Jours OUVRÉS couverts par le relevé — du premier événement à maintenant.
premier = min(date(e) for e in lignes)
ouvres = sum(1 for i in range((maintenant.date() - premier.date()).days + 1)
             if (premier.date() + datetime.timedelta(days=i)).weekday() < 5)

sessions = [e for e in lignes if e.get("event") == "session" and e.get("spontanee")]
replis = [e for e in lignes if e.get("event") == "repli"]
verdicts = [e for e in lignes if e.get("event") == "verdict"]
injections = [e for e in lignes if e.get("event") == "injection"]

print(f"── GO/NO-GO n°2 · relevé de {ouvres} jour(s) ouvré(s), "
      f"{len(lignes)} événement(s) ──\n")

refus = []
if ouvres < 10:
    refus.append(f"{ouvres} jour(s) ouvré(s) de relevé — il en faut dix")
if len(injections) < 20:
    refus.append(f"{len(injections)} tentative(s) d'injection — il en faut vingt : "
                 "le dernier mètre n'est pas assez exercé pour être jugé")
if not replis:
    refus.append("aucun repli jamais noté — zéro mesure l'oubli de déclarer, "
                 "pas la perfection de l'outil")

# Les quatre nombres, TOUJOURS imprimés — même quand la conclusion se refuse :
# voir où l'on en est fait partie de tenir dix jours sans impression.
def ligne(nom, valeur, comparateur, seuil, unite=""):
    ok = comparateur(valeur, seuil)
    print(f"  {'✓' if ok else '✗'} {nom:26} {valeur:>8} {unite:12} seuil : {seuil} {unite}")
    return ok

ok = True
ok &= ligne("sessions spontanées", len(sessions), lambda v, s: v >= s, 5, "/ 10 j ouvrés")
taux = round(100 * len(replis) / max(1, len(sessions) + len(replis)))
ok &= ligne("taux de repli", taux, lambda v, s: v <= s, 50, "%")
dix = verdicts[-10:]
pertinents = sum(1 for v in dix if v.get("verdict") == "pertinent")
if len(dix) < 10:
    refus.append(f"{len(dix)} verdict(s) de diff persisté(s) — il en faut dix pour juger « 7 sur 10 »")
ok &= ligne("diffs pertinents", pertinents, lambda v, s: v >= s, 7, f"/ {len(dix)} verdicts")
fins = sorted(e.get("finSecondes", 0) for e in lignes
              if e.get("event") == "session" and "finSecondes" in e)
p95 = round(fins[int(len(fins) * 0.95) - 1] if fins else 0, 1)
ok &= ligne("fin de session p95", p95, lambda v, s: v <= s, 20, "s")

print()
if refus:
    print("── LE SCRIPT REFUSE DE CONCLURE ──")
    for r in refus: print(f"  ✗ {r}")
    sys.exit(5)
print("── conclusion : " + ("GO" if ok else "NO-GO — un seuil au moins est crevé") + " ──")
sys.exit(0 if ok else 1)
PY
