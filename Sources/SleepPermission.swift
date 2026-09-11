import AppKit

/// Saetter sudoers-reglen op der lader appen koere `pmset -a disablesleep` uden kodeord.
/// Det er den eneste maade at stoppe dvale med lukket laag. Installeres appen fra DMG'en,
/// har ingen installer gjort det, saa appen spoerger selv, via macOS' egen kodeordsdialog.
enum SleepPermission {
    static let sudoersPath = "/etc/sudoers.d/smartsleep"
    
    /// Brugernavnet skrives ind i sudoers, saa det tjekkes foerst.
    static func rule(for user: String) -> String? {
        guard !user.isEmpty,
              user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }) else { return nil }
        return "\(user) ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep *"
    }
    
    /// Reglen valideres med visudo foer den laegges paa plads. En ugyldig fil i sudoers.d
    /// kan faa sudo til at naegte alt, ogsaa for administratorer.
    static func shellCommand(rule: String, target: String = sudoersPath) -> String {
        """
        tmp=$(/usr/bin/mktemp) && printf '%s\\n' '\(rule)' > "$tmp" && /usr/sbin/visudo -cf "$tmp" && \
        /bin/mkdir -p "$(/usr/bin/dirname '\(target)')" && /usr/bin/install -m 0440 -o root -g wheel "$tmp" '\(target)'; \
        s=$?; /bin/rm -f "$tmp"; exit $s
        """
    }
    
    /// AppleScript-kilden der beder om kodeord og koerer kommandoen som root.
    static func appleScript(shell: String) -> String {
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }
    
    /// Viser macOS' kodeordsdialog. Returnerer true hvis reglen blev lagt paa plads.
    static func install() -> Bool {
        guard let rule = rule(for: NSUserName()) else {
            appLog.error("Brugernavnet kan ikke bruges i sudoers: \(NSUserName(), privacy: .public)")
            return false
        }
        var error: NSDictionary?
        NSAppleScript(source: appleScript(shell: shellCommand(rule: rule)))?.executeAndReturnError(&error)
        if let error {
            appLog.error("Sudoers-reglen blev ikke sat op: \(error.description, privacy: .public)")
            return false
        }
        appLog.notice("Sudoers-reglen er sat op i \(sudoersPath, privacy: .public)")
        return true
    }
}
