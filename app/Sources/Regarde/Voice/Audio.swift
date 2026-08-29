import AVFoundation
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// L'interface entre le micro (S61) et le moteur (S62) — une seule couture
//
// Le micro livre des TRANCHES : un buffer déjà converti au format du moteur,
// daté en ÉCHANTILLONS SORTIS du converter depuis l'ouverture de la fenêtre —
// jamais en secondes flottantes (le cumul chevauche d'un tick et le moteur
// refuse l'audio), jamais sur les échantillons entrants (les résidus de
// conversion créent des trous qui hachent les mots). Leçons payées par le
// harnais de S59, normatives ici (lot5-seuils § 2).
//
// Le moteur, lui, connaît le format qu'il veut (`bestAvailableAudioFormat`) :
// c'est lui qui le donne au micro à l'ouverture. Le micro ne suppose rien.
// ─────────────────────────────────────────────────────────────────────────────

/// Une tranche d'audio prête pour le moteur.
struct TrancheAudio: @unchecked Sendable {
    /// Au format cible, mono, cadence du moteur.
    let buffer: AVAudioPCMBuffer
    /// Position du premier échantillon de ce buffer, en échantillons SORTIS
    /// depuis l'ouverture de la fenêtre — 0 pour la première tranche.
    let premierEchantillon: Int64
    /// L'instant hôte de REMISE du buffer par le tap (pas de l'arrivée du son
    /// au micro : la latence d'entrée s'y soustrait, § 3.6).
    let hostTime: UInt64
    /// Nil quand `AVAudioTime.isHostTimeValid` est faux — périphérique
    /// agrégé — : le consommateur se replie sur le compteur d'échantillons.
    var hostTimeValide: Bool
    /// L'énergie de la tranche — RMS sur l'échelle Int16 —, le seul signal de
    /// parole qui existe EN TEMPS RÉEL : mesuré le 29 août, le moteur ne rend
    /// aucun résultat pendant les douze premières secondes d'une fenêtre. Sans
    /// ce signal, ni la prolongation de la fenêtre ni la rétention de l'éclair
    /// n'auraient de quoi décider.
    var energie: Double = 0

    /// RMS d'un buffer mono Int16 ou Float32, sur l'échelle Int16.
    static func energie(de buffer: AVAudioPCMBuffer) -> Double {
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var somme = 0.0
        if let canal = buffer.int16ChannelData {
            for i in 0..<n { let v = Double(canal[0][i]); somme += v * v }
        } else if let canal = buffer.floatChannelData {
            for i in 0..<n { let v = Double(canal[0][i]) * 32_767; somme += v * v }
        } else { return 0 }
        return (somme / Double(n)).squareRoot()
    }
}

/// Qui reçoit les tranches — le moteur de S62, ou un banc.
protocol PuitsAudio: AnyObject, Sendable {
    func recevoir(_ tranche: TrancheAudio)
}

/// Une source à usage unique pour `AVAudioConverter.convert(to:error:withInputFrom:)`.
///
/// Le bloc d'entrée du converter est `@Sendable` : il ne peut capturer ni une
/// variable mutable (« a-t-on déjà donné ? ») ni un tampon, qui n'est pas
/// Sendable — en release, ce ne sont plus des avertissements mais des
/// erreurs. La boîte porte les deux, sous `@unchecked`, parce que le converter
/// l'appelle depuis le seul thread qui l'a créée, de façon synchrone.
final class SourceAudioUnique: @unchecked Sendable {
    private let tampon: AVAudioPCMBuffer
    private var donnee = false
    init(_ tampon: AVAudioPCMBuffer) { self.tampon = tampon }
    func servir(_ statut: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if donnee { statut.pointee = .noDataNow; return nil }
        donnee = true
        statut.pointee = .haveData
        return tampon
    }
}
