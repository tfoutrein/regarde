import AppKit
import Foundation
import RegardeRender

// ─────────────────────────────────────────────────────────────────────────────
// La revue à la demande — S71, § 6.6 et § 11.3
//
// La conception initiale ouvrait la revue TOUTE SEULE dès qu'un segment avait
// une confiance faible — c'est-à-dire à chaque session — et plaçait ainsi 45 à
// 120 s de coût fixe exactement sur le poste qui annule le gain de l'outil.
// Avec le micro lié au geste, la notion de confiance de rattachement a disparu
// et la revue ne s'ouvre plus jamais d'elle-même : elle attend `R` dans les
// huit secondes du bandeau, et rien d'autre ne la déclenche.
//
// Elle sert à TROIS choses, dans cet ordre d'usage réel (§ 6.6) : éditer le
// texte transcrit — le brut restant au manifeste —, supprimer une marque ou un
// segment, et vérifier les images qui vont partir.
//
// LE POINT DÉLICAT : la publication a DÉJÀ eu lieu quand la revue s'ouvre. Une
// correction ne « prépare » donc pas un rapport, elle en RÉÉCRIT un — mêmes
// fichiers, même numéro, même dossier. Le numéro ne bouge jamais : il a pu être
// prononcé à voix haute, et un feedback #42 qui deviendrait #43 en revue
// trahirait tout ce que l'ADR-0013 protège.
// ─────────────────────────────────────────────────────────────────────────────

enum Revue {

    /// Ce que la revue manipule — le manifeste publié, et où il vit.
    struct Etat {
        var manifeste: Manifeste.Racine
        let dossier: URL
        let racine: URL?
    }

    @MainActor static var courant: Etat?

    /// Charge le manifeste publié pour l'éditer. `nil` s'il n'y a rien à revoir.
    @MainActor
    static func charger() -> Etat? {
        guard let dossier = PorteurRetour.dossierPublie,
              let donnees = try? Data(contentsOf: dossier.appendingPathComponent("manifest.json")),
              let manifeste = try? Manifeste.decoder(donnees) else { return nil }
        let etat = Etat(manifeste: manifeste, dossier: dossier,
                        racine: PorteurRetour.racineProjet)
        courant = etat
        return etat
    }

    // MARK: - Les opérations, PURES

    /// Retire une marque du manifeste — et son image, et sa parole.
    ///
    /// Le numéro laisse un TROU : il n'est jamais réattribué (ADR-0013), parce
    /// que l'utilisateur a pu le prononcer. Le rapport dira « marque N
    /// (supprimée) » si un autre texte y fait référence.
    static func supprimerMarque(_ numero: Int, de m: Manifeste.Racine) -> Manifeste.Racine {
        var r = m
        r.marks.removeAll { $0.number == numero }
        r.frames.removeAll { $0.marks == [numero] }
        for i in r.frames.indices { r.frames[i].marks.removeAll { $0 == numero } }
        r.frames.removeAll { $0.role == "crop" && $0.marks.isEmpty }
        return r
    }

    /// Retire un segment de parole, où qu'il soit.
    static func supprimerSegment(_ id: String, de m: Manifeste.Racine) -> Manifeste.Racine {
        var r = m
        r.session.voice?.removeAll { $0.id == id }
        if r.session.voice?.isEmpty == true { r.session.voice = nil }
        for i in r.marks.indices {
            r.marks[i].voice?.removeAll { $0.id == id }
            if r.marks[i].voice?.isEmpty == true { r.marks[i].voice = nil }
        }
        return r
    }

    /// Édite le texte d'un segment. Le BRUT ne bouge jamais — c'est lui que
    /// `transcript.txt` porte, et c'est lui qui dit ce qui a été entendu.
    /// `editedByUser` passe à vrai : le rapport doit pouvoir dire que la phrase
    /// a été retouchée.
    static func editerSegment(_ id: String, texte: String,
                              de m: Manifeste.Racine) -> Manifeste.Racine {
        var r = m
        func appliquer(_ voix: inout [Manifeste.Voice]?) {
            guard var liste = voix else { return }
            for i in liste.indices where liste[i].id == id {
                liste[i].text = texte
                liste[i].attachment.editedByUser = texte != liste[i].rawText
            }
            voix = liste
        }
        appliquer(&r.session.voice)
        for i in r.marks.indices { appliquer(&r.marks[i].voice) }
        return r
    }

    /// Édite la note écrite d'une marque (S70).
    static func editerNote(_ numero: Int, texte: String,
                           de m: Manifeste.Racine) -> Manifeste.Racine {
        var r = m
        for i in r.marks.indices where r.marks[i].number == numero {
            r.marks[i].text = texte.isEmpty ? nil : texte
        }
        return r
    }

    // MARK: - Réécrire ce qui est déjà publié

    /// Réécrit les quatre fichiers du dossier publié depuis le manifeste
    /// amendé. Le numéro, l'identifiant et le dossier ne changent PAS.
    @MainActor
    static func republier(_ etat: Etat) throws {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encodeur.encode(etat.manifeste)
            .write(to: etat.dossier.appendingPathComponent("manifest.json"), options: .atomic)
        try Data(Rendu.rendre(etat.manifeste).utf8)
            .write(to: etat.dossier.appendingPathComponent("report.md"), options: .atomic)
        try Data(Rendu.rendre(etat.manifeste, options: .init(profil: .chatWeb)).utf8)
            .write(to: etat.dossier.appendingPathComponent("paste-web.md"), options: .atomic)

        // `transcript.txt` suit le BRUT : une édition en revue ne le touche
        // pas — il est le témoin de ce qui a été entendu. Mais une SUPPRESSION
        // doit s'y voir, sans quoi le fichier citerait un segment que le
        // rapport ne connaît plus.
        let transcript = etat.dossier.appendingPathComponent("transcript.txt")
        let restants = (etat.manifeste.session.voice ?? [])
            + etat.manifeste.marks.flatMap { $0.voice ?? [] }
        if restants.isEmpty {
            try? FileManager.default.removeItem(at: transcript)
        } else {
            let lignes = restants.sorted { $0.onset < $1.onset }.map { v -> String in
                let t = max(0, v.onset)
                let temps = String(format: "%02d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
                let qui = v.attachedTo.map { "marque \($0)" } ?? "global"
                return "[\(temps)] (\(qui)) \(v.rawText)"
            }
            try Data((lignes.joined(separator: "\n") + "\n").utf8)
                .write(to: transcript, options: .atomic)
        }

        if let racine = etat.racine {
            let state = try AppendOnlyLog(url: racine.appendingPathComponent(".regarde/state.jsonl"))
            try state.append(ligne:
                #"{"uuid":"\#(etat.manifeste.session.uuid)","number":\#(etat.manifeste.session.number),"event":"revised","at":"\#(BouclePublication.isoAvecFuseau(Date()))"}"#)
            state.fermer()
        }
        Journal.block("REVUE", [
            ("feedback", "#\(etat.manifeste.session.number)"),
            ("marques", "\(etat.manifeste.marks.count)"),
            ("segments", "\(restants.count)"),
            ("dossier", etat.dossier.lastPathComponent),
        ])
    }

    // MARK: - Annuler

    /// ⌫ au bandeau : le feedback publié disparaît.
    ///
    /// Le dossier part, l'index NON — il est append-only (S47), et réécrire un
    /// journal pour effacer une ligne est exactement ce qu'un journal
    /// append-only interdit. `state.jsonl` reçoit l'annulation : qui relit sait
    /// que le numéro a existé et qu'il a été retiré.
    @MainActor
    static func annulerLaPublication() {
        guard let dossier = PorteurRetour.dossierPublie else {
            Journal.warn(.system, "bandeau — ⌫ : aucune publication à annuler")
            return
        }
        let numero = (try? Manifeste.decoder(
            Data(contentsOf: dossier.appendingPathComponent("manifest.json"))))?.session.number
        do {
            try FileManager.default.removeItem(at: dossier)
            if let racine = PorteurRetour.racineProjet, let numero {
                let state = try AppendOnlyLog(url: racine.appendingPathComponent(".regarde/state.jsonl"))
                try state.append(ligne:
                    #"{"number":\#(numero),"event":"cancelled","at":"\#(BouclePublication.isoAvecFuseau(Date()))"}"#)
                state.fermer()
            }
            Journal.event(.system, "bandeau — ⌫ : feedback #\(numero.map(String.init) ?? "?") annulé, dossier retiré")
            HUDWindow.shared.announce("Feedback annulé",
                                      detail: "le dossier a été retiré du projet", duration: 3)
        } catch {
            Journal.warn(.system, "annulation impossible — \(error)")
        }
    }
}
