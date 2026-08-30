import SwiftUI
import UniformTypeIdentifiers

/// flashtool.py, which talks to the FlashPROMv2 programmer over its own serial
/// port. The chip in its socket is a different thing from the 6502 on the
/// other tab, and so is the port and the baud rate.
struct FlashView: View {

    enum Command: String, CaseIterable, Identifiable {
        case write, verify, read, erase, blank, info, device, protectState
        var id: String { rawValue }

        var title: String {
            switch self {
            case .write:        return "Write a file"
            case .verify:       return "Verify against a file"
            case .read:         return "Read the chip to a file"
            case .erase:        return "Erase"
            case .blank:        return "Blank check"
            case .info:         return "Chip in the socket"
            case .device:       return "Device type"
            case .protectState: return "Data protection"
            }
        }

        var detail: String {
            switch self {
            case .write:        return "Erases what it needs to, programs the file, then checks it"
            case .verify:       return "Compares the chip against a file without changing anything"
            case .read:         return "Dumps the chip, or a range of it, to a file here"
            case .erase:        return "The whole chip, or the one sector an address falls in"
            case .blank:        return "Checks that a range reads as FF"
            case .info:         return "Asks the programmer what it has identified"
            case .device:       return "Lists the chips the firmware knows, or pins one of them"
            case .protectState: return "Software data protection on the EEPROMs that have it"
            }
        }

        var needsFile: Bool { self == .write || self == .verify }
    }

    enum EraseMode: String, CaseIterable, Identifiable {
        case automatic, chip, sectors, none
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: return "As the chip needs"
            case .chip:      return "Whole chip"
            case .sectors:   return "Only the sectors written"
            case .none:      return "Do not erase"
            }
        }
    }

    let settings: AppSettings
    let index: ProjectIndex
    let runner: ProcessRunner

    @State private var command: Command = .write
    @State private var file: URL?
    @State private var offset = "0"
    @State private var fileFormat = "auto"
    @State private var eraseMode: EraseMode = .automatic
    @State private var verifyMode = "crc"
    @State private var skipBlank = true

    @State private var readOutput: URL?
    @State private var readStart = "0"
    @State private var readLength = ""
    @State private var readFormat = "auto"

    @State private var eraseWholeChip = true
    @State private var eraseSector = "0x0000"

    @State private var blankStart = "0"
    @State private var blankLength = ""

    @State private var rescan = false
    @State private var deviceAction = ""       // "" lists them, "auto" un-pins
    @State private var protectOn = true

    var body: some View {
        OptionsAndOutput(runner: runner) {
            Form {
                Section("Programmer") {
                    PortPicker(selection: bindingFlashPort)
                    LabeledContent("Baud") {
                        BaudField(baud: bindingFlashBaud, presets: [115200, 225000, 500000])
                    }
                    Text("Has to match SERIAL_BAUD in FlashPROMv2/Config.h.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Treat chip as", selection: bindingFlashDevice) {
                        Text("What the programmer detected").tag("")
                        ForEach(index.flashDevices, id: \.self) { Text($0).tag($0) }
                    }
                    LabeledContent("Bootloader wait") {
                        HexField(title: "seconds", text: bindingResetDelay,
                                 placeholder: "2.0", width: 70)
                    }
                    Toggle("Report protocol retries", isOn: bindingVerbose)
                }

                Section {
                    Picker("Command", selection: $command) {
                        ForEach(Command.allCases) { Text($0.title).tag($0) }
                    }
                    Text(command.detail).font(.caption).foregroundStyle(.secondary)
                    commandOptions
                } header: {
                    Text("Command")
                }

                RunBar(title: runTitle, systemImage: runIcon, runner: runner,
                       enabled: isReady, confirm: confirmation) {
                    run()
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { if file == nil { file = index.romBinaries.first } }
    }

    @ViewBuilder
    private var commandOptions: some View {
        switch command {
        case .write, .verify:
            binaryChooser
            LabeledContent("Offset in the chip") {
                HexField(title: "offset", text: $offset, placeholder: "0")
            }
            Picker("File format", selection: $fileFormat) {
                Text("From the name").tag("auto")
                Text("Raw binary").tag("bin")
                Text("Intel HEX").tag("hex")
            }
            if command == .write {
                Picker("Erase", selection: $eraseMode) {
                    ForEach(EraseMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Check afterwards", selection: $verifyMode) {
                    Text("CRC of what was written").tag("crc")
                    Text("Read it all back").tag("read")
                    Text("Do not check").tag("none")
                }
                Toggle("Skip stretches the file leaves blank", isOn: $skipBlank)
            } else {
                Picker("Compare by", selection: $verifyMode) {
                    Text("CRC").tag("crc")
                    Text("Reading it back").tag("read")
                }
            }

        case .read:
            LabeledContent("Write to") {
                HStack {
                    Text(readOutput?.lastPathComponent ?? "not chosen")
                        .foregroundStyle(readOutput == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose…") { chooseReadOutput() }
                }
            }
            LabeledContent("Start") { HexField(title: "start", text: $readStart, placeholder: "0") }
            LabeledContent("Length") {
                HexField(title: "length", text: $readLength, placeholder: "to the end")
            }
            Picker("Write as", selection: $readFormat) {
                Text("From the name").tag("auto")
                Text("Raw binary").tag("bin")
                Text("Intel HEX").tag("hex")
                Text("Both").tag("both")
            }

        case .erase:
            Toggle("Whole chip", isOn: $eraseWholeChip)
            if !eraseWholeChip {
                LabeledContent("Address in the sector") {
                    HexField(title: "sector", text: $eraseSector, placeholder: "0x0000")
                }
            }

        case .blank:
            LabeledContent("Start") { HexField(title: "start", text: $blankStart, placeholder: "0") }
            LabeledContent("Length") {
                HexField(title: "length", text: $blankLength, placeholder: "to the end")
            }

        case .info:
            Toggle("Probe the socket again", isOn: $rescan)

        case .device:
            Picker("Do", selection: $deviceAction) {
                Text("List what the firmware knows").tag("")
                Text("Forget the pinned type and probe").tag("auto")
                ForEach(index.flashDevices, id: \.self) { name in
                    Text("Pin it as \(name)").tag(name)
                }
            }
            if deviceAction == "auto" {
                Text("Probing writes an ID sequence to the chip. It is why the "
                     + "parallel EEPROMs are reachable by name only.")
                    .font(.caption).foregroundStyle(.secondary)
            }

        case .protectState:
            Picker("Data protection", selection: $protectOn) {
                Text("On").tag(true)
                Text("Off").tag(false)
            }
        }
    }

    private var binaryChooser: some View {
        LabeledContent("File") {
            HStack {
                Picker("", selection: $file) {
                    Text("none").tag(URL?.none)
                    ForEach(index.romBinaries, id: \.self) { url in
                        Text(url.lastPathComponent).tag(URL?.some(url))
                    }
                    if let file, !index.romBinaries.contains(file) {
                        Text(file.lastPathComponent).tag(URL?.some(file))
                    }
                }
                .labelsHidden()
                Button("Browse…") { chooseFile() }
            }
        }
    }

    // MARK: - Running

    private var runTitle: String {
        switch command {
        case .write:        return "Write"
        case .verify:       return "Verify"
        case .read:         return "Read"
        case .erase:        return "Erase"
        case .blank:        return "Check"
        case .info:         return "Read chip info"
        case .device:       return "Apply"
        case .protectState: return "Apply"
        }
    }

    private var runIcon: String {
        switch command {
        case .write:  return "square.and.arrow.down"
        case .read:   return "square.and.arrow.up"
        case .erase:  return "trash"
        default:      return "play.fill"
        }
    }

    private var isReady: Bool {
        if command.needsFile { return file != nil }
        if command == .read { return readOutput != nil }
        return true
    }

    private var confirmation: String? {
        switch command {
        case .erase where eraseWholeChip:
            return "Erase the whole chip in the programmer's socket?"
        case .protectState where !protectOn:
            return "Turning data protection off leaves the chip open to stray "
                 + "writes, and probing one in that state is what damages it."
        default:
            return nil
        }
    }

    private func run() {
        var argv = [settings.pythonPath, "-u", settings.flashToolScript.path]

        switch command {
        case .write:
            argv += ["write", file?.path ?? "", "--offset", offset.orZero,
                     "--format", fileFormat, "--verify", verifyMode]
            if eraseMode != .automatic { argv += ["--erase", eraseMode.rawValue] }
            if !skipBlank { argv.append("--no-skip-blank") }

        case .verify:
            argv += ["verify", file?.path ?? "", "--offset", offset.orZero,
                     "--format", fileFormat, "--verify", verifyMode]

        case .read:
            argv += ["read", "-o", readOutput?.path ?? "", "--start", readStart.orZero,
                     "--format", readFormat]
            if !readLength.trimmed.isEmpty { argv += ["--length", readLength.trimmed] }

        case .erase:
            argv.append("erase")
            if !eraseWholeChip { argv += ["--sector", eraseSector.orZero] }

        case .blank:
            argv += ["blank", "--start", blankStart.orZero]
            if !blankLength.trimmed.isEmpty { argv += ["--length", blankLength.trimmed] }

        case .info:
            argv.append("info")
            if rescan { argv.append("--rescan") }

        case .device:
            argv.append("device")
            if !deviceAction.isEmpty { argv.append(deviceAction) }

        case .protectState:
            argv += ["protect", protectOn ? "on" : "off"]
        }

        // Connection options are accepted on either side of the subcommand.
        if !settings.flashPort.isEmpty { argv += ["-p", settings.flashPort] }
        argv += ["-b", String(settings.flashBaud)]
        if !settings.flashResetDelay.trimmed.isEmpty {
            argv += ["--reset-delay", settings.flashResetDelay.trimmed]
        }
        // The device command changes the stored type; -d would be an override
        // for that one call and fight it.
        if !settings.flashDevice.isEmpty && command != .device {
            argv += ["-d", settings.flashDevice]
        }
        if settings.flashVerbose { argv.append("-v") }

        let workingDirectory = settings.projectRoot
        Task {
            await runner.run(argv, cwd: workingDirectory)
            index.reload()
        }
    }

    // MARK: - Panels

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = index.romBinaries.first?.deletingLastPathComponent()
            ?? settings.romDirectory
        panel.message = "Pick the image to write to the chip."
        if panel.runModal() == .OK { file = panel.url }
    }

    private func chooseReadOutput() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "dump.bin"
        panel.directoryURL = settings.projectRoot
        panel.message = "Where to put what is read off the chip."
        if panel.runModal() == .OK { readOutput = panel.url }
    }

    // MARK: - Settings bindings

    private var bindingFlashPort: Binding<String> {
        Binding(get: { settings.flashPort }, set: { settings.flashPort = $0 })
    }
    private var bindingFlashBaud: Binding<Int> {
        Binding(get: { settings.flashBaud }, set: { settings.flashBaud = $0 })
    }
    private var bindingFlashDevice: Binding<String> {
        Binding(get: { settings.flashDevice }, set: { settings.flashDevice = $0 })
    }
    private var bindingResetDelay: Binding<String> {
        Binding(get: { settings.flashResetDelay }, set: { settings.flashResetDelay = $0 })
    }
    private var bindingVerbose: Binding<Bool> {
        Binding(get: { settings.flashVerbose }, set: { settings.flashVerbose = $0 })
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
    /// An empty address field means the start, which is what the tool's own
    /// default is - passing "0" rather than nothing keeps the command line
    /// showing what will happen.
    var orZero: String { trimmed.isEmpty ? "0" : trimmed }
}
