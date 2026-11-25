//
//  ShakyShakyView.swift
//  Wakie
//
//  Dance in front of the selfie camera. Vision body-pose tracking measures how much
//  the person is moving; only time spent actually moving counts toward the goal.
//

import SwiftUI
import AVFoundation

@Observable
final class DanceTracker {
    let target: Double
    private(set) var frame: PoseFrame?
    private(set) var seconds: Double = 0
    private(set) var isMoving = false
    var isRunning = false

    private var previous: PoseFrame?
    private var energy: Double = 0
    /// When the person last moved enough to count as dancing.
    private var lastMovementTime: TimeInterval?

    /// Speed (in body-heights per second) of the fastest-moving joints needed to count as dancing.
    private let movementThreshold = 0.25
    /// Only the fastest few joints count, so moving just the arms (or just the hips) is enough.
    private let activeJointCount = 3
    /// Per-frame joint moves smaller than this (in body heights) are tracking jitter, not dancing.
    private let jitterTolerance = 0.012
    /// How long the timer keeps running through a pause in the dance.
    private let pauseGrace: TimeInterval = 1.5

    init(target: Double) {
        self.target = target
    }

    /// Forgets the last frame so switching cameras isn't counted as a huge movement.
    func resetMotion() {
        previous = nil
        frame = nil
        energy = 0
        lastMovementTime = nil
        isMoving = false
    }

    var personVisible: Bool { (frame?.joints.count ?? 0) >= 6 }
    var isComplete: Bool { seconds >= target }

    func ingest(_ newFrame: PoseFrame) {
        defer {
            frame = newFrame
            previous = newFrame
        }
        let dt = min(max(newFrame.time - (previous?.time ?? newFrame.time), 0.01), 0.3)
        guard newFrame.joints.count >= 6, let previous, previous.joints.count >= 6 else {
            // Tracking dropped for a moment: keep the timer going through the grace period.
            energy *= 0.5
            updateMoving(movedNow: false, at: newFrame.time, dt: dt)
            return
        }
        let w = newFrame.imageSize.width, h = newFrame.imageSize.height

        // Body height in pixels normalises for how far the person stands from the phone.
        let ys = newFrame.joints.values.map { $0.y * h }
        let bodyHeight = max((ys.max() ?? 0) - (ys.min() ?? 0), h * 0.15)

        // Each joint's move this frame, in body heights, ignoring tiny tracking jitter.
        var moves: [Double] = []
        for (joint, point) in newFrame.joints {
            guard let old = previous.joints[joint] else { continue }
            let move = hypot((point.x - old.x) * w, (point.y - old.y) * h) / bodyHeight
            moves.append(move > jitterTolerance ? move : 0)
        }
        guard moves.count >= 4 else { return }

        // Average only the fastest joints, so moving part of the body still counts.
        let fastest = moves.sorted(by: >).prefix(activeJointCount)
        let speed = fastest.reduce(0, +) / Double(fastest.count) / dt
        energy = energy * 0.6 + speed * 0.4
        updateMoving(movedNow: energy > movementThreshold, at: newFrame.time, dt: dt)
    }

    /// Counts the frame as dancing if the person is moving now or paused only briefly.
    private func updateMoving(movedNow: Bool, at time: TimeInterval, dt: Double) {
        if movedNow { lastMovementTime = time }
        if let lastMovementTime {
            isMoving = time - lastMovementTime <= pauseGrace
        } else {
            isMoving = false
        }
        if isRunning && isMoving {
            seconds = min(target, seconds + dt)
        }
    }
}

struct ShakyShakyView: View {
    let onComplete: () -> Void
    let onFallback: () -> Void

    @State private var camera = CameraPipeline(position: .front)
    @State private var detector = PoseDetector()
    @State private var tracker: DanceTracker
    @State private var status: CameraStatus = .starting
    @State private var device: AVCaptureDevice?
    @State private var isSwitching = false
    @State private var music = AudioPreviewPlayer()
    /// Song from Settings that plays (looping) while the person dances.
    let songURL: URL?
    /// A song from Apple Music, played through MusicKit instead of `songURL`.
    let appleMusicSong: AppleMusicSong?

    init(seconds: Int, songURL: URL?, appleMusicSong: AppleMusicSong? = nil,
         onComplete: @escaping () -> Void, onFallback: @escaping () -> Void) {
        self.appleMusicSong = appleMusicSong
        self.onComplete = onComplete
        self.onFallback = onFallback
        self.songURL = songURL
        _tracker = State(initialValue: DanceTracker(target: Double(seconds)))
    }

    var body: some View {
        VStack(spacing: 18) {
            CameraCard(camera: camera, device: device, status: status, onFallback: onFallback) {
                SkeletonOverlay(frame: tracker.frame)
                    .overlay(alignment: .topTrailing) { switchCameraButton }
            }
            .frame(maxHeight: .infinity)

            Text(statusText(tracker))
                .font(.wakie(17, .heavy))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
                .animation(.snappy, value: tracker.isMoving)

            if tracker.isRunning {
                ProgressRing(value: tracker.seconds.rounded(.down), total: tracker.target, size: 130)
            } else {
                Button {
                    tracker.isRunning = true
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(Color(hex: 0x1E1A3C))
                        .frame(width: 92, height: 92)
                        .background(Circle().fill(Theme.yellow).shadow(color: Theme.yellowDeep.opacity(0.5), radius: 12, y: 6))
                }
                .buttonStyle(PressableStyle())
                .disabled(status != .running)
                .opacity(status == .running ? 1 : 0.5)
                .accessibilityLabel("Start dancing")
                .frame(height: 130)
            }
        }
        .task {
            let tracker = tracker
            let detector = detector
            camera.frameHandler = { buffer in
                guard let frame = detector.process(buffer) else { return }
                Task { @MainActor in tracker.ingest(frame) }
            }
            (status, device) = await camera.start()
        }
        .onDisappear {
            camera.stop()
            music.stop()
            if appleMusicSong != nil { AppleMusicDance.stop() }
        }
        .onChange(of: tracker.isRunning) { _, running in
            guard running else { return }
            if let appleMusicSong {
                Task { await AppleMusicDance.play(appleMusicSong) }
            } else if let songURL {
                music.play(songURL, loops: true)
            }
        }
        .onChange(of: tracker.isComplete) { _, done in
            if done {
                camera.stop()
                music.stop()
                if appleMusicSong != nil { AppleMusicDance.stop() }
                onComplete()
            }
        }
    }

    /// Flips between the selfie and back cameras.
    @ViewBuilder
    private var switchCameraButton: some View {
        if CameraPipeline.canSwitchCameras {
            Button {
                guard !isSwitching else { return }
                isSwitching = true
                Task {
                    if let newDevice = await camera.switchCamera() {
                        tracker.resetMotion()
                        device = newDevice
                    }
                    isSwitching = false
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .rotationEffect(.degrees(isSwitching ? 180 : 0))
                    .animation(.spring(duration: 0.4), value: isSwitching)
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityLabel(device?.position == .back ? "Switch to front camera" : "Switch to back camera")
        }
    }

    private func statusText(_ tracker: DanceTracker) -> String {
        guard status == .running else { return "Prop your phone up and step back" }
        if !tracker.personVisible { return "Step back so I can see your whole body" }
        if !tracker.isRunning { return "Ready? Tap play and dance for \(Int(tracker.target)) seconds!" }
        return tracker.isMoving ? "Yes! Keep dancing 💃" : "Move it! The timer only counts while you dance"
    }
}

/// Draws the detected body skeleton over the camera preview.
struct SkeletonOverlay: View {
    let frame: PoseFrame?

    var body: some View {
        Canvas { context, size in
            guard let frame, frame.imageSize.width > 0 else { return }
            // Match the preview's aspect-fill mapping from image to view coordinates.
            let scale = max(size.width / frame.imageSize.width, size.height / frame.imageSize.height)
            let drawn = CGSize(width: frame.imageSize.width * scale, height: frame.imageSize.height * scale)
            let origin = CGPoint(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
            func map(_ p: CGPoint) -> CGPoint {
                CGPoint(x: origin.x + p.x * drawn.width, y: origin.y + (1 - p.y) * drawn.height)
            }
            for (a, b) in PoseJoint.bones {
                guard let pa = frame.joints[a], let pb = frame.joints[b] else { continue }
                var path = Path()
                path.move(to: map(pa))
                path.addLine(to: map(pb))
                context.stroke(path, with: .color(Color(hex: 0x3FE0FF)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            for point in frame.joints.values {
                let c = map(point)
                context.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(Color(hex: 0xFF5FD2)))
                context.stroke(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.white), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
