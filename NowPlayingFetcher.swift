import Foundation

struct NowPlaying {
    let title: String
    let artist: String
    let spotifyVolume: Int?
    let artworkURL: URL?
}

/// Henter sangtitel fra Spotify og videotitel fra Brave via AppleScript.
/// Koerer i baggrunden med timeout, saa en langsom app aldrig kan fryse menuen.
/// Titlen er pynt. Om Mac'en holdes vaagen afgoeres af CoreAudio, ikke af det her.
final class NowPlayingFetcher {
    static let shared = NowPlayingFetcher()
    
    private let queue = DispatchQueue(label: "com.personal.SmartSleep.nowplaying")
    private var isFetching = false   // kun main
    private static var lastError = "" // kun queue
    
    /// completion kaldes paa main. Kaldet ignoreres hvis en hentning allerede er i gang.
    func fetch(for source: AudioSource, completion: @escaping (NowPlaying?) -> Void) {
        guard !isFetching else { return }
        isFetching = true
        queue.async {
            let result: NowPlaying?
            if source.isSpotify {
                result = Self.fetchSpotify()
            } else if source.isBrave {
                result = Self.fetchBrave()
            } else {
                result = nil
            }
            DispatchQueue.main.async {
                self.isFetching = false
                completion(result)
            }
        }
    }
    
    private static func fetchSpotify() -> NowPlaying? {
        // "is running" foerst, ellers starter AppleScript Spotify hvis den lige er lukket.
        let script = """
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    -- Reklamer og lokale filer har ikke altid et cover.
                    set art to ""
                    try
                        set art to artwork url of current track
                    end try
                    return (name of current track) & "|||" & (artist of current track) & "|||" & (sound volume as string) & "|||" & art
                end if
            end tell
        end if
        return ""
        """
        guard let output = runAppleScript(script), !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: "|||")
        guard parts.count == 4 else { return nil }
        return NowPlaying(title: parts[0], artist: parts[1], spotifyVolume: Int(parts[2]),
                          artworkURL: parts[3].isEmpty ? nil : URL(string: parts[3]))
    }
    
    private static func fetchBrave() -> NowPlaying? {
        // Den aktive fane foerst, ellers den foerste YouTube-fane.
        let script = """
        if application "Brave Browser" is running then
            tell application "Brave Browser"
                if (count of windows) is 0 then return ""
                set t to active tab of front window
                if (URL of t as string) contains "youtu" then return (title of t as string) & "|||" & (URL of t as string)
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t as string) contains "youtu" then return (title of t as string) & "|||" & (URL of t as string)
                    end repeat
                end repeat
            end tell
        end if
        return ""
        """
        guard let raw = runAppleScript(script), !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: "|||")
        let url = parts.count > 1 ? parts[1] : ""
        return NowPlaying(title: cleanYouTubeTitle(parts[0]), artist: "YouTube", spotifyVolume: nil,
                          artworkURL: youTubeThumbnail(for: url))
    }
    
    /// Thumbnail ud fra videoens ID. mqdefault er 16:9 uden sorte kanter, i modsaetning til hqdefault.
    static func youTubeThumbnail(for urlString: String) -> URL? {
        guard let components = URLComponents(string: urlString), let host = components.host else { return nil }
        let pathParts = components.path.split(separator: "/").map(String.init)
        let id: String?
        if host.hasSuffix("youtu.be") {
            id = pathParts.first
        } else if let first = pathParts.first, ["shorts", "live", "embed"].contains(first) {
            id = pathParts.dropFirst().first
        } else {
            id = components.queryItems?.first(where: { $0.name == "v" })?.value
        }
        guard let id, !id.isEmpty,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
    }
    
    private static func cleanYouTubeTitle(_ raw: String) -> String {
        var title = raw.replacingOccurrences(of: " - YouTube", with: "")
        // Fjern notifikationstaelleren, fx "(3) Sangtitel".
        if let range = title.range(of: #"^\(\d+\) "#, options: .regularExpression) {
            title.removeSubrange(range)
        }
        return title
    }
    
    private static func runAppleScript(_ source: String, timeout: TimeInterval = 5) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        
        do {
            try process.run()
        } catch {
            appLog.error("Kunne ikke starte osascript: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            appLog.error("AppleScript svarede ikke inden \(timeout) sek")
            return nil
        }
        
        guard process.terminationStatus == 0 else {
            let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = "status \(process.terminationStatus): \(stderrText)"
            if message != lastError {
                appLog.error("AppleScript fejlede: \(message, privacy: .public)")
                lastError = message
            }
            return nil
        }
        lastError = ""
        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
