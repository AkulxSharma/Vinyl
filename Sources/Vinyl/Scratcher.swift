import AVFoundation

/// Synthesised turntable scratch.
///
/// Vinyl can't touch the player's actual audio, so scratching plays a short built-in
/// sample (a formant "ahh" plus a kick) through a variable-speed reader. The read speed
/// follows how fast, and which way, your hand moves the record: 1.0 is normal playback,
/// negative plays backwards, 0 is silent. That is what gives the real back-and-forth sound.
final class Scratcher {
    static let shared = Scratcher()

    private let engine = AVAudioEngine()
    private let sampleRate: Double = 44100
    private var sample: [Float] = []
    private var source: AVAudioSourceNode!
    private var stopWork: DispatchWorkItem?

    // Read by the audio thread. Plain Float writes are fine for this purpose.
    private var targetRate: Float = 0
    private var rate: Float = 0
    private var position: Double = 0

    private init() {
        sample = Self.makeSample(sampleRate: sampleRate)
        let count = Double(sample.count)
        source = AVAudioSourceNode { [unowned self] _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                // Smooth toward the hand's speed so jerky mouse events don't click.
                self.rate += (self.targetRate - self.rate) * 0.0025
                self.position += Double(self.rate)
                if self.position < 0 { self.position += count }
                if self.position >= count { self.position -= count }
                let i = Int(self.position)
                let frac = Float(self.position - Double(i))
                let a = self.sample[i], b = self.sample[(i + 1) % self.sample.count]
                let gain = min(abs(self.rate), 1.4) * 0.9
                let value = (a + (b - a) * frac) * gain
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            return noErr
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }

    func begin() {
        stopWork?.cancel()
        targetRate = 0
        if !engine.isRunning { try? engine.start() }
    }

    /// `rate` is playback speed relative to normal (33⅓ rpm = 1.0); negative is backwards.
    func set(rate: Float) {
        targetRate = max(-4, min(4, rate))
    }

    func end() {
        targetRate = 0
        let work = DispatchWorkItem { [weak self] in self?.engine.stop() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Builds ~1.2 s of source material: a sung "ahh" (sawtooth through three vowel
    /// formants) followed by a short kick drum, then a breath of silence.
    private static func makeSample(sampleRate sr: Double) -> [Float] {
        let voiceLen = Int(sr * 0.75), kickLen = Int(sr * 0.25), gapLen = Int(sr * 0.2)
        var out = [Float](repeating: 0, count: voiceLen + kickLen + gapLen)

        func resonator(_ input: [Float], freq: Double, bandwidth: Double) -> [Float] {
            let r = exp(-Double.pi * bandwidth / sr)
            let b1 = -2 * r * cos(2 * Double.pi * freq / sr), b2 = r * r
            var y1 = 0.0, y2 = 0.0
            return input.map { x in
                let y = (1 - r) * Double(x) - b1 * y1 - b2 * y2
                y2 = y1; y1 = y
                return Float(y)
            }
        }

        var saw = [Float](repeating: 0, count: voiceLen)
        var phase = 0.0
        for n in 0..<voiceLen {
            let t = Double(n) / sr
            let f0 = 150 - 30 * t / 0.75
            phase += f0 / sr
            if phase >= 1 { phase -= 1 }
            let env = min(1, t / 0.02) * min(1, (0.75 - t) / 0.08)
            saw[n] = Float((2 * phase - 1) * env)
        }
        let f1 = resonator(saw, freq: 750, bandwidth: 90)
        let f2 = resonator(saw, freq: 1200, bandwidth: 110)
        let f3 = resonator(saw, freq: 2600, bandwidth: 160)
        for n in 0..<voiceLen { out[n] = f1[n] + 0.6 * f2[n] + 0.3 * f3[n] }

        var kp = 0.0
        for n in 0..<kickLen {
            let t = Double(n) / sr
            kp += (50 + 120 * exp(-t * 30)) / sr
            out[voiceLen + n] = Float(sin(2 * Double.pi * kp) * exp(-t * 14))
        }

        let peak = out.map(abs).max() ?? 1
        return out.map { $0 / max(peak, 0.0001) * 0.85 }
    }
}
