import SwiftUI

// Where each highlighted part of the Lanes window is, collected from the views.
struct TourAnchors: PreferenceKey {
    static var defaultValue: [TourSpot: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourSpot: Anchor<CGRect>], nextValue: () -> [TourSpot: Anchor<CGRect>]) { value.merge(nextValue()) { $1 } }
}
extension View {
    func tourSpot(_ spot: TourSpot) -> some View { anchorPreference(key: TourAnchors.self, value: .bounds) { [spot: $0] } }
}

// Dims the window, cuts a rounded hole around the current part, and explains it
// in a card beside it. Back, Next and Skip; Return and Escape work too.
struct TourOverlay: View {
    @ObservedObject var manager: WindowManager
    let anchors: [TourSpot: Anchor<CGRect>]
    private let cardWidth: CGFloat = 340
    var body: some View {
        GeometryReader { proxy in
            if let index = manager.tourStep, manager.tourSteps.indices.contains(index) {
                let step = manager.tourSteps[index]
                let size = proxy.size
                let target = step.spot.flatMap { anchors[$0] }.map { proxy[$0].insetBy(dx: -8, dy: -8).intersection(CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)) }
                ZStack(alignment: .topLeading) {
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: size))
                        if let r = target, !r.isNull { p.addRoundedRect(in: r, cornerSize: CGSize(width: 12, height: 12)) }
                    }
                    .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle()).onTapGesture {}
                    if let r = target, !r.isNull {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(accent, lineWidth: 2)
                            .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                            .shadow(color: accent.opacity(0.45), radius: 10)
                            .allowsHitTesting(false)
                    }
                    card(step, index: index).frame(width: cardWidth)
                        .modifier(TourPlacement(target: target, container: size, width: cardWidth))
                }
                .animation(.easeInOut(duration: 0.22), value: index)
            }
        }
    }
    func card(_ step: TourStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(index + 1) of \(manager.tourSteps.count)").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(muted)
            Text(step.title).font(.system(size: 17, weight: .semibold))
            Text(step.body).font(.system(size: 12)).foregroundStyle(ink.opacity(0.78)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if step.spot == nil { StripIllustration().padding(.vertical, 6) }
            HStack {
                Button("Skip tour") { manager.endTour() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(muted).keyboardShortcut(.cancelAction)
                Spacer()
                if index > 0 { Button("Back") { manager.tourStep = index - 1 }.font(.system(size: 11)) }
                Button(index == manager.tourSteps.count - 1 ? "Done" : "Next") {
                    if index == manager.tourSteps.count - 1 { manager.endTour() } else { manager.tourStep = index + 1 }
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(surface)
                .padding(.horizontal, 16).padding(.vertical, 7).background(accent).clipShape(Capsule())
                .keyboardShortcut(.defaultAction)
            }.padding(.top, 4)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(surface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.3)))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .foregroundStyle(ink)
    }
}

// Beside the highlighted part when there is room: below, above, right, left;
// otherwise inside its lower edge. Steps without a part are centered.
private struct TourPlacement: ViewModifier {
    let target: CGRect?
    let container: CGSize
    let width: CGFloat
    private let room: CGFloat = 230
    func body(content: Content) -> some View {
        let clampX = { (x: CGFloat) in min(max(16, x), container.width - width - 16) }
        guard let r = target, !r.isNull else {
            return AnyView(content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center))
        }
        if container.height - r.maxY > room {
            return AnyView(content.offset(x: clampX(r.midX - width / 2), y: r.maxY + 14))
        }
        if r.minY > room {
            return AnyView(content.frame(maxHeight: .infinity, alignment: .bottom).offset(x: clampX(r.midX - width / 2), y: -(container.height - r.minY + 14)))
        }
        if container.width - r.maxX > width + 32 {
            return AnyView(content.offset(x: r.maxX + 16, y: min(max(16, r.minY + 24), container.height - room)))
        }
        if r.minX > width + 32 {
            return AnyView(content.offset(x: r.minX - width - 16, y: min(max(16, r.minY + 24), container.height - room)))
        }
        return AnyView(content.frame(maxHeight: .infinity, alignment: .bottom).offset(x: clampX(r.maxX - width - 20), y: -(container.height - r.maxY + 20)))
    }
}

// A resting strip growing into its expanded form, for the step about the screen.
private struct StripIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            pill(open: false)
            pill(open: true)
        }
    }
    func pill(open: Bool) -> some View {
        let c = Color(red: 0.64, green: 0.76, blue: 0.96)
        return HStack(spacing: 6) {
            Text("≡").font(.system(size: 9)).foregroundStyle(muted)
            Image(systemName: "globe").font(.system(size: 9)).foregroundStyle(c)
            Text("Browser").font(.system(size: 10, weight: .semibold)).foregroundStyle(c)
            if open {
                ForEach(["Docs", "Mail", "Calendar"], id: \.self) { t in
                    Text(t).font(.system(size: 9, weight: t == "Docs" ? .semibold : .regular))
                        .foregroundStyle(t == "Docs" ? c : muted)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(t == "Docs" ? c.opacity(0.18) : Color.white.opacity(0.06)))
                }
                Text("‹ 1/3 ›").font(.system(size: 9, design: .monospaced)).foregroundStyle(c)
            } else {
                HStack(spacing: 3) { Capsule().fill(c).frame(width: 12, height: 4); Capsule().fill(Color.white.opacity(0.28)).frame(width: 4, height: 4); Capsule().fill(Color.white.opacity(0.28)).frame(width: 4, height: 4) }
            }
        }
        .padding(.horizontal, 10).frame(height: 24)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(c.opacity(0.3)))
    }
}
