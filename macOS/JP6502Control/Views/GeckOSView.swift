import SwiftUI

/// GeckOS-V2, the multitasking OS ported to this board in
/// GeckOS-V2/arch/jp6502. It has its own makefile, its own way of naming the
/// clock, a ROM image of its own and a card to fill: the kernel and the
/// devices are in the ROM, and lsh and the rest are loaded from FAT32.
struct GeckOSView: View {

    enum Target: String, CaseIterable, Identifiable {
        case rom, sdcard, clean
        var id: String { rawValue }

        var title: String {
            switch self {
            case .rom:    return "ROM image"
            case .sdcard: return "Programs for the card"
            case .clean:  return "Clean"
            }
        }

        var detail: String {
            switch self {
            case .rom:    return "make - boot/geckos.bin, 32k, ready for the Flash tab"
            case .sdcard: return "make sdcard - builds apps and sysapps and gathers them in boot/sdcard"
            case .clean:  return "make clean - the ROM, the objects, the card folder and the emulator"
            }
        }
    }

    enum Shells: String, CaseIterable, Identifiable {
        case both = ""
        case videoOnly = "-DNO_SERIAL_SHELL"
        case serialOnly = "-DNO_VIDEO_SHELL"
        var id: String { rawValue }

        var title: String {
            switch self {
            case .both:       return "Both - VDP console and serial line"
            case .videoOnly:  return "VDP console only"
            case .serialOnly: return "Serial line only"
            }
        }
    }

    let settings: AppSettings
    let index: ProjectIndex
    let runner: ProcessRunner
    /// Handing the ROM to the Flash tab, once it has been selected there.
    let showFlashTab: () -> Void

    @State private var target: Target = .rom
    @State private var cards: [Volume] = []
    @State private var rebuildBeforeCopy = true

    var body: some View {
        VSplitView {
            Form {
                buildSection
                romSection
                cardSection
                toolchainSection
            }
            .formStyle(.grouped)
            .frame(minHeight: 300)

            ConsoleView(runner: runner)
                .frame(minHeight: 140)
        }
        .onAppear { refreshCards() }
    }

    // MARK: - Build

    @ViewBuilder
    private var buildSection: some View {
        Section("Build") {
            Picker("Build", selection: $target) {
                ForEach(Target.allCases) { Text($0.title).tag($0) }
            }
            Text(target.detail).font(.caption).foregroundStyle(.secondary)

            Picker("Clock", selection: bindingClock) {
                Text(index.defaultGeckosClock.isEmpty
                     ? "As the makefile has it"
                     : "As the makefile has it - \(index.defaultGeckosClock) MHz")
                    .tag("")
                ForEach(index.geckosClocks, id: \.self) { mhz in
                    Text("\(mhz) MHz").tag(mhz)
                }
            }
            .disabled(target == .clean)

            Picker("Shells", selection: bindingShells) {
                ForEach(Shells.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .disabled(target == .clean)

            Text("The ROM is reassembled on every build, so the clock and the "
                 + "shells take effect without anything being touched on disk. "
                 + "make run, which puts the emulator's serial line on a "
                 + "terminal, is the one target this tab leaves out.")
                .font(.caption).foregroundStyle(.secondary)

            RunBar(title: target == .clean ? "Clean" : "Build",
                   systemImage: target == .clean ? "trash" : "hammer",
                   runner: runner,
                   confirm: target == .clean
                        ? "Remove the ROM, the objects, boot/sdcard and the emulator?" : nil) {
                build()
            }
        }
    }

    // MARK: - ROM

    @ViewBuilder
    private var romSection: some View {
        Section("ROM image") {
            LabeledContent("File", value: "boot/geckos.bin")
            LabeledContent("State", value: describe(settings.geckosROM))
            HStack {
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([settings.geckosROM])
                }
                Button("Write it to the flash") {
                    settings.flashFilePath = settings.geckosROM.path
                    showFlashTab()
                }
            }
            .disabled(!FileManager.default.fileExists(atPath: settings.geckosROM.path))
        }
    }

    // MARK: - SD card

    @ViewBuilder
    private var cardSection: some View {
        Section("SD card") {
            LabeledContent("Card") {
                HStack {
                    Picker("", selection: bindingCard) {
                        Text("none").tag("")
                        ForEach(cards) { card in
                            Text(card.display).tag(card.url.path)
                        }
                        if let chosen, !cards.contains(where: { $0.url.path == chosen.url.path }) {
                            Text(chosen.display).tag(chosen.url.path)
                        }
                    }
                    .labelsHidden()
                    Button("Rescan") { refreshCards() }
                    Button("Choose…") { chooseCard() }
                }
            }

            if let chosen {
                if chosen.isReadOnly {
                    Label("This volume is mounted read only.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.caption)
                } else if !chosen.looksLikeFAT {
                    Label("The card GeckOS reads is FAT32, and this one says "
                          + "\(chosen.format). Copying there will work; the board "
                          + "will not read it.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.caption)
                } else {
                    Label("\(Volume.size(chosen.available)) free of "
                          + "\(Volume.size(chosen.capacity)).",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.green).font(.caption)
                }
            } else if cards.isEmpty {
                Text("No removable volume is mounted. Put the card in, press "
                     + "Rescan, or pick a folder by hand.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            LabeledContent("Programs") {
                HStack {
                    Text(programSummary)
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([settings.geckosCardDirectory])
                    }
                    .disabled(index.geckosPrograms.isEmpty)
                }
            }
            Toggle("Rebuild them first", isOn: $rebuildBeforeCopy)
            Text("Copies into the root of the card, over anything of the same "
                 + "name, and leaves everything else there alone. The ._ files "
                 + "the copy leaves behind are removed afterwards, so GeckOS "
                 + "lists the programs and nothing else.")
                .font(.caption).foregroundStyle(.secondary)

            RunBar(title: "Copy to the card", systemImage: "sdcard",
                   runner: runner,
                   enabled: chosen != nil && chosen?.isReadOnly != true
                        && (rebuildBeforeCopy || !index.geckosPrograms.isEmpty),
                   confirm: chosen.map { "Copy the programs into \($0.name)?" },
                   shortcut: false) {
                copyToCard()
            }
        }
    }

    // MARK: - Toolchain

    @ViewBuilder
    private var toolchainSection: some View {
        Section("Toolchain") {
            ForEach(["xa", "file65", "reloc65"], id: \.self) { tool in
                LabeledContent(tool, value: Shell.find(tool) ?? "not found")
                    .foregroundStyle(Shell.find(tool) == nil ? .orange : .primary)
            }
            Text("xa 2.4.1 or later, with file65 and reloc65 from the same "
                 + "package - brew install xa.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Doing it

    private var chosen: Volume? { Volumes.at(settings.sdCardPath) }

    private var programSummary: String {
        let programs = index.geckosPrograms
        guard !programs.isEmpty else { return "not built yet" }
        let bytes = programs.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return "\(programs.count) files, \(Volume.size(bytes))"
    }

    private func describe(_ file: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        guard let attributes,
              let size = attributes[.size] as? Int,
              let date = attributes[.modificationDate] as? Date else {
            return "not built yet"
        }
        return "\(size) bytes, \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var makeArguments: [String] {
        var argv: [String] = []
        if target != .clean {
            if !settings.geckosClock.isEmpty { argv.append("CLOCK=\(settings.geckosClock)") }
            if !settings.geckosShells.isEmpty { argv.append("SHELLS=\(settings.geckosShells)") }
        }
        return argv
    }

    private func build() {
        var argv = [settings.makePath]
        switch target {
        case .rom:    argv.append("all")
        case .sdcard: argv.append("sdcard")
        case .clean:  argv.append("clean")
        }
        argv += makeArguments

        let workingDirectory = settings.geckosArchDirectory
        Task {
            await runner.run(argv, cwd: workingDirectory)
            index.reload()
        }
    }

    private func copyToCard() {
        guard let card = chosen else { return }
        let workingDirectory = settings.geckosArchDirectory
        let cardDirectory = settings.geckosCardDirectory
        let rebuild = rebuildBeforeCopy
        var makeArgv = [settings.makePath, "sdcard"]
        if !settings.geckosClock.isEmpty { makeArgv.append("CLOCK=\(settings.geckosClock)") }
        if !settings.geckosShells.isEmpty { makeArgv.append("SHELLS=\(settings.geckosShells)") }

        Task {
            if rebuild {
                // make sdcard removes boot/sdcard and fills it again, so the
                // list of files has to be read after it, not before.
                guard await runner.run(makeArgv, cwd: workingDirectory) == 0 else { return }
                index.reload()
            }
            let programs = (try? FileManager.default.contentsOfDirectory(
                at: cardDirectory, includingPropertiesForKeys: nil))?
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
            guard !programs.isEmpty else { return }

            let copy = Shell.findFirst(["cp"])
            let argv = [copy, "-Xv"] + programs.map(\.path) + [card.url.path]
            guard await runner.run(argv, cwd: workingDirectory,
                                   note: "\(programs.count) programs into \(card.url.path)") == 0
            else { return }

            // macOS attaches com.apple.provenance to every file it writes, and
            // on a FAT card an extended attribute is stored in an AppleDouble
            // beside the file - ._lsh next to lsh. cp -X does not prevent it
            // and neither does clearing the attribute on the source: a plain
            // dd write produces one too. Deleting them afterwards does work,
            // and it sticks, because on FAT the ._ file is the only place the
            // attribute lives. Without this GeckOS lists thirty entries where
            // it should list fifteen.
            let shadows = programs.map {
                card.url.appendingPathComponent("._" + $0.lastPathComponent).path
            }
            await runner.run([Shell.findFirst(["rm"]), "-f"] + shadows,
                             cwd: workingDirectory,
                             note: "removing the ._ files the copy left behind")
            refreshCards()
        }
    }

    private func refreshCards() {
        cards = Volumes.removable()
        // A card that was ejected is no longer a choice, and silently keeping
        // its path would copy into a folder in /Volumes that macOS recreated.
        if !settings.sdCardPath.isEmpty
            && !FileManager.default.fileExists(atPath: settings.sdCardPath) {
            settings.sdCardPath = ""
        }
        if settings.sdCardPath.isEmpty, let only = cards.first, cards.count == 1 {
            settings.sdCardPath = only.url.path
        }
    }

    private func chooseCard() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        panel.message = "Pick the root of the card, or a folder to fill instead."
        if panel.runModal() == .OK, let url = panel.url {
            settings.sdCardPath = url.path
            refreshCards()
        }
    }

    // MARK: - Settings bindings

    private var bindingClock: Binding<String> {
        Binding(get: { settings.geckosClock }, set: { settings.geckosClock = $0 })
    }
    private var bindingShells: Binding<String> {
        Binding(get: { settings.geckosShells }, set: { settings.geckosShells = $0 })
    }
    private var bindingCard: Binding<String> {
        Binding(get: { settings.sdCardPath }, set: { settings.sdCardPath = $0 })
    }
}

/// The note the GeckOS tab shows when the submodule has not been checked out.
struct MissingGeckOSNotice: View {
    var body: some View {
        ContentUnavailableView {
            Label("GeckOS-V2 is not checked out", systemImage: "shippingbox")
        } description: {
            Text("It is a submodule, and a plain clone leaves it empty. "
                 + "git submodule update --init --recursive fills it in.")
        }
    }
}
