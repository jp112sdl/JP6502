import Foundation

/// A terminal to hand a tool instead of a pipe, so that what it prints arrives
/// while it is still running.
///
/// A C program picks its buffering from what its stdout is: line by line to a
/// terminal, and in 4 KB blocks to anything else. `make` on a plain pipe
/// therefore says nothing at all until it exits, which is the whole build spent
/// looking at an empty window. Given a terminal it flushes every line, and so
/// do the tools it starts.
struct PseudoTerminal {

    /// The end this app reads. What the tool writes to `replica` comes out here.
    let mainDescriptor: Int32
    /// The end the tool is given as its stdout. It is closed here as soon as
    /// the tool has been started: the tool's own copy is then the only one
    /// left, and its exit is what ends the read above.
    let replica: FileHandle

    init?() {
        let main = posix_openpt(O_RDWR | O_NOCTTY)
        guard main >= 0 else { return nil }
        guard grantpt(main) == 0, unlockpt(main) == 0, let name = ptsname(main) else {
            close(main)
            return nil
        }
        let replicaDescriptor = open(name, O_RDWR | O_NOCTTY)
        guard replicaDescriptor >= 0 else {
            close(main)
            return nil
        }

        // OPOST off stops the line discipline turning every \n into \r\n. A CR
        // here means a progress line is being rewritten in place, and one in
        // front of every newline would blank every line instead.
        var settings = termios()
        if tcgetattr(replicaDescriptor, &settings) == 0 {
            settings.c_oflag &= ~tcflag_t(OPOST)
            settings.c_lflag &= ~tcflag_t(ECHO)
            _ = tcsetattr(replicaDescriptor, TCSANOW, &settings)
        }
        Self.setSize(replicaDescriptor, rows: 50, columns: 200)

        mainDescriptor = main
        replica = FileHandle(fileDescriptor: replicaDescriptor, closeOnDealloc: false)
    }

    /// Tools that lay their output out to the window get a wide one rather than
    /// the zero an unconfigured terminal reports.
    private static func setSize(_ descriptor: Int32, rows: UInt16, columns: UInt16) {
        // TIOCSWINSZ is _IOW('t', 103, struct winsize), which is a macro and so
        // is not imported into Swift; this is what it expands to.
        let request = UInt(0x8000_0000)
            | (UInt(MemoryLayout<winsize>.size) << 16)
            | (UInt(UInt8(ascii: "t")) << 8)
            | 103
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(descriptor, request, &size)
    }
}
