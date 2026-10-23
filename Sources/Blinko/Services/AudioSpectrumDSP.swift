import Accelerate
import Foundation

/// Real-FFT power spectrum of the most recent audio window (vDSP, Hann window).
/// Runs on the main thread at display-link rate, never on the audio thread. All buffers
/// are allocated once; `analyze` does no allocation.
final class SpectrumAnalyzer {
    let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imag: [Float]
    /// Power per bin (index 0..<size/2), scaled so the bins of a sine of amplitude A sum
    /// to ≈ A² (a full-scale sine reads 0 dB).
    private(set) var power: [Float]
    /// Peak absolute sample of the last window (0 = digital silence).
    private(set) var peak: Float = 0

    init(size: Int = 2048) {
        precondition(size > 0 && size & (size - 1) == 0, "FFT size must be a power of two")
        self.size = size
        log2n = vDSP_Length(log2(Double(size)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        windowed = [Float](repeating: 0, count: size)
        real = [Float](repeating: 0, count: size / 2)
        imag = [Float](repeating: 0, count: size / 2)
        power = [Float](repeating: 0, count: size / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// `samples` must hold `size` mono samples, oldest first.
    func analyze(_ samples: UnsafePointer<Float>) {
        let n = vDSP_Length(size)
        vDSP_maxmgv(samples, 1, &peak, n)
        guard peak > 0 else {
            vDSP_vclr(&power, 1, vDSP_Length(size / 2))
            return
        }
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, n)
        let half = size / 2
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                windowed.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // Nyquist is packed into imag[0]; drop it and DC (neither is drawn).
                im[0] = 0
                re[0] = 0
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        // Measured calibration (zrip's 2× output, Hann gain and its 1.5-bin leakage):
        // dividing the squared magnitudes by N² makes a tone's bins sum to A².
        var scale = 1 / Float(size * size)
        vDSP_vsmul(power, 1, &scale, &power, 1, vDSP_Length(half))
    }
}

/// Maps an FFT power spectrum to `count` log-spaced bands with a noise gate, adaptive
/// normalisation and attack/decay smoothing. One per view (bar count), cheap to update.
struct SpectrumBands {
    let count: Int
    /// First and last bin of each band (inclusive), for the analyzer's size and sample rate.
    private(set) var ranges: [ClosedRange<Int>] = []
    /// Smoothed, normalised levels 0…1 — what the bars draw.
    private(set) var levels: [Float]
    private var targets: [Float]
    /// Adaptive ceiling (dB): follows the loudest band up at once, relaxes slowly.
    private(set) var ceiling: Float = -24
    private var configured: (bins: Int, sampleRate: Double) = (0, 0)

    static let lowHz = 45.0
    static let highHz = 16_000.0
    /// Dynamic range shown, below the adaptive ceiling.
    static let range: Float = 42
    /// Below this window peak (≈ −66 dBFS) the input counts as silence.
    static let gate: Float = 0.0005
    static let attack = 0.035   // seconds (time constant)
    static let decay = 0.20

    init(count: Int) {
        self.count = count
        levels = [Float](repeating: 0, count: count)
        targets = levels
    }

    /// Log-spaced band edges between `lowHz` and `highHz` (clamped below Nyquist), each at
    /// least one bin wide and never overlapping the previous band's first bin.
    static func bandRanges(count: Int, bins: Int, sampleRate: Double) -> [ClosedRange<Int>] {
        let binHz = sampleRate / Double(bins * 2)
        let high = min(highHz, sampleRate / 2 * 0.95)
        let ratio = pow(high / lowHz, 1 / Double(count))
        var result: [ClosedRange<Int>] = []
        var lower = max(1, Int((lowHz / binHz).rounded()))
        for i in 1...count {
            let edge = lowHz * pow(ratio, Double(i))
            var upper = min(bins - 1, Int((edge / binHz).rounded()) - 1)
            upper = max(upper, lower)
            result.append(lower...upper)
            lower = min(bins - 1, upper + 1)
        }
        return result
    }

    /// Updates the targets from a fresh spectrum (`power` has `bins` entries).
    mutating func ingest(power: UnsafeBufferPointer<Float>, peak: Float, sampleRate: Double, dt: Double) {
        guard peak >= Self.gate, power.count > count else {
            for i in 0..<count { targets[i] = 0 }
            ceiling = max(-24, ceiling - Float(dt) * 6)
            return
        }
        if configured.bins != power.count || configured.sampleRate != sampleRate {
            ranges = Self.bandRanges(count: count, bins: power.count, sampleRate: sampleRate)
            configured = (power.count, sampleRate)
        }
        var loudest: Float = -120
        for (i, r) in ranges.enumerated() {
            // Summed power: pink-ish music then reads evenly across log-spaced bands.
            var sum: Float = 0
            for b in r { sum += power[b] }
            let db = 10 * log10(sum + 1e-12)
            targets[i] = db
            loudest = max(loudest, db)
        }
        // Follow peaks up immediately, relax 6 dB/s; never louder than full scale, never
        // so low that faint noise fills the bars.
        ceiling = min(0, max(-30, max(loudest, ceiling - Float(dt) * 6)))
        let floor = ceiling - Self.range
        for i in 0..<count {
            let x = min(max((targets[i] - floor) / Self.range, 0), 1)
            targets[i] = x * x // ease-in: quiet bands stay low, peaks pop
        }
    }

    /// Moves `levels` toward the targets; frame-rate independent.
    mutating func smooth(dt: Double) {
        let up = Float(1 - exp(-dt / Self.attack))
        let down = Float(1 - exp(-dt / Self.decay))
        for i in 0..<count {
            let t = targets[i]
            let l = levels[i]
            levels[i] = l + (t - l) * (t > l ? up : down)
        }
    }

    var isSettled: Bool { levels.allSatisfy { $0 < 0.002 } && targets.allSatisfy { $0 == 0 } }

    mutating func reset() {
        for i in 0..<count { levels[i] = 0; targets[i] = 0 }
    }
}

/// Single-producer / single-consumer ring of mono Float samples. The audio IOProc writes
/// with plain stores (no locks, no allocation); the reader copies the newest window.
/// A read racing a write can only blend two adjacent windows for one frame, which a
/// visualizer cannot show, so no barrier is needed beyond aligned word stores.
final class AudioSampleRing: @unchecked Sendable {
    let capacity: Int
    private let mask: Int
    let samples: UnsafeMutablePointer<Float>
    /// Total frames ever written (monotonic). Aligned Int store: atomic on arm64/x86_64.
    let written: UnsafeMutablePointer<Int>

    init(capacity: Int = 8192) {
        precondition(capacity & (capacity - 1) == 0)
        self.capacity = capacity
        mask = capacity - 1
        samples = .allocate(capacity: capacity)
        samples.initialize(repeating: 0, count: capacity)
        written = .allocate(capacity: 1)
        written.initialize(to: 0)
    }

    deinit {
        samples.deallocate()
        written.deallocate()
    }

    /// Audio thread. `channels` interleaved samples per frame are averaged to mono.
    @inline(__always)
    func write(_ data: UnsafePointer<Float>, frames: Int, channels: Int, stride: Int) {
        var w = written.pointee
        if channels == 1 {
            for f in 0..<frames { samples[w & mask] = data[f * stride]; w &+= 1 }
        } else {
            let scale = 1 / Float(channels)
            for f in 0..<frames {
                var s: Float = 0
                for c in 0..<channels { s += data[f * stride + c] }
                samples[w & mask] = s * scale
                w &+= 1
            }
        }
        written.pointee = w
    }

    /// Copies the newest `count` samples (oldest first) into `out`.
    func copyLatest(_ count: Int, into out: UnsafeMutablePointer<Float>) {
        let end = written.pointee
        var r = end &- count
        for i in 0..<count { out[i] = samples[r & mask]; r &+= 1 }
    }

    func clear() {
        samples.update(repeating: 0, count: capacity)
    }
}
