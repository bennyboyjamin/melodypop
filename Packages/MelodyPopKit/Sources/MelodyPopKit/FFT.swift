import Foundation

/// Small iterative radix-2 complex FFT in pure Swift, used by the pitch tracker.
/// Pure Swift keeps the analysis code testable everywhere; at 4096 points it costs well under 1 ms on device.
public final class FFT {
    public let size: Int
    private let log2n: Int
    private let cosTable: [Double]
    private let sinTable: [Double]
    private let bitReverse: [Int]

    public init(size: Int) {
        precondition(size > 1 && size & (size - 1) == 0, "FFT size must be a power of two")
        self.size = size
        var l = 0
        while (1 << l) < size { l += 1 }
        log2n = l
        cosTable = (0..<size / 2).map { cos(-2 * Double.pi * Double($0) / Double(size)) }
        sinTable = (0..<size / 2).map { sin(-2 * Double.pi * Double($0) / Double(size)) }
        bitReverse = (0..<size).map { i in
            var r = 0, x = i
            for _ in 0..<l { r = (r << 1) | (x & 1); x >>= 1 }
            return r
        }
    }

    /// In-place transform. `inverse` computes the unscaled inverse (caller divides by `size`).
    public func transform(real re: inout [Double], imag im: inout [Double], inverse: Bool = false) {
        precondition(re.count == size && im.count == size)
        for i in 0..<size {
            let j = bitReverse[i]
            if j > i { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var len = 2
        while len <= size {
            let half = len / 2
            let step = size / len
            var start = 0
            while start < size {
                for k in 0..<half {
                    let wr = cosTable[k * step]
                    let wi = inverse ? -sinTable[k * step] : sinTable[k * step]
                    let a = start + k, b = a + half
                    let tr = re[b] * wr - im[b] * wi
                    let ti = re[b] * wi + im[b] * wr
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] += tr; im[a] += ti
                }
                start += len
            }
            len <<= 1
        }
    }
}
