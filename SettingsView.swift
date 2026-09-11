import SwiftUI
import AppKit

/// Samme ikon i menulinjen og i indstillingsvinduet.
enum StatusSymbol {
    static func name(isSleepPrevented: Bool, isMediaDetected: Bool, isForced: Bool) -> String {
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

// MARK: - View Model

class SettingsViewModel: ObservableObject {
    private let monitor = AudioSleepMonitor.shared
    
    // Kun skriv til monitoren ved en reel aendring. Ellers ville en synkronisering fra
    // monitoren trigge en ny notifikation, der synkroniserer igen, og saa videre.
    @Published var isAutoEnabled: Bool = AudioSleepMonitor.shared.isAutoEnabled {
        didSet { if monitor.isAutoEnabled != isAutoEnabled { monitor.isAutoEnabled = isAutoEnabled } }
    }
    @Published var isForceKeepAwake: Bool = AudioSleepMonitor.shared.isForceKeepAwake {
        didSet { if monitor.isForceKeepAwake != isForceKeepAwake { monitor.isForceKeepAwake = isForceKeepAwake } }
    }
    @Published var isDimBrightnessEnabled: Bool = AudioSleepMonitor.shared.isDimBrightnessEnabled {
        didSet { if monitor.isDimBrightnessEnabled != isDimBrightnessEnabled { monitor.isDimBrightnessEnabled = isDimBrightnessEnabled } }
    }
    @Published var isLaunchAtLogin: Bool = LaunchAtLogin.isEnabled
    
    @Published var isMediaDetected = false
    @Published var isSleepPrevented = false
    @Published var currentSource = ""
    @Published var nowPlayingTitle = ""
    
    init() {
        monitor.addObserver(self) { [weak self] media, prevented, _, source, title, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isMediaDetected = media
                self.isSleepPrevented = prevented
                self.currentSource = source
                self.nowPlayingTitle = title
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
                row("waveform", "Automatisk ved lyd", $viewModel.isAutoEnabled)
                row("bolt", "Hold altid vågen", $viewModel.isForceKeepAwake)
                row("laptopcomputer", "Sluk skærm ved lukket låg", $viewModel.isDimBrightnessEnabled)
                row("power", "Start ved login", Binding(
                    get: { viewModel.isLaunchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
        .fixedSize()
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: StatusSymbol.name(
                isSleepPrevented: viewModel.isSleepPrevented,
                isMediaDetected: viewModel.isMediaDetected,
                isForced: viewModel.isForceKeepAwake
            ))
            .font(.system(size: 20))
            .foregroundColor(viewModel.isSleepPrevented ? .accentColor : .secondary)
            .frame(width: 26)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isSleepPrevented ? "Holder Mac'en vågen" : "Mac'en må sove")
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
    }
    
    private var subtitle: String {
        guard viewModel.isSleepPrevented else { return "Ingen afspilning" }
        if !viewModel.nowPlayingTitle.isEmpty {
            // Kilden foerst, saa den ikke bliver skaaret vaek naar titlen er lang.
            return "\(viewModel.currentSource) · \(viewModel.nowPlayingTitle)"
        }
        if !viewModel.currentSource.isEmpty { return viewModel.currentSource }
        return viewModel.isForceKeepAwake ? "Tvunget vågen" : "Lyden stoppede, slipper om lidt"
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
