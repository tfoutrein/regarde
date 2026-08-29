import AVFoundation
import CoreAudio
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Le périphérique d'entrée — S61, spécification § 7.2
//
// JAMAIS l'entrée par défaut. Sur un poste de développeur, « l'entrée par
// défaut » est ce que la dernière visioconférence a laissé : le pilote de
// boucle de Teams, un agrégé, BlackHole. Capturer l'un d'eux transcrirait la
// réunion des collègues au lieu de la voix de l'utilisateur — le doctor du
// lot 1 le repère depuis toujours (« Microsoft Teams Audio ← pilote de boucle,
// à exclure »), ce fichier applique enfin l'exclusion.
//
// Le CHOIX est une fonction pure sur une liste de candidats : elle se juge
// sans brancher un seul périphérique, sur les cas réellement rencontrés.
// L'énumération vivante et la traduction vers CoreAudio sont à côté, et ne
// décident de rien.
// ─────────────────────────────────────────────────────────────────────────────

enum Peripheriques {

    /// Les marqueurs de nom qui trahissent un pilote de boucle ou un agrégé —
    /// UNE seule liste, partagée avec le doctor (`AudioDevicesCheck`).
    static let marqueursDeBoucle = [
        "loopback", "blackhole", "soundflower", "vb-cable", "teams", "zoom",
        "aggregate", "multi-output", "virtual",
    ]

    /// Un périphérique réduit à ce dont le choix a besoin.
    struct Candidat: Equatable, Sendable {
        let uid: String
        let nom: String
        /// Le micro intégré de la machine (`BuiltInMicrophoneDevice`).
        let interne: Bool

        /// Un nom qui porte un marqueur de boucle — l'exclusion se juge sur le
        /// nom parce que c'est la seule chose que ces pilotes ne maquillent
        /// pas : leur `deviceType` est celui d'un micro ordinaire.
        func estBoucle(marqueurs: [String] = Peripheriques.marqueursDeBoucle) -> Bool {
            let bas = nom.lowercased()
            return marqueurs.contains { bas.contains($0) }
        }
    }

    /// LE choix, pur. L'interne d'abord — c'est celui que la mesure de
    /// dictée du § 10.1 qualifie —, sinon le premier externe sain, sinon rien :
    /// rien vaut mieux qu'un pilote de boucle.
    static func choisir(parmi candidats: [Candidat],
                        marqueurs: [String] = marqueursDeBoucle) -> Candidat? {
        let sains = candidats.filter { !$0.estBoucle(marqueurs: marqueurs) }
        if let interne = sains.first(where: \.interne) { return interne }
        return sains.first
    }

    // MARK: - Le vivant

    /// Les périphériques de la machine, tels que la sélection les voit.
    static func candidatsVivants() -> [Candidat] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified)
        return session.devices.map {
            Candidat(uid: $0.uniqueID, nom: $0.localizedName,
                     interne: $0.deviceType == .microphone
                        || $0.uniqueID == "BuiltInMicrophoneDevice")
        }
    }

    /// L'`AudioDeviceID` CoreAudio d'un uid AVFoundation — c'est lui que
    /// l'`inputNode` de l'`AVAudioEngine` accepte, pas l'uid.
    static func identifiantCoreAudio(uid: String) -> AudioDeviceID? {
        var adresse = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uidCF = uid as CFString
        var identifiant = AudioDeviceID(kAudioObjectUnknown)
        var taille = UInt32(MemoryLayout<AudioDeviceID>.size)
        let statut = withUnsafeMutablePointer(to: &uidCF) { pointeurUID in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &adresse,
                UInt32(MemoryLayout<CFString>.size), pointeurUID,
                &taille, &identifiant)
        }
        guard statut == noErr, identifiant != kAudioObjectUnknown else { return nil }
        return identifiant
    }
}

extension Peripheriques {
    /// Le nom de l'entrée PAR DÉFAUT du système — celle que le moteur écoute
    /// si l'imposition échoue. Diagnostic seul : le produit ne l'utilise jamais.
    static func nomDuDefautSysteme() -> String? {
        var identifiant = AudioDeviceID(0)
        var taille = UInt32(MemoryLayout<AudioDeviceID>.size)
        var adresse = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &adresse, 0, nil,
                                         &taille, &identifiant) == noErr else { return nil }
        var nom: CFString = "" as CFString
        var tailleNom = UInt32(MemoryLayout<CFString>.size)
        var adresseNom = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(identifiant, &adresseNom, 0, nil, &tailleNom, &nom) == noErr else { return nil }
        return "\(nom as String) (CoreAudio \(identifiant))"
    }
}
