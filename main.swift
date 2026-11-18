import SwiftUI
import AVFoundation

// MARK: - Model

enum Limb: String, CaseIterable {
    case leftHand = "Left Hand"
    case rightHand = "Right Hand"
    case leftFoot = "Left Foot"
    case rightFoot = "Right Foot"

    var symbol: String {
        switch self {
        case .leftHand, .rightHand: return "hand.raised.fill"
        case .leftFoot, .rightFoot: return "shoe.fill"
        }
    }

    /// The SF Symbols point one way; flip them for the other side.
    var mirrored: Bool { self == .leftHand || self == .rightFoot }
}

enum Spot: String, CaseIterable {
    case red = "Red"
    case blue = "Blue"
    case yellow = "Yellow"
    case green = "Green"

    var color: Color {
        switch self {
        case .red: return Color(red: 0.89, green: 0.15, blue: 0.17)
        case .blue: return Color(red: 0.10, green: 0.42, blue: 0.90)
        case .yellow: return Color(red: 0.99, green: 0.82, blue: 0.10)
        case .green: return Color(red: 0.13, green: 0.68, blue: 0.30)
        }
    }

    var ink: Color { self == .yellow ? Color.black.opacity(0.8) : .white }
}

struct Move: Equatable, Identifiable {
    let id = UUID()
    let limb: Limb
    let spot: Spot

    var spoken: String { "\(limb.rawValue), \(spot.rawValue)" }

    static func == (a: Move, b: Move) -> Bool { a.limb == b.limb && a.spot == b.spot }
}

final class Game: ObservableObject {
    static let intervalRange: ClosedRange<Double> = 3...60

    @Published var current: Move?
    /// Where each limb should currently be, from the most recent call for it.
    @Published var positions: [Limb: Spot] = [:]
    @Published var isRunning = false
    @Published var remaining: Double = 10
    @Published var interval: Double {
        didSet {
            UserDefaults.standard.set(interval, forKey: "interval")
            if !isRunning || remaining > interval { remaining = interval }
        }
    }
    @Published var voiceOn: Bool {
        didSet {
            UserDefaults.standard.set(voiceOn, forKey: "voiceOn")
            if !voiceOn { synth.stopSpeaking(at: .immediate) }
        }
    }

    private let synth = AVSpeechSynthesizer()
    private var timer: Timer?
    private var lastTick = Date()

    init() {
        let saved = UserDefaults.standard.double(forKey: "interval")
        let start = Game.intervalRange.contains(saved) ? saved : 10
        interval = start
        remaining = start
        voiceOn = UserDefaults.standard.object(forKey: "voiceOn") as? Bool ?? true
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        if current == nil { callNext() }
        lastTick = Date()
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        synth.stopSpeaking(at: .immediate)
        current = nil
        positions = [:]
        remaining = interval
    }

    func callNext() {
        var next: Move
        repeat {
            next = Move(limb: Limb.allCases.randomElement()!, spot: Spot.allCases.randomElement()!)
        } while positions[next.limb] == next.spot  // always an actual change
        positions[next.limb] = next.spot
        current = next
        remaining = interval
        lastTick = Date()
        if voiceOn {
            synth.stopSpeaking(at: .immediate)
            let u = AVSpeechUtterance(string: next.spoken)
            u.rate = 0.45
            synth.speak(u)
        }
    }

    private func tick() {
        let now = Date()
        remaining -= now.timeIntervalSince(lastTick)
        lastTick = now
        if remaining <= 0 { callNext() }
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var game = Game()

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            GeometryReader { geo in
                let d = min(geo.size.width, geo.size.height)
                callout(diameter: d)
                    .frame(width: d, height: d)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            VStack(alignment: .trailing, spacing: 14) {
                Spacer(minLength: 0)
                layoutGrid
                controls
                settings
            }
            .frame(width: 290)
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 520)
        .background(
            LinearGradient(colors: [Color(white: 0.13), Color(white: 0.07)],
                           startPoint: .top, endPoint: .bottom)
        )
        .preferredColorScheme(.dark)
    }

    private func callout(diameter d: CGFloat) -> some View {
        let progress = max(0, min(1, game.remaining / game.interval))
        let ring = d * 0.035
        return ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: ring)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(game.current?.spot.color ?? Color.white.opacity(0.4),
                        style: StrokeStyle(lineWidth: ring, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(game.current?.spot.color ?? Color.white.opacity(0.08))
                .padding(ring * 1.8)
                .shadow(color: (game.current?.spot.color ?? .clear).opacity(0.5), radius: d * 0.07)

            if let move = game.current {
                VStack(spacing: d * 0.02) {
                    Image(systemName: move.limb.symbol)
                        .font(.system(size: d * 0.24))
                        .scaleEffect(x: move.limb.mirrored ? -1 : 1, y: 1)
                    Text(move.limb.rawValue.uppercased())
                        .font(.system(size: d * 0.105, weight: .heavy, design: .rounded))
                    Text(move.spot.rawValue.uppercased())
                        .font(.system(size: d * 0.07, weight: .bold, design: .rounded))
                        .opacity(0.85)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(move.spot.ink)
                .id(move.id)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                VStack(spacing: d * 0.015) {
                    Text("Ready?")
                        .font(.system(size: d * 0.105, weight: .heavy, design: .rounded))
                    Text("Press Start or hit Space")
                        .font(.system(size: max(13, d * 0.035)))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(ring / 2)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: game.current)
        .overlay(alignment: .bottom) {
            Text("\(Int(ceil(max(0, game.remaining))))")
                .font(.system(size: max(18, d * 0.05), weight: .bold, design: .rounded).monospacedDigit())
                .padding(.horizontal, d * 0.03).padding(.vertical, d * 0.008)
                .background(Capsule().fill(Color(white: 0.2)))
        }
    }

    /// Body map: hands on top, feet below, each tile showing the colour that limb is on.
    private var layoutGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) { limbTile(.leftHand); limbTile(.rightHand) }
            HStack(spacing: 8) { limbTile(.leftFoot); limbTile(.rightFoot) }
        }
    }

    private func limbTile(_ limb: Limb) -> some View {
        let spot = game.positions[limb]
        let justCalled = game.current?.limb == limb
        return VStack(spacing: 4) {
            Image(systemName: limb.symbol)
                .font(.system(size: 26))
                .scaleEffect(x: limb.mirrored ? -1 : 1, y: 1)
            Text(limb.rawValue)
                .font(.caption.weight(.semibold))
            Text(spot?.rawValue ?? "—")
                .font(.callout.weight(.heavy))
        }
        .foregroundStyle(spot?.ink ?? Color.white.opacity(0.35))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(spot?.color ?? Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.white, lineWidth: justCalled ? 3 : 0))
        .animation(.easeOut(duration: 0.25), value: spot)
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                game.toggle()
            } label: {
                Label(game.isRunning ? "Pause" : "Start",
                      systemImage: game.isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(.borderedProminent)

            Button {
                game.callNext()
            } label: {
                Label("Next", systemImage: "forward.fill")
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .help("Call the next move now (→)")

            Button {
                game.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Reset (⌘R)")
        }
        .controlSize(.large)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Every")
                Slider(value: $game.interval, in: Game.intervalRange, step: 1)
                Stepper(value: $game.interval, in: Game.intervalRange, step: 1) {
                    Text("\(Int(game.interval)) s")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .frame(width: 36, alignment: .trailing)
                }
            }
            Toggle("Speak moves aloud", isOn: $game.voiceOn)
                .toggleStyle(.switch)
        }
        .controlSize(.small)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }
}

@main
struct TwistCallerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("Twist Caller") {
            ContentView()
        }
        .defaultSize(width: 1060, height: 740)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
