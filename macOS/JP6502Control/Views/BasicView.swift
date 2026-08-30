import SwiftUI

/// basicsend.py and basicrecv.py, which talk to the 6502 itself over the
/// 6551's port. Both wait up to two minutes for the machine, so the order of
/// the two ends does not matter - but something has to be typed over there.
struct BasicView: View {

    enum Direction: String, CaseIterable, Identifiable {
        case send, receive
        var id: String { rawValue }
        var title: String { self == .send ? "Send to the machine" : "Fetch from the machine" }
        /// What has to be typed on the 6502 for this to go anywhere.
        var machineCommand: String { self == .send ? "LOAD \"@\"" : "SAVE \"@\"" }
    }

    let settings: AppSettings
    let index: ProjectIndex
    let runner: ProcessRunner

    @State private var direction: Direction = .send
    @State private var program: URL?
    @State private var asIs = false
    @State private var preview = ""

    @State private var destination: URL?
    @State private var toWindow = false
    @State private var overwrite = false

    var body: some View {
        OptionsAndOutput(runner: runner) {
            Form {
                Section("Machine") {
                    PortPicker(selection: bindingPort)
                    LabeledContent("Baud") {
                        BaudField(baud: bindingBaud, presets: [4800, 9600, 19200, 38400])
                    }
                    Text("19200 is what _acia_init sets.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Picker("Direction", selection: $direction) {
                        ForEach(Direction.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if direction == .send { sendOptions } else { receiveOptions }

                    Label("Type \(direction.machineCommand) on the 6502. Either end "
                          + "can be started first; this one waits two minutes.",
                          systemImage: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Transfer")
                }

                RunBar(title: direction == .send ? "Send" : "Receive",
                       systemImage: direction == .send ? "arrow.up.circle" : "arrow.down.circle",
                       runner: runner, enabled: isReady) {
                    run()
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            if program == nil { program = index.basicPrograms.first }
            loadPreview()
        }
        .onChange(of: program) { _, _ in loadPreview() }
    }

    @ViewBuilder
    private var sendOptions: some View {
        LabeledContent("Program") {
            HStack {
                Picker("", selection: $program) {
                    Text("none").tag(URL?.none)
                    ForEach(index.basicPrograms, id: \.self) { url in
                        Text(url.lastPathComponent).tag(URL?.some(url))
                    }
                    if let program, !index.basicPrograms.contains(program) {
                        Text(program.lastPathComponent).tag(URL?.some(program))
                    }
                }
                .labelsHidden()
                Button("Browse…") { chooseProgram() }
            }
        }
        Toggle("Send the text exactly as written", isOn: $asIs)
        Text(asIs
             ? "Lowercase keywords arrive as they are, and the tokeniser only knows uppercase ones."
             : "Keywords are uppercased on the way out; text inside quotes is left alone.")
            .font(.caption).foregroundStyle(.secondary)

        if !preview.isEmpty {
            LabeledContent("Listing") {
                ScrollView {
                    Text(preview)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 120)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    @ViewBuilder
    private var receiveOptions: some View {
        Toggle("Show it here instead of writing a file", isOn: $toWindow)
        if !toWindow {
            LabeledContent("Write to") {
                HStack {
                    Text(destination?.lastPathComponent ?? "not chosen")
                        .foregroundStyle(destination == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose…") { chooseDestination() }
                }
            }
            Toggle("Overwrite a file that is already there", isOn: $overwrite)
        }
        Text("A listing that stops early is not written at all - half a program "
             + "looks exactly like a whole one.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private var isReady: Bool {
        direction == .send ? program != nil : (toWindow || destination != nil)
    }

    private func run() {
        var argv = [settings.pythonPath, "-u"]
        switch direction {
        case .send:
            argv += [settings.basicSendScript.path, program?.path ?? ""]
            if asIs { argv.append("--as-is") }
        case .receive:
            argv += [settings.basicRecvScript.path, toWindow ? "-" : (destination?.path ?? "")]
            if !toWindow && overwrite { argv.append("-f") }
        }
        if !settings.basicPort.isEmpty { argv += ["-p", settings.basicPort] }
        argv += ["-b", String(settings.basicBaud)]

        let workingDirectory = settings.toolsDirectory
        let note = "Type \(direction.machineCommand) on the 6502."
        Task {
            await runner.run(argv, cwd: workingDirectory, note: note)
            index.reload()
        }
    }

    private func loadPreview() {
        guard let program, let text = try? String(contentsOf: program, encoding: .utf8) else {
            preview = ""
            return
        }
        preview = text
    }

    private func chooseProgram() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.basicDirectory
        panel.message = "Pick the BASIC program to send."
        if panel.runModal() == .OK { program = panel.url }
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PROGRAM.BAS"
        panel.directoryURL = settings.basicDirectory
        panel.message = "Where to put the listing the machine sends."
        if panel.runModal() == .OK {
            destination = panel.url
            // The save panel has already asked about replacing it, so the tool
            // being asked to refuse would only produce a second question.
            overwrite = true
        }
    }

    private var bindingPort: Binding<String> {
        Binding(get: { settings.basicPort }, set: { settings.basicPort = $0 })
    }
    private var bindingBaud: Binding<Int> {
        Binding(get: { settings.basicBaud }, set: { settings.basicBaud = $0 })
    }
}
