import SwiftUI

/// Where the checkout is and which interpreter runs the tools. Nothing here is
/// needed twice: it is set once and remembered.
struct SettingsView: View {
    let settings: AppSettings
    let index: ProjectIndex

    /// nil while the probe below has not answered yet.
    @State private var hasPySerial: Bool?

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder") {
                    HStack {
                        Text(settings.projectRootPath.isEmpty
                             ? "not chosen" : settings.projectRootPath)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Choose…") { chooseRoot() }
                    }
                }
                if settings.isProjectRootValid {
                    Label("Software/makefile and FlashPROMv2/tools/flashtool.py are there.",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Label("Software/makefile or FlashPROMv2/tools/flashtool.py is missing. "
                          + "Pick the folder that holds them.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            } header: {
                Text("Project")
            }

            Section {
                LabeledContent("python") {
                    HStack {
                        TextField("python3", text: bindingPython).frame(minWidth: 220)
                        Button("Detect") { settings.pythonPath = Shell.pythonWithPySerial() }
                            .help("Pick the first python on PATH that has pyserial")
                    }
                }
                switch hasPySerial {
                case .some(true):
                    Label("pyserial is there, so the serial tools will run.",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.green).font(.caption)
                case .some(false):
                    // Which python has the module is the one thing that goes
                    // wrong on a machine with several of them installed, and
                    // the tools can only report it once they are already
                    // running.
                    Label("pyserial is missing from this python. Either point the "
                          + "field at one that has it, or install it: "
                          + "\(settings.pythonPath) -m pip install pyserial",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.caption)
                        .textSelection(.enabled)
                case .none:
                    Label("Checking for pyserial…", systemImage: "clock")
                        .foregroundStyle(.secondary).font(.caption)
                }
                LabeledContent("make") {
                    TextField("make", text: bindingMake).frame(minWidth: 220)
                }
                LabeledContent("CC65_HOME") {
                    HStack {
                        TextField("/usr/local/share/cc65", text: bindingCC65Home)
                            .frame(minWidth: 220)
                        Button("Detect") { settings.cc65Home = Shell.cc65Home() }
                            .help("Look next to ca65, then in the usual prefixes")
                    }
                }
                if settings.isCC65HomeValid {
                    Label("asminc/longbranch.mac is there.", systemImage: "checkmark.circle")
                        .foregroundStyle(.green).font(.caption)
                } else {
                    // The makefile does not set this and ca65 does not always
                    // have a usable default compiled in, so without it the C
                    // projects stop at the first .macpack.
                    Label("No asminc/longbranch.mac under this path. ca65 will not "
                          + "assemble what cc65 generates, and cc65 will not find "
                          + "its own headers. It is the folder holding asminc, "
                          + "include, lib and cfg - next to the bin that has ca65.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.caption)
                }
                Text("Both are run with the PATH a login shell has, so ca65 and "
                     + "the rest of cc65 are found the way they are in a Terminal.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("PATH", value: Shell.searchPath)
                    .font(.caption)
                    .textSelection(.enabled)
            } header: {
                Text("Tools")
            }

            Section {
                LabeledContent("ROM projects", value: String(index.firmwareProjects.count))
                LabeledContent("Loadable programs", value: String(index.loadableProjects.count))
                LabeledContent("Built images", value: String(index.romBinaries.count))
                LabeledContent("BASIC programs", value: String(index.basicPrograms.count))
                LabeledContent("Chips the firmware knows", value: String(index.flashDevices.count))
                Button("Rescan") { index.reload() }
            } header: {
                Text("What was found")
            }
        }
        .formStyle(.grouped)
        .task(id: settings.pythonPath) {
            let python = settings.pythonPath
            hasPySerial = nil
            hasPySerial = await Task.detached { Shell.hasPySerial(python) }.value
        }
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.projectRoot
        panel.message = "Pick the JP6502 checkout - the folder holding Software and FlashPROMv2."
        if panel.runModal() == .OK, let url = panel.url {
            settings.projectRootPath = url.path
            index.reload()
        }
    }

    private var bindingPython: Binding<String> {
        Binding(get: { settings.pythonPath }, set: { settings.pythonPath = $0 })
    }
    private var bindingMake: Binding<String> {
        Binding(get: { settings.makePath }, set: { settings.makePath = $0 })
    }
    private var bindingCC65Home: Binding<String> {
        Binding(get: { settings.cc65Home }, set: { settings.cc65Home = $0 })
    }
}
