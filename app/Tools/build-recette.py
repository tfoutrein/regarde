#!/usr/bin/env python3
"""Génère la page de recette depuis le markdown, pour que les deux ne divergent pas."""
import html as H, re, sys

# La source et la sortie sont des ARGUMENTS depuis S43.
#
# Elles étaient codées en dur, et la sortie pointait vers un répertoire de travail
# temporaire qui n'existe plus. Un générateur qui n'écrit que la recette d'un lot
# est un générateur qu'il faut modifier à chaque lot — et qu'on modifie mal, en
# oubliant de remettre la valeur précédente.
#
#   build-recette.py <source.md> <sortie.html>
#
# Sans argument, il retombe sur la recette du lot 2, pour que les commandes déjà
# écrites ailleurs continuent de fonctionner.
CSS = "app/Tools/recette.css"          # relatif à la racine du dépôt
SRC = sys.argv[1] if len(sys.argv) > 1 else "docs/livrables/lot2-recette.md"
OUT = sys.argv[2] if len(sys.argv) > 2 else "docs/livrables/lot2-recette.html"

def inline(t):
    t = H.escape(t)
    t = re.sub(r'`([^`]+)`', r'<kbd>\1</kbd>', t)
    t = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', t)
    t = re.sub(r'\*([^*]+)\*', r'<em>\1</em>', t)
    return t

lines = open(SRC).read().split("\n")

# ── L'identité du lot se LIT dans la source ──────────────────────────────────
#
# Elle était codée en dur — titre, chapô, durée, nombre de sections bloquantes, et
# jusqu'à la clé de stockage local. Générer la recette du lot 3 produisait donc une
# page qui s'annonçait « lot 2 », et cocher ses tests aurait ÉCRASÉ les coches du
# lot 2 dans le navigateur, puisque les deux partageaient la même clé.
#
# Tout vient maintenant du Markdown, qui est la seule source.
_titre = next((l for l in lines if l.startswith("# ")), "# Recette")
LOT = (re.search(r"lot\s+(\d+)", _titre, re.I) or re.match(r".*", "0")).group(1) \
      if re.search(r"lot\s+(\d+)", _titre, re.I) else "?"
# Le chapô est un PARAGRAPHE, pas une ligne : le Markdown est enveloppé à 95
# colonnes, et ne prendre que la première ligne le coupe au milieu d'une phrase —
# et laisse un `**` non fermé, que `inline` rend alors littéralement.
_i = next((k for k, l in enumerate(lines) if l.startswith("Ce que vous validez")), None)
if _i is None:
    LEDE = ""
else:
    _bloc = []
    for l in lines[_i:]:
        if not l.strip():
            break
        _bloc.append(l.strip())
    LEDE = inline(re.sub(r"^Ce que vous validez\s*:\s*", "", " ".join(_bloc)))
_duree = re.search(r"Comptez\s+\*\*([^*]+)\*\*", "\n".join(lines))
DUREE = _duree.group(1).replace(" à ", "–").replace(" minutes", "").strip() if _duree else "—"
BLOQUANTES = sum(1 for l in lines if re.match(r"^## \d+\..*bloquant", l))
body, i = [], 0
suite = None      # section de tests ouverte
tests = []        # tests de la section courante
n_tests = 0

def close_suite():
    global suite, tests
    if suite is None:
        return
    num, title, note = suite
    blocking = num in ("1", "2")
    body.append(f'<section class="suite{" blocking" if blocking else ""}">')
    body.append('<div class="suite-head">')
    body.append(f'<span class="suite-num">{int(num):02d}{" · bloquant" if blocking else ""}</span>')
    body.append(f'<h2 class="suite-title">{inline(title)}</h2>')
    body.append(f'<span class="tally">0/{len(tests)}</span></div>')
    if note:
        body.append(f'<p class="suite-note">{note}</p>')
    body.append('<ul class="tests">')
    CLASSE = {"FAIRE": "action", "REGARDER": "ou", "ATTENDU": "attendu", "SI ÇA RATE": "rate"}
    LIBELLE = {"FAIRE": "Faire", "REGARDER": "Regarder", "ATTENDU": "Attendu", "SI ÇA RATE": "Si ça rate"}
    for tid, text, hint, etapes in tests:
        assert tid.split(".")[0] == num, (
            f"le test {tid} est tombé dans la section {num} — "
            "un identifiant non reconnu a fermé la section trop tôt")
        h = f'<i>{hint}</i>' if hint else ''
        if etapes:
            # Chaque ATTENDU porte SA case.
            #
            # Un test qui demande de vérifier trois choses et n'offre qu'une case
            # oblige à tout retenir avant de cocher — et on coche en ayant vérifié
            # la première et oublié la troisième. Les cases filles vivent HORS du
            # label du test, sans quoi en cliquer une cocherait le test entier.
            attendus = 0
            lignes = []
            for genre, txt in etapes:
                if genre == "ATTENDU":
                    attendus += 1
                    sid = f"{tid}-{attendus}"
                    lignes.append(
                        f'<label class="etape attendu fille">'
                        f'<input type="checkbox" data-role="sub" data-id="{sid}" data-parent="{tid}">'
                        f'<span class="box mini"></span>'
                        f'<em>{LIBELLE[genre]}</em><span>{inline(txt)}</span></label>')
                else:
                    lignes.append(f'<span class="etape {CLASSE[genre]}">'
                                  f'<em>{LIBELLE[genre]}</em><span>{inline(txt)}</span></span>')
            body.append(
                f'<li class="test"><label class="maitre">'
                f'<input type="checkbox" data-role="master" data-id="{tid}">'
                f'<span class="box"></span><span class="tid">{tid}</span>'
                f'<b class="titre">{text}</b></label>'
                f'<div class="corps">{"".join(lignes)}{h}</div></li>')
        else:
            body.append(f'<li class="test"><label class="maitre plein">'
                        f'<input type="checkbox" data-role="master" data-id="{tid}">'
                        f'<span class="box"></span><span class="tid">{tid}</span>'
                        f'<span class="tbody">{text}{h}</span></label></li>')
    body.append('</ul></section>')
    suite, tests = None, []

while i < len(lines):
    ln = lines[i]

    m = re.match(r'^## (\d+)\.\s+(.*)$', ln)
    if m:
        close_suite()
        title = m.group(2)
        blocking = ""
        if "— bloquant" in title:
            title = title.replace("— bloquant", "").strip()
        suite = (m.group(1), title, "")
        i += 1
        # note de section : paragraphes avant le premier test
        note = []
        while i < len(lines) and not lines[i].startswith("- [ ]") and not lines[i].startswith("##"):
            if lines[i].strip() and not lines[i].startswith("**Mise en place**"):
                note.append(lines[i].strip())
            elif lines[i].startswith("**Mise en place**"):
                note.append(lines[i].strip())
            i += 1
        if note:
            suite = (suite[0], suite[1], inline(" ".join(note)))
        continue

    # « 7.1 bis » compte aussi : un identifiant non reconnu tomberait dans le cas
    # « paragraphe », qui ferme la section — et les tests suivants atterriraient sous le
    # titre d'après. C'est arrivé : 7.2 à 7.4 se sont retrouvés sous « 8. La session
    # explicite ».
    m = re.match(r'^- \[ \] \*\*([\d.]+(?:\s+bis)?)\*\*\s+(.*)$', ln)
    if m:
        tid, text = m.group(1), m.group(2)
        cont, hint = [], []
        # Les quatre temps d'un test : ce qu'on FAIT, où on REGARDE, ce qu'on doit
        # VOIR, et ce qu'on fait si ça rate. Mélangés dans un paragraphe, on ne sait
        # plus lequel des quatre on lit — et on fait le geste sans savoir ce qu'on
        # attend. Séparés, chaque ligne a un seul rôle.
        etapes = []           # [(genre, texte)]
        dans_note = False
        i += 1
        while i < len(lines) and lines[i].startswith("      "):
            s = lines[i].strip()
            # Une note est un BLOC, pas une ligne.
            # Le test se faisait ligne par ligne : la première commençait par `*` et
            # partait en note, les suivantes non et retombaient dans le texte
            # principal. Une note de trois lignes sortait donc coupée en deux, avec
            # sa fin recollée au milieu de l'énoncé et son début affiché après.
            #
            # Les DEUX recettes en souffraient. Celle du lot 2 a été lue comme ça,
            # soixante-quatre tests durant, par un outil dont toute la raison d'être
            # est d'empêcher la recette et le code de diverger.
            #
            # Une note s'ouvre sur une étoile SIMPLE — deux, c'est du gras — et se
            # ferme sur la ligne qui se termine par une étoile simple.
            m_etape = re.match(r'^(FAIRE|REGARDER|ATTENDU|SI ÇA RATE)\s*:\s*(.*)$', s)
            if m_etape and not dans_note:
                etapes.append([m_etape.group(1), m_etape.group(2)])
            elif etapes and not dans_note and not s.startswith("*"):
                # Continuation de l'étape précédente : le Markdown enveloppe à 95
                # colonnes, et une étape de deux lignes ne doit pas se scinder.
                etapes[-1][1] += " " + s
            elif not dans_note and s.startswith("*") and not s.startswith("**"):
                dans_note = True
                hint.append(s)
                if len(s) > 1 and s.endswith("*") and not s.endswith("**"):
                    dans_note = False
            elif dans_note:
                hint.append(s)
                if len(s) > 1 and s.endswith("*") and not s.endswith("**"):
                    dans_note = False
            else:
                cont.append(s)
            i += 1
        full = inline(" ".join([text] + cont))
        hint_html = inline(" ".join(hint).strip("*")) if hint else ""
        tests.append((tid, full, hint_html, etapes))
        n_tests += 1
        continue

    if ln.startswith("## "):
        close_suite()
        body.append(f'<h2 class="block">{inline(ln[3:])}</h2>')
        i += 1
        continue

    if ln.startswith("```"):
        close_suite()
        i += 1
        code = []
        while i < len(lines) and not lines[i].startswith("```"):
            c = H.escape(lines[i])
            c = re.sub(r'(#.*)$', r'<span class="c">\1</span>', c)
            code.append(c)
            i += 1
        i += 1
        body.append('<pre class="cmd">' + "\n".join(code) + '</pre>')
        continue

    if ln.startswith("|"):
        close_suite()
        rows = []
        while i < len(lines) and lines[i].startswith("|"):
            rows.append([c.strip() for c in lines[i].strip("|").split("|")])
            i += 1
        head, data = rows[0], rows[2:]
        body.append('<div class="tablewrap"><table class="keytable"><thead><tr>'
                    + "".join(f"<th>{inline(c)}</th>" for c in head)
                    + "</tr></thead><tbody>")
        for r in data:
            body.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
        body.append("</tbody></table></div>")
        continue

    if ln.startswith("> "):
        close_suite()
        quote = []
        while i < len(lines) and lines[i].startswith(">"):
            quote.append(lines[i].lstrip("> ").rstrip())
            i += 1
        body.append(f'<blockquote>{inline(" ".join(quote))}</blockquote>')
        continue

    m = re.match(r'^(\d+)\. (.*)$', ln)
    if m:
        close_suite()
        items = []
        while i < len(lines) and re.match(r'^\d+\. ', lines[i]):
            items.append(inline(re.sub(r'^\d+\. ', '', lines[i])))
            i += 1
        body.append('<ol class="asks">' + "".join(f"<li>{x}</li>" for x in items) + "</ol>")
        continue

    if ln.startswith("---") or not ln.strip():
        i += 1
        continue

    # Le titre de niveau 1 est déjà le H1 de la page.
    if ln.startswith("# "):
        i += 1
        continue

    # Un paragraphe court sur plusieurs lignes : on le rassemble AVANT de rendre
    # l'inline, sinon un gras à cheval sur deux lignes n'est jamais reconnu.
    close_suite()
    para = []
    while i < len(lines) and lines[i].strip() and not lines[i].startswith(
            ("#", "-", "|", ">", "```")) and not re.match(r'^\d+\. ', lines[i]):
        para.append(lines[i].strip())
        i += 1
    if para:
        body.append(f"<p>{inline(' '.join(para))}</p>")
    else:
        i += 1

close_suite()

css = open(CSS).read()
page = f'''<!doctype html>
<html lang="fr">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Recette Regarde lot {LOT}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,500;12..96,700;12..96,800&family=Karla:ital,wght@0,400;0,500;0,700;1,400&family=IBM+Plex+Mono:wght@400;500;600&display=swap">
<style>{css}</style>
<div class="progress-rail"><div class="progress-fill" id="fill"></div></div>
<div class="wrap">
<header class="masthead">
  <p class="eyebrow">Regarde · réception du lot {LOT}</p>
  <h1>Ce que le lot {LOT} doit tenir</h1>
  <p class="lede">{LEDE}</p>
  <div class="meta">
    <div><b id="count" class="live">0 / {n_tests}</b>tests cochés</div>
    <div><b>{DUREE}</b>minutes</div>
    <div><b>{BLOQUANTES}</b>sections bloquantes</div>
  </div>
  <div class="tools"><button class="tool" id="reset" type="button">Tout décocher</button></div>
</header>
{chr(10).join(body)}
<footer class="colophon"><span>Regarde · lot {LOT}</span><span>Vos coches restent dans ce navigateur</span></footer>
</div>
<script>
(function () {{
  var KEY = "regarde-recette-lot{LOT}-v2";
  var boxes = Array.prototype.slice.call(document.querySelectorAll('input[type="checkbox"]'));
  // Le décompte porte sur les TESTS, pas sur les cases : un test à trois attendus
  // ne vaut pas trois fois un test à un seul.
  var masters = boxes.filter(function (b) {{ return b.dataset.role === "master"; }});
  var fill = document.getElementById("fill"), count = document.getElementById("count");
  var total = masters.length;
  function load() {{ try {{ return JSON.parse(localStorage.getItem(KEY)) || {{}}; }} catch (e) {{ return {{}}; }} }}
  function save(s) {{ try {{ localStorage.setItem(KEY, JSON.stringify(s)); }} catch (e) {{}} }}
  function subsOf(id) {{
    return boxes.filter(function (b) {{ return b.dataset.parent === id; }});
  }}
  function refresh() {{
    var done = masters.filter(function (b) {{ return b.checked; }}).length;
    fill.style.width = (total ? (done / total) * 100 : 0) + "%";
    count.textContent = done + " / " + total;
    document.querySelectorAll("section.suite").forEach(function (s) {{
      var local = Array.prototype.slice.call(
        s.querySelectorAll('input[data-role="master"]'));
      var ok = local.filter(function (b) {{ return b.checked; }}).length;
      var t = s.querySelector(".tally");
      t.textContent = ok + "/" + local.length;
      t.classList.toggle("full", ok === local.length && local.length > 0);
    }});
  }}
  var state = load();
  boxes.forEach(function (b) {{ if (state[b.dataset.id]) b.checked = true; }});
  boxes.forEach(function (b) {{
    b.addEventListener("change", function () {{
      state[b.dataset.id] = b.checked;
      if (b.dataset.role === "master") {{
        // Cocher un test coche ses attendus : on vient de tout vérifier.
        subsOf(b.dataset.id).forEach(function (s) {{
          s.checked = b.checked; state[s.dataset.id] = s.checked;
        }});
      }} else if (b.dataset.parent) {{
        // Un test n'est acquis que quand TOUS ses attendus le sont. Décocher un
        // seul attendu retire le test : c'est le sens de la case.
        var freres = subsOf(b.dataset.parent);
        var tous = freres.every(function (s) {{ return s.checked; }});
        var m = document.querySelector('input[data-role="master"][data-id="' + b.dataset.parent + '"]');
        if (m) {{ m.checked = tous; state[m.dataset.id] = tous; }}
      }}
      save(state); refresh();
    }});
  }});
  document.getElementById("reset").addEventListener("click", function () {{
    boxes.forEach(function (b) {{ b.checked = false; }}); state = {{}}; save(state); refresh();
  }});
  refresh();
}})();
</script>
'''
open(OUT, "w").write(page)
print(f"{n_tests} tests → {OUT}")
