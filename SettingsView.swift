import SwiftUI
import AppKit

// MARK: - Glass Background
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - View Model
class SettingsViewModel: ObservableObject {
    @Published var isAutoEnabled: Bool = AudioSleepMonitor.shared.isAutoEnabled {
        didSet { AudioSleepMonitor.shared.isAutoEnabled = isAutoEnabled }
    }
    @Published var isForceKeepAwake: Bool = AudioSleepMonitor.shared.isForceKeepAwake {
        didSet { AudioSleepMonitor.shared.isForceKeepAwake = isForceKeepAwake }
    }
    @Published var isDimBrightnessEnabled: Bool = AudioSleepMonitor.shared.isDimBrightnessEnabled {
        didSet { AudioSleepMonitor.shared.isDimBrightnessEnabled = isDimBrightnessEnabled }
    }
    @Published var isLaunchAtLogin: Bool = false
    
    @Published var isMediaDetected: Bool = false
    @Published var isSleepPrevented: Bool = false
    @Published var isLidClosed: Bool = false
    @Published var currentSource: String = ""
    @Published var nowPlayingTitle: String = ""
    @Published var nowPlayingArtist: String = ""
    
    init() {
        let home = NSHomeDirectory()
        let plistPath = "\(home)/Library/LaunchAgents/com.personal.SmartSleep.plist"
        isLaunchAtLogin = FileManager.default.fileExists(atPath: plistPath)
        
        isMediaDetected = AudioSleepMonitor.shared.isMediaDetected
        isSleepPrevented = AudioSleepMonitor.shared.isSleepPrevented
        isLidClosed = AudioSleepMonitor.shared.isLidClosed
        currentSource = AudioSleepMonitor.shared.currentDetectionSource
        nowPlayingTitle = AudioSleepMonitor.shared.nowPlayingTitle
        nowPlayingArtist = AudioSleepMonitor.shared.nowPlayingArtist
        
        AudioSleepMonitor.shared.addObserver(self) { [weak self] media, prevented, lid, src, title, artist in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self?.isMediaDetected = media
                    self?.isSleepPrevented = prevented
                    self?.isLidClosed = lid
                    self?.currentSource = src
                    self?.nowPlayingTitle = title
                    self?.nowPlayingArtist = artist
                }
            }
        }
    }
    
    deinit {
        AudioSleepMonitor.shared.removeObserver(self)
    }
    
    func toggleLaunchAtLogin(_ on: Bool) {
        let home = NSHomeDirectory()
        let path = "\(home)/Library/LaunchAgents/com.personal.SmartSleep.plist"
        if on {
            let exec = "\(Bundle.main.bundlePath)/Contents/MacOS/SmartSleep"
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
            <key>Label</key><string>com.personal.SmartSleep</string>
            <key>ProgramArguments</key><array><string>\(exec)</string></array>
            <key>RunAtLoad</key><true/>
            </dict></plist>
            """
            let folder = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? xml.write(toFile: path, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(atPath: path)
        }
        isLaunchAtLogin = on
    }
}

// MARK: - Main View
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        ZStack {
            VisualEffectView().ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Drag area for titlebar
                Spacer().frame(height: 36)
                
                VStack(spacing: 14) {
                    // Now Playing Card
                    nowPlayingCard
                    
                    // Settings
                    settingsCard
                    
                    // Footer
                    HStack {
                        Text("SmartSleep v1.0")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 440, height: 480)
    }
    
    // MARK: - Now Playing Card
    var nowPlayingCard: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(viewModel.isSleepPrevented
                          ? LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 50, height: 50)
                
                Image(systemName: viewModel.isSleepPrevented
                      ? (viewModel.currentSource.contains("Spotify") ? "music.note" : "play.tv.fill")
                      : "zzz")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                if viewModel.isSleepPrevented {
                    Text(viewModel.nowPlayingTitle.isEmpty ? "Lyd afspilles" : viewModel.nowPlayingTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    
                    Text(viewModel.nowPlayingArtist.isEmpty ? viewModel.currentSource : viewModel.nowPlayingArtist)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Ingen afspilning")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("Mac'en dvaler normalt")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Status badge
            VStack(spacing: 3) {
                Circle()
                    .fill(viewModel.isSleepPrevented ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 10, height: 10)
                    .shadow(color: viewModel.isSleepPrevented ? .green.opacity(0.6) : .clear, radius: 4)
                
                Text(viewModel.isSleepPrevented ? "VÅGEN" : "DVALE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(viewModel.isSleepPrevented ? .green : .secondary)
                
                if viewModel.isSleepPrevented {
                    Text("LIVE")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(viewModel.isSleepPrevented ? Color.green.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Settings Card
    var settingsCard: some View {
        VStack(spacing: 0) {
            settingRow(
                icon: "music.note", color: .blue,
                title: "Automatisk dvalestyring",
                sub: "Når en app spiller lyd",
                isOn: $viewModel.isAutoEnabled
            )
            
            divider
            
            settingRow(
                icon: "sun.min.fill", color: .orange,
                title: "Sluk skærmen",
                sub: "Når låget lukkes under afspilning",
                isOn: $viewModel.isDimBrightnessEnabled
            )
            
            divider
            
            settingRow(
                icon: "bolt.fill", color: .yellow,
                title: "Tving forbliv vågen",
                sub: "Uanset om der spilles lyd",
                isOn: $viewModel.isForceKeepAwake
            )
            
            divider
            
            settingRow(
                icon: "power", color: .green,
                title: "Start ved login",
                sub: "Kør automatisk ved opstart",
                isOn: Binding(
                    get: { viewModel.isLaunchAtLogin },
                    set: { viewModel.toggleLaunchAtLogin($0) }
                )
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Setting Row
    func settingRow(icon: String, color: Color, title: String, sub: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color)
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    var divider: some View {
        Divider().padding(.leading, 54)
    }
}
