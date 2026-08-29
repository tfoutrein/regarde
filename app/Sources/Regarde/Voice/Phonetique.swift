import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// La distance phonétique — S68, § 7.3
//
// Le danger que le lexique existe pour réduire n'est pas le mot inconnu, c'est
// le mot PLAUSIBLE : « chant » au lieu de « champ », « pratique » au lieu de
// « padding ». La confiance ne le signale pas — le moteur est sûr de lui — et
// la relecture rapide ne le voit pas, parce que la phrase reste du français
// valide. Ce que le lexique peut faire, c'est proposer : les DEUX versions
// vont au rapport, et c'est la relecture humaine qui tranche.
//
// La comparaison se fait sur un SQUELETTE phonétique français, pas sur les
// lettres : « Checkou » et « Checkout » diffèrent d'une lettre muette, «
// graveQuelle » et « GraphQL » de presque tout à l'écrit et de peu à l'oreille.
// Le squelette applique les règles qui comptent en français — ph→f, qu→k,
// ou→u, eau→o, finales muettes — puis la distance de Levenshtein tranche.
//
// TOUT EST PUR ici : des chaînes entrent, un nombre sort. L'autotest le juge
// sur les erreurs RÉELLEMENT observées par ce moteur sur cette machine, pas
// sur des paires inventées.
// ─────────────────────────────────────────────────────────────────────────────

enum Phonetique {

    /// Le squelette phonétique d'un mot français (ou d'un anglicisme prononcé
    /// à la française, ce que le jargon front est presque toujours).
    static func squelette(_ mot: String) -> String {
        // 1. Minuscules, sans accents, lettres seulement — le camelCase et les
        //    tirets disparaissent : « z-index » et « Z index » se prononcent
        //    pareil, et c'est ce qui compte.
        var s = mot.folding(options: [.diacriticInsensitive, .caseInsensitive],
                            locale: Locale(identifier: "fr_FR"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
        guard !s.isEmpty else { return "" }

        // 2. Les digrammes, du plus long au plus court — l'ordre compte :
        //    « eau » doit passer avant « au », sinon il reste un « e ».
        for (de, vers) in [("eau", "o"), ("eu", "e"), ("au", "o"), ("ou", "u"),
                           ("oi", "wa"), ("ai", "e"), ("ei", "e"),
                           ("ph", "f"), ("ch", "x"), ("qu", "k"), ("gu", "g"),
                           ("th", "t"), ("ck", "k"), ("sh", "x"),
                           ("an", "a"), ("en", "a"), ("in", "e"), ("on", "o"),
                           ("un", "e"), ("am", "a"), ("em", "a"), ("om", "o")] {
            s = s.replacingOccurrences(of: de, with: vers)
        }

        // 3. Les lettres qui n'ont qu'un son : c→k, q→k, y→i, w→v, z→s.
        //    « x » garde sa valeur de digramme (ch) posée au-dessus.
        var lettres = ""
        for c in s {
            switch c {
            case "c", "q": lettres.append("k")
            case "y": lettres.append("i")
            case "w": lettres.append("v")
            case "z": lettres.append("s")
            case "h": break                       // muet en français
            default: lettres.append(c)
            }
        }

        // 4. Les doubles se réduisent : « spinner » et « spiner » sonnent pareil.
        var reduit = ""
        for c in lettres where reduit.last != c { reduit.append(c) }

        // 5. La finale muette tombe. Le français en a beaucoup — champ, grand,
        //    prix, long, petit — et c'est exactement le cas qu'on veut
        //    rapprocher : « chant » et « champ » sont homophones (/ʃɑ̃/), et
        //    le moteur les échange sans que la confiance ne bronche.
        if reduit.count > 2, let derniere = reduit.last,
           "estdpxg".contains(derniere) { reduit.removeLast() }
        return reduit
    }

    /// Distance d'édition entre deux squelettes. Deux lignes de tampon, pas de
    /// matrice : cette fonction tourne sur chaque mot de chaque segment contre
    /// chaque terme du lexique.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a.utf8), y = Array(b.utf8)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var precedente = Array(0...y.count)
        var courante = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            courante[0] = i
            for j in 1...y.count {
                let cout = x[i - 1] == y[j - 1] ? 0 : 1
                courante[j] = min(courante[j - 1] + 1,
                                  precedente[j] + 1,
                                  precedente[j - 1] + cout)
            }
            swap(&precedente, &courante)
        }
        return precedente[y.count]
    }

    /// Deux mots se ressemblent-ils assez pour qu'on ose proposer ?
    ///
    /// Le seuil est RELATIF à la longueur : une lettre d'écart sur trois
    /// lettres est un autre mot, une lettre sur dix est un accent. Un mot
    /// entendu très court ne propose rien — « you » ne doit pas devenir
    /// « useEffect ».
    static func proche(_ entendu: String, _ candidat: String) -> Bool {
        let a = squelette(entendu), b = squelette(candidat)
        guard a.count >= 2, b.count >= 2 else { return false }
        // Un HOMOPHONE exact se propose même court : « chant » et « champ » se
        // réduisent tous deux à `xa`, et c'est précisément l'échange que le
        // moteur fait sans que la confiance ne bronche.
        if a == b { return true }
        // Une RESSEMBLANCE, elle, demande de la matière : une lettre d'écart
        // sur trois lettres est un autre mot, une sur dix est un accent. Et un
        // mot entendu très court ne propose rien — « you » ne doit jamais
        // devenir « useEffect ».
        guard a.count >= 3, b.count >= 3 else { return false }
        let distance = levenshtein(a, b)
        let plafond = max(1, min(a.count, b.count) / 3)
        return distance <= plafond
    }
}
