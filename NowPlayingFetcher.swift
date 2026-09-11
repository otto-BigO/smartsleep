import Foundation

struct NowPlaying {
    let title: String
    let artist: String
    let spotifyVolume: Int?
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
                    return (name of current track) & "|||" & (artist of current track) & "|||" & (sound volume as string)
                end if
            end tell
        end if
        return ""
        """
        guard let output = runAppleScript(script), !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: "|||")
        guard parts.count == 3 else { return nil }
        return NowPlaying(title: parts[0], artist: parts[1], spotifyVolume: Int(parts[2]))
    }
    
    private static func fetchBrave() -> NowPlaying? {
        // Den aktive fane foerst, ellers den foerste YouTube-fane.
        let script = """
        if application "Brave Browser" is running then
            tell application "Brave Browser"
                if (count of windows) is 0 then return ""
                set t to active tab of front window
                if (URL of t as string) contains "youtu" then return (title of t as string)
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t as string) contains "youtu" then return (title of t as string)
                    end repeat
                end repeat
            end tell
        end if
        return ""
        """
        guard let raw = runAppleScript(script), !raw.isEmpty else { return nil }
        return NowPlaying(title: cleanYouTubeTitle(raw), artist: "Brave", spotifyVolume: nil)
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
