//
//  MissionView.swift
//  Wakie
//
//  Shared chrome for the three missions, plus the success screen.
//

import SwiftUI

struct MissionView: View {
    let run: MissionRun
    /// Called when an alarm mission (not a practice run) is finished.
    var onFinish: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var mission: Mission
    @State private var isComplete = false

    init(run: MissionRun, onFinish: (() -> Void)? = nil) {
        self.run = run
        self.onFinish = onFinish
        _mission = State(initialValue: run.mission)
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 18) {
                header
                content
                    .id(mission)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            if isComplete {
                MissionSuccessView(mission: mission, isPractice: run.isPractice) {
                    if run.isPractice {
                        dismiss()
                    } else {
                        onFinish?()
                    }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.45), value: isComplete)
        .sensoryFeedback(.success, trigger: isComplete)
    }

    private var header: some View {
        ZStack {
            BannerTitle(text: mission.title, color: mission.bannerColor)
            HStack {
                if run.isPractice {
                    CircleIconButton(systemName: "chevron.left") { dismiss() }
                        .accessibilityLabel("Back")
                }
                Spacer()
                SparkleLines(size: 28)
                    .rotationEffect(.degrees(50))
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        let complete = { isComplete = true }
        let fallback = { withAnimation { mission = .blahBlah } }
        switch mission {
        case .shakyShaky:
            ShakyShakyView(seconds: model.danceSeconds, songURL: model.danceSongURL, appleMusicSong: model.danceAppleMusicSong,
                           onComplete: complete, onFallback: fallback)
        case .pickiePicky:
            PickiePickyView(item: model.randomPickItem(), onComplete: complete, onFallback: fallback)
        case .blahBlah:
            BlahBlahView(seconds: model.talkSeconds, onComplete: complete)
        }
    }
}

struct MissionSuccessView: View {
    let mission: Mission
    let isPractice: Bool
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                MascotImage(mission: mission, size: 150)
                Text(isPractice ? "Nailed it!" : "You're awake!")
                    .font(.wakie(34, .black))
                    .foregroundStyle(Theme.ink)
                Text(isPractice ? "That's how it'll work when your alarm rings." : "Alarm off. Go have a great day.")
                    .font(.wakie(15, .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                Button(action: onDone) {
                    Text("Done")
                        .font(.wakie(18, .heavy))
                        .foregroundStyle(Color(hex: 0x1E1A3C))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(Theme.yellow))
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 6)
            }
            .padding(28)
            .wakieCard(radius: 36)
            .padding(.horizontal, 30)
        }
    }
}

/// Circular progress ring with a "10 / 15" style counter, as in the design.
struct ProgressRing: View {
    let value: Double
    let total: Double
    var size: CGFloat = 150

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.timeBox.opacity(0.85), lineWidth: 16)
            Circle()
                .trim(from: 0, to: total > 0 ? min(value / total, 1) : 0)
                .stroke(Theme.yellow, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: value)
            VStack(spacing: -4) {
                Text("\(Int(value))")
                    .font(.wakie(size * 0.3, .black))
                    .contentTransition(.numericText())
                Text("/\(Int(total))")
                    .font(.wakie(size * 0.15, .heavy))
            }
            .foregroundStyle(Theme.ink)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(Int(value)) of \(Int(total)) seconds")
    }
}

#Preview("Shaky-Shaky") {
    MissionView(run: MissionRun(mission: .shakyShaky, isPractice: true))
        .environment(AppModel.shared)
}

#Preview("Pickie-Picky") {
    MissionView(run: MissionRun(mission: .pickiePicky, isPractice: true))
        .environment(AppModel.shared)
}

#Preview("Blah-Blah") {
    MissionView(run: MissionRun(mission: .blahBlah, isPractice: true))
        .environment(AppModel.shared)
}
