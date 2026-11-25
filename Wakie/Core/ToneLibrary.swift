//
//  ToneLibrary.swift
//  Wakie
//
//  Wakie's own free sounds: four alarm tones and four dance tracks, synthesized in code
//  the first time the app runs. They're original, so there are no copyright concerns.
//  Alarm tones go in Library/Sounds (where AlarmKit looks); dance tracks go with the
//  other dance music. Built-in files start with "builtin-" so they're never listed or
//  deleted as imported songs.
//

import AVFoundation
import Foundation

nonisolated enum ToneLibrary {
    struct Tone: Identifiable, Hashable, Sendable {
        let file: String
        let title: String
        let subtitle: String
        var id: String { file }
    }

    static let builtInPrefix = "builtin-"

    /// The loud default alarm sound, used when no other sound is picked.
    static let defaultAlarmFile = "builtin-wakie-rise.caf"

    static let alarmTones: [Tone] = [
        Tone(file: defaultAlarmFile, title: "Wakie Rise", subtitle: "Loud rising arpeggio · default"),
        Tone(file: "builtin-rooster-rush.caf", title: "Rooster Rush", subtitle: "Classic beep-beep-beep"),
        Tone(file: "builtin-sunny-bells.caf", title: "Sunny Bells", subtitle: "Bright chiming bells"),
        Tone(file: "builtin-marimba-morning.caf", title: "Marimba Morning", subtitle: "Bouncy marimba tune"),
    ]

    static let danceTracks: [Tone] = [
        Tone(file: "builtin-bouncy-beat.caf", title: "Bouncy Beat", subtitle: "120 BPM pop groove"),
        Tone(file: "builtin-disco-dash.caf", title: "Disco Dash", subtitle: "128 BPM disco"),
        Tone(file: "builtin-funky-wobble.caf", title: "Funky Wobble", subtitle: "100 BPM funk"),
        Tone(file: "builtin-jump-jam.caf", title: "Jump Jam", subtitle: "140 BPM high energy"),
    ]

    static func isBuiltIn(_ file: String) -> Bool { file.hasPrefix(builtInPrefix) }

    static func title(forFile file: String) -> String? {
        (alarmTones + danceTracks).first { $0.file == file }?.title
    }

    /// Bump when the sounds change so existing installs regenerate them.
    private static let version = 1
    private static let versionKey = "toneLibraryVersion"

    /// Writes any missing built-in sounds. Cheap when they already exist.
    static func ensureGenerated() {
        let defaults = UserDefaults.standard
        let regenerate = defaults.integer(forKey: versionKey) != version
        for tone in alarmTones {
            write(tone, in: AudioImporter.alarmSoundsDirectory, regenerate: regenerate)
        }
        for tone in danceTracks {
            write(tone, in: AudioImporter.danceMusicDirectory, regenerate: regenerate)
        }
        defaults.set(version, forKey: versionKey)
    }

    private static func write(_ tone: Tone, in directory: URL, regenerate: Bool) {
        let url = directory.appending(path: tone.file)
        guard regenerate || !FileManager.default.fileExists(atPath: url.path()) else { return }
        let samples = render(tone.file)
        do {
            try save(samples, to: url)
        } catch {
            print("Couldn't write \(tone.file): \(error)")
        }
    }

    // MARK: - Rendering

    private static let sampleRate = 44_100.0

    private static func render(_ file: String) -> [Float] {
        switch file {
        case "builtin-rooster-rush.caf": roosterRush()
        case "builtin-sunny-bells.caf": sunnyBells()
        case "builtin-marimba-morning.caf": marimbaMorning()
        case "builtin-bouncy-beat.caf":
            dance(bpm: 120, roots: [48, 48, 53, 55],
                  lead: [72, nil, 76, 79, nil, 76, 74, nil, 72, nil, 74, 76, 79, nil, 77, 76], voice: .square)
        case "builtin-disco-dash.caf":
            dance(bpm: 128, roots: [45, 45, 50, 52], octaveBass: true,
                  lead: [81, nil, 79, 76, nil, 76, 79, 81, 84, nil, 81, 79, 76, nil, 74, 76], voice: .pluck)
        case "builtin-funky-wobble.caf":
            dance(bpm: 100, roots: [43, 43, 46, 48],
                  lead: [67, nil, nil, 70, nil, 72, nil, 70, 67, nil, 65, nil, 67, nil, nil, nil], voice: .square)
        case "builtin-jump-jam.caf":
            dance(bpm: 140, roots: [50, 50, 46, 48], octaveBass: true,
                  lead: [74, 77, 81, 77, 74, 77, 81, 86, 84, 81, 77, 81, 84, 81, 77, 74], voice: .pluck)
        default: wakieRise()
        }
    }

    /// Alarm tones fill almost the full 30 seconds AlarmKit allows, so they never fall quiet.
    private static let alarmLength = 29.0

    private static func wakieRise() -> [Float] {
        var out = [Float](repeating: 0, count: Int(alarmLength * sampleRate))
        let pattern = [72, 76, 79, 84, 79, 76, 72, 76, 74, 77, 81, 86, 81, 77, 74, 77]
        let step = 60.0 / 150 / 2 // eighth notes at 150 BPM
        var t = 0.0, i = 0
        while t < alarmLength - step {
            // Grows from a little quieter to full volume over the first few seconds.
            let ramp = min(1, 0.55 + t / 8)
            add(.square, midi: pattern[i % pattern.count], at: t, length: step * 0.85, gain: 0.5 * ramp, into: &out)
            add(.square, midi: pattern[i % pattern.count] + 12, at: t, length: step * 0.85, gain: 0.18 * ramp, into: &out)
            t += step; i += 1
        }
        return finish(out)
    }

    private static func roosterRush() -> [Float] {
        var out = [Float](repeating: 0, count: Int(alarmLength * sampleRate))
        var t = 0.0, cycle = 0
        while t < alarmLength - 1 {
            let pitch = cycle.isMultiple(of: 2) ? 96 : 100 // C7 / E7: piercing, easy to hear
            for _ in 0..<4 {
                add(.beep, midi: pitch, at: t, length: 0.11, gain: 0.7, into: &out)
                t += 0.17
            }
            t += 0.35; cycle += 1
        }
        return finish(out)
    }

    private static func sunnyBells() -> [Float] {
        var out = [Float](repeating: 0, count: Int(alarmLength * sampleRate))
        let melody = [76, 79, 84, 83, 79, 76, 74, 76, 72, 76, 79, 77, 76, 74, 72, 79]
        let beat = 60.0 / 104
        var t = 0.0, i = 0
        while t < alarmLength - beat {
            add(.bell, midi: melody[i % melody.count], at: t, length: beat * 1.8, gain: 0.55, into: &out)
            if i % 4 == 0 { add(.bell, midi: melody[i % melody.count] - 12, at: t, length: beat * 3, gain: 0.3, into: &out) }
            t += beat; i += 1
        }
        return finish(out)
    }

    private static func marimbaMorning() -> [Float] {
        var out = [Float](repeating: 0, count: Int(alarmLength * sampleRate))
        let melody = [67, 71, 74, 79, 74, 71, 69, 72, 76, 81, 76, 72, 65, 69, 72, 77, 72, 69, 67, 71, 74, 79, 83, 86]
        let step = 60.0 / 126 / 2
        var t = 0.0, i = 0
        while t < alarmLength - step {
            add(.marimba, midi: melody[i % melody.count], at: t, length: step * 2.5, gain: 0.65, into: &out)
            t += step; i += 1
        }
        return finish(out)
    }

    /// A short looping dance groove: kick, hats, snare, bass and a lead line.
    private static func dance(bpm: Double, roots: [Int], octaveBass: Bool = false, lead: [Int?], voice: Voice) -> [Float] {
        let beat = 60.0 / bpm
        let bars = max(4, Int((16 / (beat * 4)).rounded()))
        let length = Double(bars) * beat * 4
        var out = [Float](repeating: 0, count: Int(length * sampleRate) + 1)
        for bar in 0..<bars {
            let barStart = Double(bar) * beat * 4
            let root = roots[bar % roots.count]
            for b in 0..<4 {
                let t = barStart + Double(b) * beat
                kick(at: t, into: &out)
                if b == 1 || b == 3 { snare(at: t, into: &out) }
                hat(at: t + beat / 2, into: &out)
            }
            for e in 0..<8 {
                let t = barStart + Double(e) * beat / 2
                let note = octaveBass && e.isMultiple(of: 2) == false ? root + 12 : root
                add(.bass, midi: note, at: t, length: beat / 2 * 0.9, gain: 0.45, into: &out)
            }
            // The lead pattern covers two bars (16 eighth notes).
            for e in 0..<8 {
                guard let note = lead[(bar % 2) * 8 + e] else { continue }
                add(voice, midi: note, at: barStart + Double(e) * beat / 2, length: beat / 2 * 0.95, gain: 0.3, into: &out)
            }
        }
        return finish(out)
    }

    // MARK: - Instruments

    private enum Voice { case square, beep, bell, marimba, bass, pluck }

    private static func frequency(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    private static func add(_ voice: Voice, midi: Int, at start: Double, length: Double, gain: Double, into out: inout [Float]) {
        let f = frequency(midi)
        let first = Int(start * sampleRate)
        let count = Int(length * sampleRate)
        for n in 0..<count {
            let index = first + n
            guard index < out.count else { break }
            let t = Double(n) / sampleRate
            let p = 2 * Double.pi * f * t
            let value: Double
            switch voice {
            case .square:
                // Odd harmonics give a bright, cutting tone; short fades avoid clicks.
                value = (sin(p) + sin(3 * p) / 3 + sin(5 * p) / 5) * fade(t, length, attack: 0.004, release: 0.02)
            case .beep:
                value = (sin(p) + 0.3 * sin(2 * p)) * fade(t, length, attack: 0.003, release: 0.01)
            case .bell:
                value = (sin(p) + 0.5 * sin(2.76 * p) + 0.25 * sin(5.4 * p)) * exp(-t * 3) * fade(t, length, attack: 0.002, release: 0.05)
            case .marimba:
                value = (sin(p) + 0.35 * sin(4 * p) * exp(-t * 30)) * exp(-t * 7) * fade(t, length, attack: 0.002, release: 0.03)
            case .bass:
                value = (sin(p) + 0.4 * sin(2 * p) + 0.15 * sin(3 * p)) * exp(-t * 4) * fade(t, length, attack: 0.005, release: 0.02)
            case .pluck:
                value = (sin(p) + 0.6 * sin(2 * p) + 0.3 * sin(3 * p)) * exp(-t * 9) * fade(t, length, attack: 0.002, release: 0.02)
            }
            out[index] += Float(value * gain)
        }
    }

    private static func fade(_ t: Double, _ length: Double, attack: Double, release: Double) -> Double {
        min(1, t / attack, max(0, (length - t) / release))
    }

    private static func kick(at start: Double, into out: inout [Float]) {
        let first = Int(start * sampleRate)
        var phase = 0.0
        for n in 0..<Int(0.25 * sampleRate) {
            let index = first + n
            guard index < out.count else { break }
            let t = Double(n) / sampleRate
            let f = 50 + 110 * exp(-t * 30) // pitch drop gives the thump
            phase += 2 * .pi * f / sampleRate
            out[index] += Float(sin(phase) * exp(-t * 12) * 0.9)
        }
    }

    private static func snare(at start: Double, into out: inout [Float]) {
        let first = Int(start * sampleRate)
        var noise = Noise(seed: UInt64(first))
        for n in 0..<Int(0.18 * sampleRate) {
            let index = first + n
            guard index < out.count else { break }
            let t = Double(n) / sampleRate
            out[index] += Float((noise.next() * 0.5 + sin(2 * .pi * 185 * t) * 0.3) * exp(-t * 22))
        }
    }

    private static func hat(at start: Double, into out: inout [Float]) {
        let first = Int(start * sampleRate)
        var noise = Noise(seed: UInt64(first) &+ 99)
        var previous = 0.0
        for n in 0..<Int(0.05 * sampleRate) {
            let index = first + n
            guard index < out.count else { break }
            let t = Double(n) / sampleRate
            let white = noise.next()
            let bright = white - previous // crude high-pass for a crisp hat
            previous = white
            out[index] += Float(bright * 0.22 * exp(-t * 70))
        }
    }

    /// Deterministic noise, so the files come out the same every time.
    private struct Noise {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1 }
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(Int64(bitPattern: state >> 11 << 11)) / Double(Int64.max)
        }
    }

    /// Normalizes to near full scale with gentle saturation, so every sound is as loud as possible.
    private static func finish(_ samples: [Float]) -> [Float] {
        let peak = samples.map(abs).max() ?? 1
        guard peak > 0 else { return samples }
        let drive: Float = 1.6
        let norm = tanh(drive)
        return samples.map { tanh($0 / peak * drive) / norm * 0.97 }
    }

    private static func save(_ samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { throw CocoaError(.fileWriteUnknown) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }
}
