#!/usr/bin/env python3
# ─────────────────────────────────────────────────────────────────────────────
# Serveur du témoin — S29, lot 3
#
# Il existe pour une seule raison : permettre au témoin de DÉPOSER son état sur
# le disque sans passer par `osascript … execute javascript`.
#
# La dette C3b du lot 0 tenait entièrement là. Le seul moyen de lire le JSON du
# témoin depuis un script était d'activer « Autoriser JavaScript depuis les
# Apple Events » dans Chrome — une permission qui donne l'exécution de
# JavaScript dans TOUS les onglets, y compris ceux où l'on est authentifié. La
# refuser était juste ; il fallait alors une autre voie. C'est celle-ci : la
# page POSTe elle-même, et le pilotage se fait aux frappes clavier via System
# Events, qui n'exige que l'Accessibilité.
#
# Ce serveur écrit sur disque ce qu'une page lui envoie. C'est une surface
# d'attaque, et elle est traitée comme telle : quatre routes, un vocabulaire de
# noms fermé, une liste blanche de clés, aucune exécution nulle part, et le
# dépôt n'est jamais re-servi en lecture.
#
# Pourquoi pas `python3 -m http.server` : `SimpleHTTPRequestHandler` ne définit
# que do_GET et do_HEAD, donc un POST reçoit 501. Le piège n'est pas qu'il
# refuse — c'est qu'il reste JOIGNABLE. Un ancien serveur qui traîne sur le port
# laisse la page se charger normalement et ne fait échouer que le dépôt : un
# faux négatif silencieux, en fin de mesure. D'où /sante et sa signature, que le
# script de pilotage exige avant de commencer.
# ─────────────────────────────────────────────────────────────────────────────

import argparse
import hashlib
import json
import os
import re
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROTOCOLE = 2
OUTIL = "regarde-lot0-temoin1"

# Borne 5 — la taille est refusée AVANT toute lecture, sur Content-Length.
MAX_CORPS = 4 * 1024 * 1024
MAX_FICHIERS_PAR_RUN = 64
MAX_FICHIERS_PAR_VIE = 512

# Borne 4 — `run` et `nom` ne sont jamais des chemins. Pas de `/`, pas de `..`,
# pas de point initial, pas de `~` : l'expression ne les laisse pas passer.
RE_SEGMENT = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")

# Vocabulaire FERMÉ des noms de dépôt. Un nom hors liste est un 400, pas un
# fichier. « NN-<etat> » couvre les relevés numérotés du plan.
RE_NOM = re.compile(r"^(00-session|02-etat|03-calibrage|fin|interrompu|\d{2}-[a-z0-9][a-z0-9-]{0,31})$")

# Borne 7 — schéma fermé. Toute clé de premier niveau hors de cette liste fait
# rendre 400. Trois interdits qui ne s'y trouvent donc pas, et qu'une revue doit
# reverifier : le contenu de #probe (l'opérateur y tape du texte libre), le titre
# ou l'URL d'autres onglets, et quoi que ce soit venant du presse-papiers.
CLES_ADMISES = {
    "tool", "protocole", "sessionId", "run", "capturedAt", "ecran", "pleinEcran",
    "probeFocalise", "chiffresVisibles", "reglette", "verbes", "journal", "c3b",
    "c11", "drapeaux",
}

EXTENSIONS_SERVIES = {".html": "text/html; charset=utf-8",
                      ".css": "text/css; charset=utf-8",
                      ".js": "text/javascript; charset=utf-8"}


class Etat:
    """Compteurs partagés. Le serveur est multithread : un verrou, pas d'astuce."""

    def __init__(self):
        self.verrou = threading.Lock()
        self.par_run = {}
        self.total = 0
        self.depuis = time.time()


def journaliser(*champs):
    """Une ligne par événement, sur stdout. Le script relit ce flot pour rendre
    son index de fichiers : c'est la seule trace qui survit à la page."""
    horodatage = time.strftime("%Y-%m-%dT%H:%M:%S")
    print(horodatage + "  " + "  ".join(str(c) for c in champs), flush=True)


def fabriquer(racine_web, racine_depot, port, etat):

    hotes_admis = {f"127.0.0.1:{port}", f"localhost:{port}"}
    origines_admises = {f"http://127.0.0.1:{port}", f"http://localhost:{port}"}

    class Handler(BaseHTTPRequestHandler):
        server_version = "regarde-temoin/2"
        sys_version = ""
        protocol_version = "HTTP/1.1"

        # ── Sorties ──────────────────────────────────────────────────────────

        def _repondre(self, code, corps=b"", type_mime="application/json"):
            self.send_response(code)
            self.send_header("Content-Type", type_mime)
            self.send_header("Content-Length", str(len(corps)))
            # `no-store` et non `no-cache` : le témoin est un instrument, une
            # réponse relue depuis un cache mentirait sur l'état courant.
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            if corps:
                self.wfile.write(corps)

        def _json(self, code, objet):
            self._repondre(code, json.dumps(objet, ensure_ascii=False).encode("utf-8"))

        def _refus(self, code, motif):
            journaliser(code, self.command, self.path.split("?")[0], motif)
            self._json(code, {"erreur": motif})

        def log_message(self, *_args):
            pass  # On journalise nous-mêmes, en une ligne par événement.

        # ── Borne 2 — le Host sur liste blanche, sur TOUTES les routes ────────
        #
        # Le bind sur la boucle locale ne protège pas du DNS rebinding : un site
        # visité dans un autre onglet peut faire résoudre son domaine vers
        # 127.0.0.1 et nous parler avec le Host de son choix. C'est cette
        # vérification-ci qui le neutralise, pas le bind.
        def _hote_valide(self):
            return self.headers.get("Host", "") in hotes_admis

        # ── Routes ───────────────────────────────────────────────────────────

        def do_OPTIONS(self):
            # 405 délibérément : ne jamais répondre à un préflight CORS. C'est ce
            # qui coupe la voie d'écriture cross-origin, puisque le POST exige un
            # Content-Type non simple.
            self._refus(405, "OPTIONS non servi")

        def do_GET(self):
            if not self._hote_valide():
                return self._refus(403, "hôte non admis")
            chemin = self.path.split("?", 1)[0]

            if chemin == "/sante":
                with etat.verrou:
                    vie = etat.total
                return self._json(200, {
                    "serveur": "regarde-temoin", "protocole": PROTOCOLE,
                    "racine": racine_web, "depot": racine_depot, "pid": os.getpid(),
                    "depuis": int(etat.depuis), "fichiers": {"vie": vie},
                })

            # Le dépôt n'est JAMAIS servi en lecture. Le re-servir en HTTP
            # transformerait une écriture en XSS stocké sur la boucle locale.
            if chemin.startswith("/depot/"):
                return self._refus(404, "le dépôt n'est pas servi")

            return self._statique(chemin)

        def _statique(self, chemin):
            if chemin in ("/", ""):
                chemin = "/index.html"
            if ".." in chemin or chemin.startswith("//"):
                return self._refus(404, "chemin refusé")
            extension = os.path.splitext(chemin)[1].lower()
            if extension not in EXTENSIONS_SERVIES:
                return self._refus(404, f"extension non servie : {extension or '(aucune)'}")

            cible = os.path.realpath(os.path.join(racine_web, chemin.lstrip("/")))
            if not (cible == racine_web or cible.startswith(racine_web + os.sep)):
                return self._refus(404, "hors racine")
            if not os.path.isfile(cible):
                return self._refus(404, "introuvable")

            with open(cible, "rb") as f:
                corps = f.read()
            self._repondre(200, corps, EXTENSIONS_SERVIES[extension])

        def do_POST(self):
            if not self._hote_valide():
                return self._refus(403, "hôte non admis")

            # Borne 3 — sans ces deux en-têtes, n'importe quelle page ouverte
            # dans le navigateur pourrait écrire des fichiers : un POST simple
            # part en cross-origin même si la réponse est bloquée.
            if self.headers.get("Sec-Fetch-Site") != "same-origin":
                return self._refus(403, "Sec-Fetch-Site absent ou non same-origin")
            if self.headers.get("Origin") not in origines_admises:
                return self._refus(403, "Origin non admise")
            if not (self.headers.get("Content-Type", "").split(";")[0].strip()
                    == "application/json"):
                return self._refus(403, "Content-Type doit être application/json")

            # Borne 5 — chunked refusé, Content-Length obligatoire, refus au-delà
            # de la borne AVANT la moindre lecture du corps.
            if self.headers.get("Transfer-Encoding"):
                return self._refus(400, "Transfer-Encoding refusé")
            brut = self.headers.get("Content-Length")
            if brut is None or not brut.isdigit():
                return self._refus(400, "Content-Length absent ou non numérique")
            taille = int(brut)
            if taille > MAX_CORPS:
                return self._refus(413, f"corps de {taille} octets, borne à {MAX_CORPS}")

            parties = self.path.split("?", 1)[0].strip("/").split("/")
            if len(parties) != 3 or parties[0] != "depot":
                return self._refus(404, "route inconnue")
            _, run, nom = parties
            if not RE_SEGMENT.match(run):
                return self._refus(400, f"run refusé : {run!r}")
            if not (RE_SEGMENT.match(nom) and RE_NOM.match(nom)):
                return self._refus(400, f"nom hors vocabulaire : {nom!r}")

            with etat.verrou:
                if etat.total >= MAX_FICHIERS_PAR_VIE:
                    return self._refus(429, f"{MAX_FICHIERS_PAR_VIE} fichiers pour cette vie")
                if etat.par_run.get(run, 0) >= MAX_FICHIERS_PAR_RUN:
                    return self._refus(429, f"{MAX_FICHIERS_PAR_RUN} fichiers pour le run {run}")

            # Lecture d'EXACTEMENT Content-Length octets, jamais jusqu'à EOF.
            corps = self.rfile.read(taille)
            if len(corps) != taille:
                return self._refus(400, "corps tronqué")

            try:
                objet = json.loads(corps.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as e:
                return self._refus(400, f"JSON invalide : {e}")
            if not isinstance(objet, dict):
                return self._refus(400, "objet attendu à la racine")
            if objet.get("tool") != OUTIL:
                return self._refus(400, f"champ tool inattendu : {objet.get('tool')!r}")
            if objet.get("protocole") != PROTOCOLE:
                return self._refus(400, f"protocole {objet.get('protocole')!r} ≠ {PROTOCOLE}")
            intruses = sorted(set(objet) - CLES_ADMISES)
            if intruses:
                return self._refus(400, "clés hors schéma : " + ", ".join(intruses))

            return self._ecrire(run, nom, objet)

        # ── Écriture atomique ────────────────────────────────────────────────

        def _ecrire(self, run, nom, objet):
            dossier = os.path.join(racine_depot, run)
            os.makedirs(dossier, mode=0o700, exist_ok=True)

            # Borne 4 — l'extension est IMPOSÉE ici, jamais reprise de la
            # requête : ni .command, ni .sh, ni .html, ni .webloc, ni .plist.
            final = os.path.realpath(os.path.join(dossier, nom + ".json"))
            if not final.startswith(os.path.realpath(racine_depot) + os.sep):
                return self._refus(400, "chemin hors dépôt")

            # Re-sérialisation : le fichier ne contient que ce que le parseur a
            # accepté — ni octet NUL, ni queue de garbage après le JSON.
            charge = json.dumps(objet, ensure_ascii=False, sort_keys=True).encode("utf-8")
            empreinte = hashlib.sha256(charge).hexdigest()

            with etat.verrou:
                etat.total += 1
                etat.par_run[run] = etat.par_run.get(run, 0) + 1
                rang = etat.total

            partiel = f"{final}.{os.getpid()}.{rang}.part"
            fd = os.open(partiel, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            try:
                with os.fdopen(fd, "wb") as f:
                    f.write(charge)
                    f.flush()
                    os.fsync(f.fileno())

                # `link` est atomique ET échoue en EEXIST si la cible existe : le
                # fichier apparaît d'un coup, complet, et ne peut jamais être
                # écrasé. C'est cette propriété qui rend correcte la
                # synchronisation par simple présence de fichier — un lecteur qui
                # teste `-f` ne voit jamais un demi-fichier.
                collision = False
                try:
                    os.link(partiel, final)
                except FileExistsError:
                    collision = True
                    # On ne perd pas la preuve pour autant : la seconde écriture
                    # atterrit à côté, et le 409 dit qu'elle a eu lieu. C'est ce
                    # qui rend un rechargement de page visible après coup.
                    suffixe = 2
                    while suffixe < 64:
                        voisin = os.path.join(dossier, f"{nom}~{suffixe}.json")
                        try:
                            os.link(partiel, voisin)
                            final = voisin
                            break
                        except FileExistsError:
                            suffixe += 1
            finally:
                try:
                    os.unlink(partiel)
                except FileNotFoundError:
                    pass

            code = 409 if collision else 201
            journaliser(code, final, len(charge), empreinte[:12])
            return self._json(code, {"chemin": final, "octets": len(charge),
                                     "sha256": empreinte,
                                     "collision": collision})

    return Handler


class Serveur(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True          # SO_REUSEADDR : relancer sans attendre TIME_WAIT.
    # SO_REUSEPORT reste JAMAIS armé : deux serveurs partageant le port se
    # répartiraient les requêtes au hasard, et un dépôt sur deux disparaîtrait
    # dans l'autre processus — sans la moindre erreur nulle part.

    def server_bind(self):
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        ThreadingHTTPServer.server_bind(self)


def main():
    ap = argparse.ArgumentParser(description="Serveur de dépôt du témoin (S29)")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--racine", required=True, help="racine web, servie en lecture seule")
    ap.add_argument("--depot", required=True, help="racine de dépôt, jamais servie")
    ap.add_argument("--duree-max", type=int, default=7200,
                    help="arrêt automatique, en secondes (0 = jamais)")
    a = ap.parse_args()

    # Borne 1 — le bind n'est pas un paramètre libre.
    if a.bind != "127.0.0.1":
        sys.exit("✗ --bind n'accepte que 127.0.0.1 : ce serveur écrit sur disque.")

    racine_web = os.path.realpath(a.racine)
    racine_depot = os.path.realpath(a.depot)
    if not os.path.isdir(racine_web):
        sys.exit(f"✗ racine web introuvable : {racine_web}")
    os.makedirs(racine_depot, mode=0o700, exist_ok=True)

    # Borne 4 — les deux racines ne doivent jamais se contenir. Un fichier
    # déposé qu'on pourrait re-servir en HTTP serait un XSS stocké.
    for a_, b_ in ((racine_web, racine_depot), (racine_depot, racine_web)):
        if b_ == a_ or b_.startswith(a_ + os.sep):
            sys.exit(f"✗ racine web et racine de dépôt s'imbriquent :\n  {racine_web}\n  {racine_depot}")

    etat = Etat()
    serveur = Serveur((a.bind, a.port), fabriquer(racine_web, racine_depot, a.port, etat))
    journaliser("000", "démarré", f"pid={os.getpid()}", f"port={a.port}",
                f"racine={racine_web}", f"depot={racine_depot}")

    if a.duree_max > 0:
        threading.Timer(a.duree_max, serveur.shutdown).start()
    try:
        serveur.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        journaliser("000", "arrêté", f"fichiers={etat.total}")


if __name__ == "__main__":
    main()
