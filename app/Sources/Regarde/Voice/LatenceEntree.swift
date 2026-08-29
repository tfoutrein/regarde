import AVFoundation
import CoreAudio
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// La latence d'entrée — S61, spécification § 3.6, ADR-0007
//
// `AVAudioTime.hostTime` date la REMISE du buffer par le tap, pas l'instant où
// le son a atteint le micro. Entre les deux : la latence de présentation du
// moteur, la latence du périphérique, et sa marge de sécurité. Micro interne :
// 10 à 30 ms, négligeable. AirPods : 150 à 300 ms — tout le budget d'erreur
// d'ancrage du « premier mot » (lot5-seuils § 1, seuil n°3). La somme est
// mesurée à l'ouverture et à chaque changement de configuration, soustraite
// dans `bufferStartTime` par le moteur (S62), et affichée au doctor.
//
// La SOMME est pure ; la mesure interroge CoreAudio, et ne décide de rien.
// ─────────────────────────────────────────────────────────────────────────────

enum LatenceEntree {

    /// Les trois termes, chacun en millisecondes, et leur somme.
    struct Mesure: Equatable, Sendable {
        let presentationMs: Double
        let peripheriqueMs: Double
        let securiteMs: Double
        var totalMs: Double { presentationMs + peripheriqueMs + securiteMs }

        /// Pour le journal : « 24,0 ms (présentation 20,0 + périphérique 2,7 + sécurité 1,3) ».
        var description: String {
            String(format: "%.1f ms (présentation %.1f + périphérique %.1f + sécurité %.1f)",
                   totalMs, presentationMs, peripheriqueMs, securiteMs)
        }
    }

    /// LA somme, pure : la présentation arrive en secondes, les deux autres
    /// termes en FRAMES à la cadence du périphérique — l'oubli de la cadence
    /// donnerait des millisecondes fausses d'un facteur 48.
    static func somme(presentationSecondes: Double,
                      latenceFrames: UInt32, securiteFrames: UInt32,
                      cadence: Double) -> Mesure {
        let parFrame = cadence > 0 ? 1000 / cadence : 0
        return Mesure(presentationMs: presentationSecondes * 1000,
                      peripheriqueMs: Double(latenceFrames) * parFrame,
                      securiteMs: Double(securiteFrames) * parFrame)
    }

    // MARK: - Le vivant

    /// Mesure sur un périphérique CoreAudio, côté entrée, avec la latence de
    /// présentation que l'`inputNode` rapporte pour le moteur en cours.
    static func mesurer(peripherique: AudioDeviceID, presentationSecondes: Double) -> Mesure {
        let cadence = lire(peripherique, kAudioDevicePropertyNominalSampleRate, Float64(48_000))
        let latence = lire(peripherique, kAudioDevicePropertyLatency, UInt32(0))
        let securite = lire(peripherique, kAudioDevicePropertySafetyOffset, UInt32(0))
        return somme(presentationSecondes: presentationSecondes,
                     latenceFrames: latence, securiteFrames: securite, cadence: cadence)
    }

    /// Une propriété CoreAudio scalaire, scope ENTRÉE, avec repli sur une
    /// valeur nommée : une propriété absente n'est pas une latence nulle, mais
    /// on ne bloque pas une fenêtre de parole pour un périphérique taiseux —
    /// la valeur de repli est celle que le journal montrera.
    private static func lire<T>(_ peripherique: AudioDeviceID,
                                _ selecteur: AudioObjectPropertySelector, _ repli: T) -> T {
        var adresse = AudioObjectPropertyAddress(
            mSelector: selecteur,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var valeur = repli
        var taille = UInt32(MemoryLayout<T>.size)
        let statut = AudioObjectGetPropertyData(peripherique, &adresse, 0, nil, &taille, &valeur)
        return statut == noErr ? valeur : repli
    }
}
