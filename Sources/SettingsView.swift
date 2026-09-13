import SwiftUI
import AppKit

/// Samme ikon i menulinjen og i indstillingsvinduet.
enum StatusSymbol {
    /// Pause har sit eget ikon. Slaaet fra ser ellers praecis ud som "intet spiller",
    /// og saa opdager man ikke at appen ikke goer noget.
    static func name(isSleepPrevented: Bool, isMediaDetected: Bool, isForced: Bool, isPaused: Bool) -> String {
        if isPaused { return "pause.circle" }
        guard isSleepPrevented else { return "moon.zzz" }
        return (isForced && !isMediaDetected) ? "bolt.fill" : "waveform"
    }
}

enum LaunchAtLogin {
    private static var plistPath: String {
        "\(NSHomeDirectory())/Library/LaunchAgents/com.personal.SmartSleep.plist"
    }
    
    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }
    
    static func set(_ enabled: Bool) {
        guard enabled else {
            try? FileManager.default.removeItem(atPath: plistPath)
            return
        }
        let executable = "\(Bundle.main.bundlePath)/Contents/MacOS/SmartSleep"
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>com.personal.SmartSleep</string>
        <key>ProgramArguments</key><array><string>\(executable)</string></array>
        <key>RunAtLoad</key><true/>
        </dict></plist>
        """
        let folder = (plistPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try? xml.write(toFile: plistPath, atomically: true, encoding: .utf8)
    }
}

/// Henter albumcovers og thumbnails, og husker de seneste saa et nummer ikke hentes igen.
final class ArtworkLoader {
    static let shared = ArtworkLoader()
    
    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 20
        return cache
    }()
    
    /// completion kaldes paa main.
    func image(for url: URL, completion: @escaping (NSImage?) -> Void) {
        if let cached = cache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            let image = data.flatMap { NSImage(data: $0) }
            if image == nil {
                appLog.error("Kunne ikke hente cover: \(error?.localizedDescription ?? "ugyldigt billede", privacy: .public)")
            }
            DispatchQueue.main.async {
                if let image { self?.cache.setObject(image, forKey: url as NSURL) }
                completion(image)
            }
        }.resume()
    }
}

// MARK: - View Model

class SettingsViewModel: ObservableObject {
    private let monitor = AudioSleepMonitor.shared
    
    // Kun skriv til monitoren ved en reel aendring. Ellers ville en synkronisering fra
    // monitoren trigge en ny notifikation, der synkroniserer igen, og saa videre.
    @Published var isAutoEnabled: Bool = AudioSleepMonitor.shared.isAutoEnabled {
        didSet {
            guard monitor.isAutoEnabled != isAutoEnabled else { return }
            appLog.notice("Keep awake while playing slaaet \(self.isAutoEnabled ? "til" : "fra", privacy: .public) i vinduet")
            monitor.isAutoEnabled = isAutoEnabled
        }
    }
    @Published var isForceKeepAwake: Bool = AudioSleepMonitor.shared.isForceKeepAwake {
        didSet { if monitor.isForceKeepAwake != isForceKeepAwake { monitor.isForceKeepAwake = isForceKeepAwake } }
    }
    @Published var isDimBrightnessEnabled: Bool = AudioSleepMonitor.shared.isDimBrightnessEnabled {
        didSet { if monitor.isDimBrightnessEnabled != isDimBrightnessEnabled { monitor.isDimBrightnessEnabled = isDimBrightnessEnabled } }
    }
    @Published var isLaunchAtLogin: Bool = LaunchAtLogin.isEnabled
    @Published var iconAnimation: IconAnimation = IconAnimation.current {
        didSet { if IconAnimation.current != iconAnimation { IconAnimation.current = iconAnimation } }
    }
    
    @Published var isMediaDetected = false
    @Published var isSleepPrevented = false
    @Published var currentSource = ""
    @Published var nowPlayingTitle = ""
    @Published var nowPlayingArtist = ""
    @Published var artwork: NSImage?
    private var artworkURL: URL?
    
    init() {
        monitor.addObserver(self) { [weak self] media, prevented, _, _, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                // Laes direkte fra monitoren. Notifikationen ved "soevn tilladt" sender tomme
                // tekster, ogsaa hvis musikken stadig spiller.
                self.isMediaDetected = media
                self.isSleepPrevented = prevented
                self.currentSource = self.monitor.currentDetectionSource
                self.nowPlayingTitle = self.monitor.nowPlayingTitle
                self.nowPlayingArtist = self.monitor.nowPlayingArtist
                self.updateArtwork(self.monitor.nowPlayingArtworkURL)
                // Menuen kan ogsaa slaa ting til og fra. Hold vinduet i sync.
                if self.isAutoEnabled != self.monitor.isAutoEnabled { self.isAutoEnabled = self.monitor.isAutoEnabled }
                if self.isForceKeepAwake != self.monitor.isForceKeepAwake { self.isForceKeepAwake = self.monitor.isForceKeepAwake }
            }
        }
    }
    
    deinit {
        AudioSleepMonitor.shared.removeObserver(self)
    }
    
    func setLaunchAtLogin(_ enabled: Bool) {
        LaunchAtLogin.set(enabled)
        isLaunchAtLogin = LaunchAtLogin.isEnabled
    }
    
    /// Det gamle cover bliver staaende til det nye er hentet, saa der ikke blinker et tomt felt.
    private func updateArtwork(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        guard let url else {
            artwork = nil
            return
        }
        ArtworkLoader.shared.image(for: url) { [weak self] image in
            guard let self, self.artworkURL == url else { return }
            self.artwork = image
        }
    }
}

// MARK: - View

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            
            Divider()
            
            VStack(spacing: 0) {
                row("waveform", "Keep awake while playing", $viewModel.isAutoEnabled)
                row("bolt", "Always stay awake", $viewModel.isForceKeepAwake)
                row("laptopcomputer", "Screen off when lid closes", $viewModel.isDimBrightnessEnabled)
                row("power", "Open at login", Binding(
                    get: { viewModel.isLaunchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                animationRow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
        .fixedSize()
    }
    
    // MARK: Nu spiller
    
    private var header: some View {
        HStack(spacing: 12) {
            artworkView
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
    }
    
    private var artworkView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
            if viewModel.isMediaDetected, let artwork = viewModel.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: StatusSymbol.name(
                    isSleepPrevented: viewModel.isSleepPrevented,
                    isMediaDetected: viewModel.isMediaDetected,
                    isForced: viewModel.isForceKeepAwake,
                    isPaused: isPaused
                ))
                .font(.system(size: 17))
                .foregroundColor(viewModel.isMediaDetected ? .accentColor : .secondary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    
    private var headerTitle: String {
        guard viewModel.isMediaDetected else { return "Nothing playing" }
        return viewModel.nowPlayingTitle.isEmpty ? viewModel.currentSource : viewModel.nowPlayingTitle
    }
    
    private var isPaused: Bool {
        !viewModel.isAutoEnabled && !viewModel.isForceKeepAwake
    }
    
    private var headerSubtitle: String {
        if isPaused {
            return viewModel.isMediaDetected ? "Paused · \(viewModel.currentSource)" : "Paused. Mac sleeps as usual"
        }
        guard viewModel.isMediaDetected else {
            guard viewModel.isSleepPrevented else { return "Mac can sleep" }
            return viewModel.isForceKeepAwake ? "Staying awake (forced)" : "Staying awake a few more seconds"
        }
        guard !viewModel.nowPlayingTitle.isEmpty else { return "Playing audio" }
        let artist = viewModel.nowPlayingArtist
        if artist.isEmpty || artist == viewModel.currentSource { return viewModel.currentSource }
        return "\(artist) · \(viewModel.currentSource)"
    }
    
    // MARK: Indstillinger
    
    private var animationRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 18)
            Text("Animation")
                .font(.system(size: 13))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            SegmentPicker(selection: $viewModel.iconAnimation)
                .frame(width: 144)
        }
        .padding(.vertical, 6)
    }
    
    private func row(_ symbol: String, _ title: String, _ isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 6)
    }
}

/// Egen segment-kontrol. macOS' egen giver den valgte knap fed skrift, saa bredderne
/// hopper, og den nye udgave laver en pop-animation ved tryk. Her er alle knapper lige
/// brede og skriften aendrer sig ikke.
private struct SegmentPicker: View {
    @Binding var selection: IconAnimation
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(IconAnimation.allCases, id: \.self) { style in
                Button {
                    selection = style
                } label: {
                    Text(style.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == style ? .white : .primary)
                        .frame(maxWidth: .infinity, minHeight: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(selection == style ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
    }
}

/// Ingen skalering ved tryk, kun en svag fade.
private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}
