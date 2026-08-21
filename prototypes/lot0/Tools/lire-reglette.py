#!/usr/bin/env python3
# ─────────────────────────────────────────────────────────────────────────────
# Lecture de la réglette dans un PNG — implémentation de RÉFÉRENCE
#
# Le décodeur qui compte est `FrameNumberReader.swift` (S31). Celui-ci existe
# pour deux raisons : vérifier le témoin sans attendre S31, et servir d'oracle —
# deux implémentations indépendantes qui doivent rendre le même numéro sur la
# même image, sans quoi l'une des deux se trompe.
#
# Il ne suppose NI la position de la réglette, NI le plein écran, NI l'absence de
# boîtage : il balaie l'image, trouve le localisateur, déduit le pas de grille,
# puis lit les bits par décision DIFFÉRENTIELLE entre les deux rangées.
#
# DEUX PIÈGES, tous deux trouvés en l'écrivant contre une vraie capture, et tous
# deux absents de la spécification de conception :
#
#   1. « la plus longue plage sombre » ne suffit pas à trouver le localisateur.
#      Le fond du témoin est sombre (#0b0b0d) et la passe de charge sort entre 8
#      et 33 sur 255 : la plus longue plage sombre de l'image est une ligne de
#      fond ENTIÈRE. La plage doit être BORNÉE PAR DU BLANC des deux côtés —
#      c'est à cela que sert la zone de silence, et l'oublier fait chercher au
#      mauvais endroit.
#
#   2. la ligne de balayage qui trouve la barre n'est pas le BORD de la barre.
#      Le balayage avance de trois en trois et tombe où il tombe ; prendre ce y
#      pour l'origine des rangées les décale toutes d'une fraction de module, et
#      les échantillons mordent sur la rangée voisine. Il faut remonter au bord.
#
# Usage : lire-reglette.py <image.png>
# ─────────────────────────────────────────────────────────────────────────────
import struct, sys, zlib

def lire_png_gris(chemin):
    d = open(chemin, 'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n'
    i, idat, w = 8, b'', None
    while i < len(d):
        n, typ = struct.unpack('>I', d[i:i+4])[0], d[i+4:i+8]
        corps = d[i+8:i+8+n]
        if typ == b'IHDR':
            w, h, prof, coul = struct.unpack('>IIBB', corps[:10])
            assert prof == 8 and coul in (2, 6), f"profondeur {prof} couleur {coul}"
            canaux = 3 if coul == 2 else 4
        elif typ == b'IDAT': idat += corps
        elif typ == b'IEND': break
        i += 12 + n
    brut = zlib.decompress(idat)
    pas, ligne = canaux, w * canaux
    gris = bytearray(w * h)
    prec = bytearray(ligne)
    p = 0
    for y in range(h):
        f = brut[p]; p += 1
        cur = bytearray(brut[p:p+ligne]); p += ligne
        for x in range(ligne):                      # défiltrage PNG
            a = cur[x-pas] if x >= pas else 0
            b = prec[x]
            c = prec[x-pas] if x >= pas else 0
            if   f == 1: cur[x] = (cur[x] + a) & 255
            elif f == 2: cur[x] = (cur[x] + b) & 255
            elif f == 3: cur[x] = (cur[x] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b-c), abs(a-c), abs(a+b-2*c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[x] = (cur[x] + pr) & 255
        for x in range(w):                          # luma approché : le vert suffit,
            gris[y*w + x] = cur[x*canaux + 1]       # la réglette est achromatique
        prec = cur
    return w, h, gris

def decoder(w, h, g):
    M_ATTENDU, COLS, ROWS, BITS, DONNEES = 64, 34, 6, 28, 20
    px = lambda x, y: g[y*w + x]

    # 1. Chercher le localisateur : une ligne portant une longue plage sombre.
    #    La barre du cadre fait 32 modules ; la plus longue plage possible dans
    #    une rangée de DONNÉES en fait 25 (vérifié exhaustivement sur 2^20).
    #    22 % d'écart, hors de toute tolérance d'appariement.
    #    La plage doit être BORNÉE PAR DU BLANC des deux côtés : c'est à cela que
    #    sert la zone de silence, et l'ignorer fait trouver le fond de la scène.
    #    Le fond du témoin est sombre (#0b0b0d) et la passe de charge sort entre 8
    #    et 33 sur 255 : sans cette contrainte, la plus longue plage sombre de
    #    l'image est une ligne de fond entière, bornée par les bords et non par du
    #    blanc. Le décodeur refusait alors, ce qui est le bon comportement pour une
    #    mauvaise raison — et sur une scène claire il aurait pu APPARIER à tort.
    best = None
    for y in range(h - 1, 0, -3):                   # depuis le bas : la réglette y vit
        run = deb = 0
        for x in range(w + 1):
            sombre = x < w and px(x, y) < 96
            if sombre:
                if run == 0: deb = x
                run += 1
            else:
                if run:
                    avant = px(deb - 1, y) if deb > 0 else 0
                    apres = px(x, y) if x < w else 0
                    if avant > 160 and apres > 160:          # zone de silence des deux côtés
                        if best is None or run > best[0]: best = (run, deb, y)
                run = 0
    if best is None: return {'refus': 'aucune plage sombre'}
    longueur, x0, yBarre = best
    module = longueur / 32.0
    if abs(module - M_ATTENDU) > 1.0:
        return {'refus': f'pas de grille {module:.2f} px, attendu {M_ATTENDU}'}
    if module < 30: return {'refus': f'module {module:.1f} px < 30 — capture trop réduite'}

    # 2. Le cadre : la barre trouvée est la haute (rangée 1) ou la basse (rangée 4).
    #    On cherche l'autre à 3 modules de distance, dans les deux sens.
    M = module
    for signe in (+1, -1):
        y2 = int(round(yBarre + signe * 3 * M))
        if not (0 <= y2 < h): continue
        sombres = sum(1 for k in range(32) if px(int(x0 + (k + .5) * M), y2) < 96)
        if sombres >= 31:
            yHaut = min(yBarre, y2); break
    else:
        return {'refus': 'barre jumelle du cadre introuvable à 3 modules'}

    # `yHaut` est une ligne de BALAYAGE prise dans la barre, pas son bord : le
    # balayage avance de 3 en 3 et tombe où il tombe. Prendre ce y pour l'origine
    # des rangées les décalerait toutes d'une fraction de module, et les
    # échantillons mordraient sur la rangée voisine. On remonte au bord.
    sonde = int(x0 + 16 * M)
    while yHaut > 0 and px(sonde, yHaut - 1) < 96: yHaut -= 1

    # 3. Colonnes témoins blanches, aux deux bouts de l'intérieur.
    rg = lambda r: int(round(yHaut + (r + .5) * M))            # r=0 → barre haute
    ech = lambda cx, cy: sum(px(int(cx+dx), int(cy+dy))
                             for dy in range(-int(M//4), int(M//4))
                             for dx in range(-int(M//4), int(M//4))) / (2*int(M//4))**2
    colx = lambda c: x0 + (c + .5) * M                          # c=0 → montant gauche
    for r in (1, 2):
        for c in (1, 30):
            if ech(colx(c), rg(r)) < 160:
                return {'refus': f'colonne témoin ({r},{c}) non blanche'}

    # 4. Les 28 bits, par décision différentielle entre les deux rangées.
    G = crc = 0; contraste = 255; ambigus = 0
    for k in range(BITS):
        a = ech(colx(2 + k), rg(1))
        b = ech(colx(2 + k), rg(2))
        e = abs(a - b); contraste = min(contraste, e)
        if e < 40: ambigus += 1
        bit = 1 if a > b else 0
        if k < DONNEES: G |= bit << k
        else: crc |= bit << (k - DONNEES)
    if ambigus: return {'refus': f'{ambigus} bit(s) dans la bande d\'ambiguïté'}

    def crc8(x):
        c = 0xA5
        for byte in (x & 0xFF, (x >> 8) & 0xFF, (x >> 16) & 0x0F):
            c ^= byte
            for _ in range(8): c = ((c << 1) ^ 0x2F) & 0xFF if c & 0x80 else (c << 1) & 0xFF
        return c
    if crc != crc8(G): return {'refus': f'CRC {crc:#04x} ≠ {crc8(G):#04x}'}

    V = G
    s = 1
    while s < 20: V ^= V >> s; s <<= 1
    return {'V': V & 0xFFFFF, 'G': G, 'crc': crc, 'module': round(module, 2),
            'origine': (int(x0 - M), int(yHaut - M)), 'contraste': round(contraste),
            'ambigus': ambigus}

w, h, g = lire_png_gris(sys.argv[1])
print(f"image {w}×{h}")
r = decoder(w, h, g)
for k, v in r.items(): print(f"  {k:10} {v}")
