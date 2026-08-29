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
}

/// Qui reçoit les tranches — le moteur de S62, ou un banc.
protocol PuitsAudio: AnyObject, Sendable {
    func recevoir(_ tranche: TrancheAudio)
}
