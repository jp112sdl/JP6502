import Foundation
import Observation

struct LogLine: Identifiable {
    enum Kind { case output, error, meta }
    let id: Int
    var text: String
    var kind: Kind
}

/// Runs one command line tool at a time and collects what it prints.
///
/// Each tab owns one of these, so a build and a serial transfer do not have to
/// wait for each other, but nothing inside a tab can start twice.
///
/// The tools are started through /usr/bin/env rather than a shell. env execs
/// what it is given, so the child process really is make or python: Cancel can
/// send it a SIGINT and reach the Ctrl+C handling those tools already have.
///
/// stdout is a pseudo terminal rather than a pipe, which is what makes the log
/// fill in as the tool works instead of all at once when it finishes; see
/// PseudoTerminal. stderr stays a pipe, because C leaves it unbuffered anyway
/// and a second stream is what keeps errors tellable from ordinary output.
@MainActor
@Observable
final class ProcessRunner {

    private(set) var lines: [LogLine] = []
    private(set) var isRunning = false
    /// nil while a tool has never run, and while one is still running.
    private(set) var lastExitCode: Int32?

    private var nextID = 0
    /// Index of the line currently being written to, if it has had no newline
    /// yet. Progress output is one line rewritten over and over with a CR, and
    /// this is what lets it be rewritten here too instead of piling up.
    private var openLine: Int?
    private var openLineKind: LogLine.Kind = .output
    private var process: Process?

    /// Where the parser is inside an escape sequence, which a chunk boundary
    /// can fall in the middle of.
    private enum Escape { case none, started, control, operating, operatingEnding }
    private var escape: Escape = .none

    private let maxLines = 4000

    var canRun: Bool { !isRunning }

    func clear() {
        lines.removeAll()
        openLine = nil
        escape = .none
        lastExitCode = nil
    }

    /// SIGINT, which is what Ctrl+C in a Terminal sends. basicsend.py,
    /// basicrecv.py and flashtool.py all handle it and leave the port tidy.
    func cancel() {
        guard let process, process.isRunning else { return }
        append("^C", kind: .meta)
        process.interrupt()
    }

    @discardableResult
    func run(_ argv: [String], cwd: URL, note: String? = nil) async -> Int32 {
        guard !isRunning, !argv.isEmpty else { return -1 }
        isRunning = true
        lastExitCode = nil
        escape = .none
        defer { isRunning = false; process = nil }

        if !lines.isEmpty { append("", kind: .meta) }
        append("$ " + Shell.displayCommand(argv), kind: .meta)
        if let note { append(note, kind: .meta) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = argv
        task.currentDirectoryURL = cwd

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Shell.searchPath
        // Piped python buffers its output in blocks, which would hold back the
        // progress lines these tools print until the transfer was over.
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        task.environment = environment

        let errPipe = Pipe()
        task.standardError = errPipe
        // Nothing here can answer a prompt, and a tool blocked on stdin would
        // simply hang.
        task.standardInput = FileHandle.nullDevice

        // A machine with no terminal left to hand out still has to work, so a
        // plain pipe is the fallback - block buffered, but not broken.
        let terminal = PseudoTerminal()
        let outPipe: Pipe? = terminal == nil ? Pipe() : nil
        if let terminal {
            task.standardOutput = terminal.replica
        } else if let outPipe {
            task.standardOutput = outPipe
        }
        let outDescriptor = terminal?.mainDescriptor
            ?? outPipe!.fileHandleForReading.fileDescriptor

        let outReader = reader(outDescriptor, kind: .output, closeWhenDone: terminal != nil)
        let errReader = reader(errPipe.fileHandleForReading.fileDescriptor,
                               kind: .error, closeWhenDone: false)
        process = task

        let status: Int32 = await withCheckedContinuation { continuation in
            task.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try task.run()
                // The tool has its own copy of the terminal's other end now.
                // Letting go of this one is what makes the read above see an
                // end when the tool exits.
                try? terminal?.replica.close()
            } catch {
                task.terminationHandler = nil
                try? terminal?.replica.close()
                continuation.resume(returning: -1)
            }
        }

        // Both readers end when their side is closed, which the exiting process
        // has just caused. Waiting for them is what guarantees the last line is
        // in the log before the exit status is reported after it.
        _ = await outReader.value
        _ = await errReader.value
        closeLine()

        // A tool killed by a signal reports the signal number here, not the
        // 128 + n a shell would show - so Cancel on make arrives as a plain 2.
        // The tools that handle SIGINT themselves exit with 130 instead, and
        // both of those are the same thing to read about.
        let interrupted = status != -1
            && ((task.terminationReason == .uncaughtSignal && status == SIGINT) || status == 130)

        lastExitCode = status
        if status == 0 {
            append("Done.", kind: .meta)
        } else if status == -1 {
            append("Could not start \(argv[0]).", kind: .error)
        } else if interrupted {
            append("Interrupted.", kind: .meta)
        } else {
            append("Exit code \(status).", kind: .error)
        }
        return status
    }

    /// Reads one descriptor until it ends, handing over what arrives as it
    /// arrives.
    ///
    /// read() blocks, so this runs on a Dispatch queue rather than in a Swift
    /// concurrency task: those share a pool of about one thread per core, and a
    /// thread blocked in there is one nothing else can use. Handing the chunks
    /// over with DispatchQueue.main.async keeps them in order, and resuming the
    /// caller through the same queue puts it behind the last of them.
    private func reader(_ descriptor: Int32, kind: LogLine.Kind,
                        closeWhenDone: Bool) -> Task<Void, Never> {
        Task {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while true {
                        let count = buffer.withUnsafeMutableBytes {
                            read(descriptor, $0.baseAddress, 4096)
                        }
                        if count > 0 {
                            let chunk = Data(buffer[0..<count])
                            DispatchQueue.main.async {
                                MainActor.assumeIsolated { self.ingest(chunk, kind: kind) }
                            }
                        } else if count < 0 && errno == EINTR {
                            continue
                        } else {
                            // 0 is the end of the pipe; anything else at this
                            // point is the terminal reporting that its other
                            // end has gone, which means the same thing here.
                            break
                        }
                    }
                    if closeWhenDone { close(descriptor) }
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }
    }

    private func ingest(_ data: Data, kind: LogLine.Kind) {
        // These tools speak ASCII. Decoding with a repairing initialiser means
        // a byte split across two chunks shows up as one replacement character
        // rather than throwing the whole chunk away.
        let text = String(decoding: data, as: UTF8.self)
        if openLine != nil && openLineKind != kind { closeLine() }
        openLineKind = kind

        for character in text {
            // A tool writing to a terminal may colour what it prints. None of
            // that means anything here, and left in it would show up as
            // literal bracket-3-1-m noise, so the sequences are dropped.
            switch escape {
            case .started:
                if character == "[" { escape = .control }
                else if character == "]" { escape = .operating }
                else { escape = .none }
                continue
            case .control:
                // A CSI sequence runs until a byte in the range @ to ~.
                if let byte = character.asciiValue, (0x40...0x7E).contains(byte) {
                    escape = .none
                }
                continue
            case .operating:
                // An OSC string ends at a BEL, or at ESC \.
                if character == "\u{07}" { escape = .none }
                else if character == "\u{1B}" { escape = .operatingEnding }
                continue
            case .operatingEnding:
                escape = .none
                continue
            case .none:
                break
            }

            switch character {
            case "\u{1B}":
                escape = .started
            case "\n":
                if openLine == nil { append("", kind: kind) }
                closeLine()
            case "\r":
                // Back to the start of the line: what follows overwrites it.
                if let index = openLine { lines[index].text = "" }
            case "\u{08}":
                if let index = openLine, !lines[index].text.isEmpty {
                    lines[index].text.removeLast()
                }
            default:
                if openLine == nil {
                    append("", kind: kind)
                    openLine = lines.count - 1
                }
                if let index = openLine { lines[index].text.append(character) }
            }
        }
        trim()
    }

    private func append(_ text: String, kind: LogLine.Kind) {
        closeLine()
        nextID += 1
        lines.append(LogLine(id: nextID, text: text, kind: kind))
        trim()
    }

    private func closeLine() {
        openLine = nil
    }

    private func trim() {
        guard lines.count > maxLines else { return }
        let excess = lines.count - maxLines
        lines.removeFirst(excess)
        if let index = openLine { openLine = max(0, index - excess) }
    }
}
