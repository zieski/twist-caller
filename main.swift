import SwiftUI
import AVFoundation
import Speech

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

    func repeatCall() {
        guard let move = current else { return }
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: move.spoken)
        u.rate = 0.45
        synth.speak(u)
    }

    func adjustInterval(by delta: Double) {
        interval = min(max(interval + delta, Game.intervalRange.lowerBound), Game.intervalRange.upperBound)
    }

    func perform(_ command: VoiceCommand) {
        switch command {
        case .start: start()
        case .pause: pause()
        case .next: callNext()
        case .reset: reset()
        case .again: repeatCall()
        case .faster: adjustInterval(by: -5)
        case .slower: adjustInterval(by: 5)
        }
    }

    private func tick() {
        let now = Date()
        remaining -= now.timeIntervalSince(lastTick)
        lastTick = now
        if remaining <= 0 { callNext() }
    }
}

// MARK: - Voice commands

enum VoiceCommand: String {
    case start, pause, next, reset, again, faster, slower

    /// Words that trigger each command. None of them appear in the spoken
    /// calls ("Left Hand, Red"), so the app can't trigger itself.
    static let words: [String: VoiceCommand] = [
        "start": .start, "go": .start, "resume": .start, "begin": .start, "play": .start,
        "stop": .pause, "wait": .pause, "hold": .pause,
        "next": .next, "skip": .next,
        "reset": .reset,
        "repeat": .again, "again": .again,
        "faster": .faster, "slower": .slower,
    ]
}

/// Appends a line to the file named by the TWIST_LOG environment variable, if set.
/// Handy for seeing what the recognizer hears when a command is missed.
func dlog(_ message: String) {
    guard let path = ProcessInfo.processInfo.environment["TWIST_LOG"] else { return }
    let line = "\(Date()) \(message)\n"
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// macOS's older built-in command recognizer. Less accurate than Dictation-based
/// recognition, but works when Siri and Dictation are switched off.
final class BasicRecognizer: NSObject, NSSpeechRecognizerDelegate {
    private let recognizer = NSSpeechRecognizer()
    var onWord: ((String) -> Void)?

    func start() -> Bool {
        guard let recognizer else { return false }
        recognizer.commands = Array(VoiceCommand.words.keys)
        recognizer.listensInForegroundOnly = false
        recognizer.blocksOtherRecognizers = false
        recognizer.delegate = self
        recognizer.startListening()
        return true
    }

    func stop() { recognizer?.stopListening() }

    func speechRecognizer(_ sender: NSSpeechRecognizer, didRecognizeCommand command: String) {
        dlog("basic recognizer heard \(command)")
        onWord?(command.lowercased())
    }
}

final class VoiceControl: ObservableObject {
    private let basic = BasicRecognizer()
    private var usingBasic = false

    @Published var status = "Off"
    var onCommand: ((VoiceCommand) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var enabled = false
    private var generation = 0
    private var processed = 0
    private var lastCommand: (VoiceCommand, Date)?

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        on ? requestAccess() : stop()
    }

    private func requestAccess() {
        status = "Asking for permission…"
        dlog("requesting access; speech status=\(SFSpeechRecognizer.authorizationStatus().rawValue) mic status=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
        SFSpeechRecognizer.requestAuthorization { speech in
            dlog("speech callback \(speech.rawValue)")
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                DispatchQueue.main.async {
                    dlog("auth speech=\(speech.rawValue) mic=\(mic)")
                    guard self.enabled else { return }
                    if speech != .authorized {
                        self.status = "Speech Recognition not allowed — enable it in System Settings › Privacy & Security"
                    } else if !mic {
                        self.status = "Microphone not allowed — enable it in System Settings › Privacy & Security"
                    } else {
                        self.startEngine()
                    }
                }
            }
        }
    }

    private func startEngine() {
        guard let recognizer, recognizer.isAvailable else {
            status = "Speech recognition unavailable"
            return
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        dlog("input format \(format) available=\(recognizer.isAvailable) onDevice=\(recognizer.supportsOnDeviceRecognition)")
        var buffers = 0
        guard format.sampleRate > 0, format.channelCount > 0 else {
            status = "No microphone found"
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            buffers += 1
            if buffers % 200 == 1, let ch = buffer.floatChannelData?[0] {
                var peak: Float = 0
                for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(ch[i])) }
                dlog("buffer #\(buffers) peak=\(peak)")
            }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            status = "Couldn't start microphone: \(error.localizedDescription)"
            return
        }
        beginTask()
        status = "Listening"
    }

    private func beginTask() {
        guard enabled, let recognizer else { return }
        task?.cancel()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        processed = 0
        generation += 1
        let gen = generation
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.enabled, gen == self.generation else { return }
                if let error {
                    dlog("task error: \(error)")
                    let e = error as NSError
                    if e.domain == "kLSRErrorDomain" && e.code == 201 {
                        self.switchToBasic()
                        return
                    }
                }
                if let result {
                    dlog("result final=\(result.isFinal) text=\(result.bestTranscription.formattedString) segs=\(result.bestTranscription.segments.count)")
                    self.handle(result)
                }
                if error != nil || result?.isFinal == true {
                    // Sessions end after a pause or a time limit; keep listening.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if self.enabled, gen == self.generation { self.beginTask() }
                    }
                }
            }
        }
    }

    private func handle(_ result: SFSpeechRecognitionResult) {
        let words = result.bestTranscription.formattedString.lowercased()
            .split(whereSeparator: { !$0.isLetter }).map(String.init)
        if words.count < processed { processed = words.count }
        let fresh = words[processed...]
        processed = words.count
        for word in fresh { heard(word) }
    }

    private func heard(_ word: String) {
        guard enabled, let command = VoiceCommand.words[word] else { return }
        if let (last, at) = lastCommand, last == command, Date().timeIntervalSince(at) < 1.5 { return }
        lastCommand = (command, Date())
        status = "Heard “\(word)”"
        onCommand?(command)
    }

    private func switchToBasic() {
        generation += 1
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request = nil
        task?.cancel()
        task = nil
        basic.onWord = { [weak self] word in DispatchQueue.main.async { self?.heard(word) } }
        usingBasic = basic.start()
        dlog("switched to basic recognizer: \(usingBasic)")
        status = usingBasic
            ? "Listening (basic mode — turn on Dictation in System Settings › Keyboard for better accuracy)"
            : "Voice commands need Dictation turned on in System Settings › Keyboard"
    }

    private func stop() {
        generation += 1
        if usingBasic { basic.stop(); usingBasic = false }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        status = "Off"
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var game = Game()
    @StateObject private var voice = VoiceControl()
    @AppStorage("voiceCommands") private var voiceCommands = true

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
        .onAppear {
            voice.onCommand = { [weak game] in game?.perform($0) }
            voice.setEnabled(voiceCommands)
        }
        .onChange(of: voiceCommands) { voice.setEnabled($0) }
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
                    Text("Press Start or say “start”")
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
            Toggle("Voice commands", isOn: $voiceCommands)
                .toggleStyle(.switch)
            if voiceCommands {
                Label(voice.status, systemImage: "mic.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Say: start · stop · next · repeat · faster · slower · reset")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
