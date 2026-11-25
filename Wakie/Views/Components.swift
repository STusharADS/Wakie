//
//  Components.swift
//  Wakie
//

import SwiftUI

/// Mission mascot artwork. The source images have generous transparent padding,
/// so the figure is scaled up to fill a `size × size` box (overflow is allowed).
struct MascotImage: View {
    let mission: Mission
    var size: CGFloat = 60

    var body: some View {
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                Image(mission.mascot)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 2.0 * artScale, height: size * 1.25 * artScale)
            }
            .accessibilityHidden(true)
    }

    /// The artwork has different amounts of padding, so each mascot gets its own boost.
    /// Shaky-Shaky's music notes make the figure itself read smaller, so it gets more.
    private var artScale: CGFloat {
        switch mission {
        case .shakyShaky: 1.35
        case .pickiePicky, .blahBlah: 1.12
        }
    }
}

/// Section label used above groups of controls ("Repeat", "Challenge").
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.wakie(15, .bold))
            .foregroundStyle(Theme.ink)
    }
}

/// A screen title with the yellow sparkle strokes, e.g. "Alarms".
struct ScreenTitle: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(text)
                .font(.wakie(36, .black))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            SparkleLines(size: 24)
                .rotationEffect(.degrees(60))
                .offset(y: 4)
        }
    }
}

/// Selectable challenge tile used in the alarm editor.
struct MissionTile: View {
    let mission: Mission
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                MascotImage(mission: mission, size: 50)
                    .padding(.top, 6)
                Text(mission.tileTitle)
                    .font(.wakie(14, .heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? Color(hex: 0x1E1A3C) : Theme.ink)
                    .lineSpacing(-2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(LinearGradient(colors: [Theme.yellow, Theme.yellowDeep], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Theme.card))
                    .shadow(color: isSelected ? Theme.yellowDeep.opacity(0.45) : Theme.shadow, radius: 10, y: 5)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.timeBox))
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(mission.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The Edit / Done and + buttons at the top right of the Alarms and World Clock tabs.
/// Shared so both screens use identical Liquid Glass buttons at the same size and position.
struct HeaderActions: View {
    @Binding var isEditing: Bool
    var showsEdit: Bool
    let addLabel: String
    let onAdd: () -> Void

    /// One height for both buttons; the + button is a circle of the same size.
    static let height: CGFloat = 44

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if showsEdit {
                    Button {
                        withAnimation(.snappy) { isEditing.toggle() }
                    } label: {
                        Text(isEditing ? "Done" : "Edit")
                            .font(.wakie(16, .bold))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.opacity)
                            .padding(.horizontal, 18)
                            .frame(minWidth: 72)
                            .frame(height: Self.height)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(Theme.purple.opacity(0.18)).interactive(), in: .capsule)
                }
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: Self.height, height: Self.height)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.purple.opacity(0.18)).interactive(), in: .circle)
                .accessibilityLabel(addLabel)
            }
        }
    }
}

/// Fixed-height title row so header buttons land in the same spot on every tab.
struct TabHeader<Title: View>: View {
    @Binding var isEditing: Bool
    var showsEdit: Bool
    let addLabel: String
    let onAdd: () -> Void
    @ViewBuilder let title: Title

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            title
            Spacer(minLength: 8)
            HeaderActions(isEditing: $isEditing, showsEdit: showsEdit, addLabel: addLabel, onAdd: onAdd)
        }
        .frame(height: 56)
    }
}

/// Big horizontal wheel for picking a number: swipe sideways (or tap a number) to choose.
/// Used instead of thin sliders when "Easy time picking" is on in Settings.
struct HorizontalWheelPicker: View {
    let values: [Int]
    @Binding var selection: Int
    let accessibilityName: String
    var label: (Int) -> String = { "\($0)" }
    /// Called when the wheel comes to rest after being moved.
    var onSettled: (() -> Void)?

    @State private var scrolledID: Int?
    private let itemWidth: CGFloat = 84
    private let height: CGFloat = 76

    init(values: [Int], selection: Binding<Int>, accessibilityName: String,
         label: @escaping (Int) -> String = { "\($0)" }, onSettled: (() -> Void)? = nil) {
        self.values = values
        _selection = selection
        self.accessibilityName = accessibilityName
        self.label = label
        self.onSettled = onSettled
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(values, id: \.self) { value in
                        Text(label(value))
                            .font(.wakie(30, .black))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                            .frame(width: itemWidth, height: height)
                            .contentShape(Rectangle())
                            .scrollTransition(axis: .horizontal) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.35)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.72)
                            }
                            .onTapGesture { withAnimation(.snappy) { scrolledID = value } }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolledID, anchor: .center)
            .contentMargins(.horizontal, max(0, (geo.size.width - itemWidth) / 2), for: .scrollContent)
            .onScrollPhaseChange { _, phase in
                if phase == .idle { onSettled?() }
            }
        }
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.inset))
        // Highlight around the chosen number, like a selection window.
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.purple, lineWidth: 3)
                .frame(width: itemWidth, height: height - 10)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .leading) { edgeHint(systemName: "chevron.left") }
        .overlay(alignment: .trailing) { edgeHint(systemName: "chevron.right") }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Position once laid out, so the chosen value starts centred.
        .onAppear { if scrolledID == nil { scrolledID = selection } }
        .onChange(of: scrolledID) { _, newValue in
            if let newValue { selection = newValue }
        }
        .onChange(of: selection) { _, newValue in
            if scrolledID != newValue { withAnimation(.snappy) { scrolledID = newValue } }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityRepresentation {
            Picker(accessibilityName, selection: $selection) {
                ForEach(values, id: \.self) { Text(label($0)).tag($0) }
            }
        }
    }

    /// Small arrows at the ends showing the wheel moves sideways.
    private func edgeHint(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(Theme.inkSecondary.opacity(0.6))
            .padding(.horizontal, 8)
            .allowsHitTesting(false)
    }
}
