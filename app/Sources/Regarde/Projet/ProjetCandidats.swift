import Darwin
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Les candidats projet — S51 (l'énumération), S52 (la décision)
//
// Un candidat est un répertoire de travail de SHELL vivant. Pas la fenêtre au
// premier plan, pas une préférence : ce que les shells de la machine regardent
// réellement, lu par `proc_pidinfo(PROC_PIDVNODEPATHINFO)` — le même chemin que
// suivra la détection complète de S52 sur les descendants des terminaux.
//
// S51 s'arrête à l'ÉNUMÉRATION : la liste, chaque entrée avec son motif. La
// pondération, les signaux forts et le verdict sont S52 — le plan l'ordonne
// ainsi : le visible d'abord, le pondéré ensuite.
// ─────────────────────────────────────────────────────────────────────────────

struct CandidatProjet: Equatable {
    let chemin: String
    /// D'où vient ce candidat — « cwd de zsh (pid 4242) ». Le motif est ce que
    /// le sélecteur affiche sous le chemin : un candidat sans motif est une
    /// assertion, pas une détection.
    let motif: String
    let pidShell: pid_t
}

enum ProjetCandidats {

    /// Les noms de processus qu'on considère comme des shells. Volontairement
    /// court : un shell exotique absent de la liste donne un candidat de moins,
    /// pas un faux candidat.
    static let shells: Set<String> = ["zsh", "bash", "fish", "sh", "dash", "nu"]

    /// Énumère les répertoires de travail des shells vivants, dédupliqués par
    /// chemin. L'ordre est stable : par chemin, pour que deux appels successifs
    /// rendent la même liste — un sélecteur qui réordonne sous le curseur fait
    /// cliquer à côté.
    static func enumerer() -> [CandidatProjet] {
        var tailles = proc_listallpids(nil, 0)
        guard tailles > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(tailles) + 64)
        tailles = proc_listallpids(&pids, Int32(pids.count) * Int32(MemoryLayout<pid_t>.size))
        guard tailles > 0 else { return [] }

        var parChemin: [String: CandidatProjet] = [:]
        for pid in pids.prefix(Int(tailles)) where pid > 0 {
            var nomTampon = [CChar](repeating: 0, count: 64)
            guard proc_name(pid, &nomTampon, UInt32(nomTampon.count)) > 0 else { continue }
            let nom = String(cString: nomTampon)
            guard shells.contains(nom) else { continue }
            guard let cwd = repertoireDeTravail(pid) else { continue }
            // La racine et le dossier personnel nu ne sont pas des projets :
            // les proposer noierait les vrais candidats sous du bruit de shells
            // fraîchement ouverts.
            guard cwd != "/", cwd != NSHomeDirectory() else { continue }
            if parChemin[cwd] == nil {
                parChemin[cwd] = CandidatProjet(
                    chemin: cwd, motif: "cwd de \(nom) (pid \(pid))", pidShell: pid)
            }
        }
        return parChemin.values.sorted { $0.chemin < $1.chemin }
    }

    /// Le répertoire de travail d'un processus, par libproc — sans fork, sans
    /// lsof, sans droit particulier pour ses propres processus et ceux de
    /// l'utilisateur.
    static func repertoireDeTravail(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let taille = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, taille) == taille else {
            return nil
        }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { brut in
            String(cString: brut.bindMemory(to: CChar.self).baseAddress!)
        }
    }
}
