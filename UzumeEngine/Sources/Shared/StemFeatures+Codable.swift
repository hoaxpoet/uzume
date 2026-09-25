// StemFeatures+Codable — the on-disk encoding of `StemFeatures` (LF.3, D-130), split from
// StemFeatures.swift at BC.1 to keep that file under the 400-line lint cap. Pure move.

import Foundation

// MARK: - Codable

/// On-disk encoding for `PersistentStemCache` (LF.3, D-130).
///
/// Only the 44 load-bearing fields participate. The internal `_sfPad*`
/// padding floats (slots 45–64) exist for the 256-byte GPU contract and
/// have no semantic content — excluding them keeps the on-disk format
/// stable across any future padding-layout change.
extension StemFeatures: Codable {

    private enum CodingKeys: String, CodingKey {
        case vocalsEnergy, vocalsBand0, vocalsBand1, vocalsBeat
        case drumsEnergy, drumsBand0, drumsBand1, drumsBeat
        case bassEnergy, bassBand0, bassBand1, bassBeat
        case otherEnergy, otherBand0, otherBand1, otherBeat
        case vocalsEnergyRel, vocalsEnergyDev
        case drumsEnergyRel, drumsEnergyDev
        case bassEnergyRel, bassEnergyDev
        case otherEnergyRel, otherEnergyDev
        case vocalsOnsetRate, vocalsCentroid, vocalsAttackRatio, vocalsEnergySlope
        case drumsOnsetRate, drumsCentroid, drumsAttackRatio, drumsEnergySlope
        case bassOnsetRate, bassCentroid, bassAttackRatio, bassEnergySlope
        case otherOnsetRate, otherCentroid, otherAttackRatio, otherEnergySlope
        case vocalsPitchHz, vocalsPitchConfidence
        case drumsEnergyDevSmoothed
        case cachedBassProportion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        vocalsEnergy = try container.decode(Float.self, forKey: .vocalsEnergy)
        vocalsBand0 = try container.decode(Float.self, forKey: .vocalsBand0)
        vocalsBand1 = try container.decode(Float.self, forKey: .vocalsBand1)
        vocalsBeat = try container.decode(Float.self, forKey: .vocalsBeat)
        drumsEnergy = try container.decode(Float.self, forKey: .drumsEnergy)
        drumsBand0 = try container.decode(Float.self, forKey: .drumsBand0)
        drumsBand1 = try container.decode(Float.self, forKey: .drumsBand1)
        drumsBeat = try container.decode(Float.self, forKey: .drumsBeat)
        bassEnergy = try container.decode(Float.self, forKey: .bassEnergy)
        bassBand0 = try container.decode(Float.self, forKey: .bassBand0)
        bassBand1 = try container.decode(Float.self, forKey: .bassBand1)
        bassBeat = try container.decode(Float.self, forKey: .bassBeat)
        otherEnergy = try container.decode(Float.self, forKey: .otherEnergy)
        otherBand0 = try container.decode(Float.self, forKey: .otherBand0)
        otherBand1 = try container.decode(Float.self, forKey: .otherBand1)
        otherBeat = try container.decode(Float.self, forKey: .otherBeat)
        vocalsEnergyRel = try container.decode(Float.self, forKey: .vocalsEnergyRel)
        vocalsEnergyDev = try container.decode(Float.self, forKey: .vocalsEnergyDev)
        drumsEnergyRel = try container.decode(Float.self, forKey: .drumsEnergyRel)
        drumsEnergyDev = try container.decode(Float.self, forKey: .drumsEnergyDev)
        bassEnergyRel = try container.decode(Float.self, forKey: .bassEnergyRel)
        bassEnergyDev = try container.decode(Float.self, forKey: .bassEnergyDev)
        otherEnergyRel = try container.decode(Float.self, forKey: .otherEnergyRel)
        otherEnergyDev = try container.decode(Float.self, forKey: .otherEnergyDev)
        vocalsOnsetRate = try container.decode(Float.self, forKey: .vocalsOnsetRate)
        vocalsCentroid = try container.decode(Float.self, forKey: .vocalsCentroid)
        vocalsAttackRatio = try container.decode(Float.self, forKey: .vocalsAttackRatio)
        vocalsEnergySlope = try container.decode(Float.self, forKey: .vocalsEnergySlope)
        drumsOnsetRate = try container.decode(Float.self, forKey: .drumsOnsetRate)
        drumsCentroid = try container.decode(Float.self, forKey: .drumsCentroid)
        drumsAttackRatio = try container.decode(Float.self, forKey: .drumsAttackRatio)
        drumsEnergySlope = try container.decode(Float.self, forKey: .drumsEnergySlope)
        bassOnsetRate = try container.decode(Float.self, forKey: .bassOnsetRate)
        bassCentroid = try container.decode(Float.self, forKey: .bassCentroid)
        bassAttackRatio = try container.decode(Float.self, forKey: .bassAttackRatio)
        bassEnergySlope = try container.decode(Float.self, forKey: .bassEnergySlope)
        otherOnsetRate = try container.decode(Float.self, forKey: .otherOnsetRate)
        otherCentroid = try container.decode(Float.self, forKey: .otherCentroid)
        otherAttackRatio = try container.decode(Float.self, forKey: .otherAttackRatio)
        otherEnergySlope = try container.decode(Float.self, forKey: .otherEnergySlope)
        vocalsPitchHz = try container.decode(Float.self, forKey: .vocalsPitchHz)
        vocalsPitchConfidence = try container.decode(Float.self, forKey: .vocalsPitchConfidence)
        drumsEnergyDevSmoothed = try container.decode(Float.self, forKey: .drumsEnergyDevSmoothed)
        cachedBassProportion = try container.decode(Float.self, forKey: .cachedBassProportion)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vocalsEnergy, forKey: .vocalsEnergy)
        try container.encode(vocalsBand0, forKey: .vocalsBand0)
        try container.encode(vocalsBand1, forKey: .vocalsBand1)
        try container.encode(vocalsBeat, forKey: .vocalsBeat)
        try container.encode(drumsEnergy, forKey: .drumsEnergy)
        try container.encode(drumsBand0, forKey: .drumsBand0)
        try container.encode(drumsBand1, forKey: .drumsBand1)
        try container.encode(drumsBeat, forKey: .drumsBeat)
        try container.encode(bassEnergy, forKey: .bassEnergy)
        try container.encode(bassBand0, forKey: .bassBand0)
        try container.encode(bassBand1, forKey: .bassBand1)
        try container.encode(bassBeat, forKey: .bassBeat)
        try container.encode(otherEnergy, forKey: .otherEnergy)
        try container.encode(otherBand0, forKey: .otherBand0)
        try container.encode(otherBand1, forKey: .otherBand1)
        try container.encode(otherBeat, forKey: .otherBeat)
        try container.encode(vocalsEnergyRel, forKey: .vocalsEnergyRel)
        try container.encode(vocalsEnergyDev, forKey: .vocalsEnergyDev)
        try container.encode(drumsEnergyRel, forKey: .drumsEnergyRel)
        try container.encode(drumsEnergyDev, forKey: .drumsEnergyDev)
        try container.encode(bassEnergyRel, forKey: .bassEnergyRel)
        try container.encode(bassEnergyDev, forKey: .bassEnergyDev)
        try container.encode(otherEnergyRel, forKey: .otherEnergyRel)
        try container.encode(otherEnergyDev, forKey: .otherEnergyDev)
        try container.encode(vocalsOnsetRate, forKey: .vocalsOnsetRate)
        try container.encode(vocalsCentroid, forKey: .vocalsCentroid)
        try container.encode(vocalsAttackRatio, forKey: .vocalsAttackRatio)
        try container.encode(vocalsEnergySlope, forKey: .vocalsEnergySlope)
        try container.encode(drumsOnsetRate, forKey: .drumsOnsetRate)
        try container.encode(drumsCentroid, forKey: .drumsCentroid)
        try container.encode(drumsAttackRatio, forKey: .drumsAttackRatio)
        try container.encode(drumsEnergySlope, forKey: .drumsEnergySlope)
        try container.encode(bassOnsetRate, forKey: .bassOnsetRate)
        try container.encode(bassCentroid, forKey: .bassCentroid)
        try container.encode(bassAttackRatio, forKey: .bassAttackRatio)
        try container.encode(bassEnergySlope, forKey: .bassEnergySlope)
        try container.encode(otherOnsetRate, forKey: .otherOnsetRate)
        try container.encode(otherCentroid, forKey: .otherCentroid)
        try container.encode(otherAttackRatio, forKey: .otherAttackRatio)
        try container.encode(otherEnergySlope, forKey: .otherEnergySlope)
        try container.encode(vocalsPitchHz, forKey: .vocalsPitchHz)
        try container.encode(vocalsPitchConfidence, forKey: .vocalsPitchConfidence)
        try container.encode(drumsEnergyDevSmoothed, forKey: .drumsEnergyDevSmoothed)
        try container.encode(cachedBassProportion, forKey: .cachedBassProportion)
    }
}
