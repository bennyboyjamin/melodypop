import Foundation

public struct PitchEstimate: Equatable, Sendable {
    /// Hz, or 0 when no periodic signal was found.
    public var frequency: Double
    /// 0...1 (1 − YIN aperiodicity at the chosen lag).
    public var confidence: Double
    /// Root-mean-square level of the analysis window.
    public var rms: Double

    public var midiValue: Double? { frequency > 0 ? Pitch.midiValue(forFrequency: frequency) : nil }
    public var nearestPitch: Pitch? { midiValue.map { Pitch(Int(($0).rounded())) } }
    /// Deviation from the nearest equal-tempered pitch, in cents.
    public var centsOff: Double? { midiValue.map { ($0 - $0.rounded()) * 100 } }
}

/// Monophonic fundamental-frequency estimator implementing YIN
/// (de Cheveigné & Kawahara, 2002) with an FFT-based difference function.
///
/// Designed for single-note practice on an acoustic piano. It reports one pitch per frame;
/// when several notes sound at once it usually reports the strongest or lowest one, so the
/// app never uses it to grade chords.
public final class PitchTracker {
    public let sampleRate: Double
    public let windowSize: Int
    public let minLag: Int
    public let maxLag: Int
    /// Number of input samples `analyze` expects (window + max lag).
    public let frameLength: Int
    public var threshold: Double = 0.15

    private let fft: FFT
    private var aRe: [Double], aIm: [Double], bRe: [Double], bIm: [Double]
    private var energy: [Double]
    private var cmnd: [Double]

    /// Default range C2 (65 Hz) to C7 (2093 Hz) covers every MelodyPop lesson with margin.
    public init(sampleRate: Double, minFrequency: Double = 60, maxFrequency: Double = 2200, windowSize: Int = 2048) {
        self.sampleRate = sampleRate
        self.windowSize = windowSize
        minLag = max(2, Int(sampleRate / maxFrequency))
        maxLag = Int(sampleRate / minFrequency) + 1
        frameLength = windowSize + maxLag + 1
        var n = 1
        while n < frameLength { n <<= 1 }
        fft = FFT(size: n)
        aRe = [Double](repeating: 0, count: n); aIm = aRe; bRe = aRe; bIm = aRe
        energy = [Double](repeating: 0, count: frameLength + 1)
        cmnd = [Double](repeating: 1, count: maxLag + 2)
    }

    /// Analyzes the most recent `frameLength` samples of `samples`.
    public func analyze(_ samples: [Float]) -> PitchEstimate {
        guard samples.count >= frameLength else { return PitchEstimate(frequency: 0, confidence: 0, rms: 0) }
        let offset = samples.count - frameLength
        let n = fft.size
        let W = windowSize

        // Cumulative energy for fast e(τ) = Σ_{j=τ}^{τ+W-1} x².
        energy[0] = 0
        for i in 0..<frameLength {
            let v = Double(samples[offset + i])
            energy[i + 1] = energy[i] + v * v
        }
        let e0 = energy[W]
        let rms = (e0 / Double(W)).squareRoot()
        if e0 < 1e-9 { return PitchEstimate(frequency: 0, confidence: 0, rms: rms) }

        // r(τ) = Σ_{j<W} x[j]·x[j+τ] via FFT cross-correlation.
        for i in 0..<n {
            aRe[i] = i < W ? Double(samples[offset + i]) : 0
            bRe[i] = i < frameLength ? Double(samples[offset + i]) : 0
            aIm[i] = 0; bIm[i] = 0
        }
        fft.transform(real: &aRe, imag: &aIm)
        fft.transform(real: &bRe, imag: &bIm)
        for i in 0..<n { // conj(A)·B
            let r = aRe[i] * bRe[i] + aIm[i] * bIm[i]
            let im = aRe[i] * bIm[i] - aIm[i] * bRe[i]
            aRe[i] = r; aIm[i] = im
        }
        fft.transform(real: &aRe, imag: &aIm, inverse: true)
        let scale = 1 / Double(n)

        // Cumulative mean normalized difference d'(τ).
        cmnd[0] = 1
        var running = 0.0
        for tau in 1...maxLag {
            let eTau = energy[tau + W] - energy[tau]
            let d = max(0, e0 + eTau - 2 * aRe[tau] * scale)
            running += d
            cmnd[tau] = running > 0 ? d * Double(tau) / running : 1
        }

        // First dip below threshold, then walk to its local minimum.
        var best = -1
        var tau = minLag
        while tau <= maxLag {
            if cmnd[tau] < threshold {
                while tau + 1 <= maxLag && cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                best = tau
                break
            }
            tau += 1
        }
        if best < 0 {
            // No confident dip: report the global minimum with its (low) confidence.
            var minVal = Double.infinity
            for t in minLag...maxLag where cmnd[t] < minVal { minVal = cmnd[t]; best = t }
        }
        guard best > 0 else { return PitchEstimate(frequency: 0, confidence: 0, rms: rms) }

        // Parabolic interpolation for sub-sample lag.
        var refined = Double(best)
        if best > minLag && best < maxLag {
            let s0 = cmnd[best - 1], s1 = cmnd[best], s2 = cmnd[best + 1]
            let denom = s0 - 2 * s1 + s2
            if abs(denom) > 1e-12 { refined += 0.5 * (s0 - s2) / denom }
        }
        let confidence = max(0, min(1, 1 - cmnd[best]))
        return PitchEstimate(frequency: sampleRate / refined, confidence: confidence, rms: rms)
    }
}
