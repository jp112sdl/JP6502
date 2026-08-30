import Foundation

/// Finding the command line tools the way a Terminal would find them.
///
/// A GUI app is launched by launchd, not by a shell, so it inherits a bare
/// PATH - /usr/bin:/bin:/usr/sbin:/sbin - and none of ca65, a Homebrew python3
/// or md5sum live there. `make` started with that PATH fails on the first
/// assembler call. Asking a login shell once for its PATH, and handing that to
/// every tool this app starts, is what makes the build work at all.
enum Shell {

    /// PATH as a login shell has it, with the usual suspects appended in case
    /// the shell could not be asked.
    static let searchPath: String = {
        var parts = loginShellPath().split(separator: ":").map(String.init)
        for extra in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                      "/usr/sbin", "/sbin"] where !parts.contains(extra) {
            parts.append(extra)
        }
        return parts.joined(separator: ":")
    }()

    /// The absolute path of `name`, or nil if it is nowhere on `searchPath`.
    static func find(_ name: String) -> String? {
        if name.contains("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        for directory in searchPath.split(separator: ":") {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// The first of `names` that exists, or the last name unresolved - so a
    /// caller always has something to put on a command line, and the failure
    /// shows up as the tool's own "not found" rather than as a nil somewhere.
    static func findFirst(_ names: [String]) -> String {
        for name in names {
            if let found = find(name) { return found }
        }
        return names.last ?? ""
    }

    /// An argument list as it could be pasted into a Terminal. Only for
    /// showing: nothing is ever run through a shell, so this cannot change
    /// what actually happens.
    static func displayCommand(_ argv: [String]) -> String {
        argv.map(quote).joined(separator: " ")
    }

    static func quote(_ argument: String) -> String {
        let safe = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-./=:+@,")
        if !argument.isEmpty && argument.unicodeScalars.allSatisfy(safe.contains) {
            return argument
        }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - python

    /// The first python on PATH that can import pyserial.
    ///
    /// Every tool here needs it, and there is usually more than one python
    /// installed - a MacPorts or Homebrew one on PATH ahead of the one the
    /// modules were installed into. Picking the first python3 and hoping is
    /// what turns a working setup into "pyserial is missing", which is the
    /// wrong thing to be debugging with a programmer on the desk.
    static func pythonWithPySerial() -> String {
        let candidates = pythonCandidates()
        for candidate in candidates where hasPySerial(candidate) { return candidate }
        return candidates.first ?? "python3"
    }

    static func hasPySerial(_ python: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: python) || !python.contains("/") else {
            return false
        }
        return run(python, ["-c", "import serial"]) == 0
    }

    /// Every python3 and python on PATH, in the order the shell would find
    /// them, without repeating one that two directories both point at.
    static func pythonCandidates() -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        for directory in searchPath.split(separator: ":") {
            for name in ["python3", "python"] {
                let candidate = "\(directory)/\(name)"
                guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
                let real = (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate))
                    ?? candidate
                guard seen.insert(real).inserted else { continue }
                found.append(candidate)
            }
        }
        return found
    }

    /// Runs something to completion for its exit code alone. Only for the
    /// quick probes above - anything the user watches goes through
    /// ProcessRunner instead.
    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func loginShellPath() -> String {
        // -l sources .zprofile and friends but not .zshrc, which is where the
        // interactive-only things that could hang a startup live.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "printf %s \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ProcessInfo.processInfo.environment["PATH"] ?? ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
