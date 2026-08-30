import SwiftUI

/// `make` in Software, with the targets the makefile offers.
struct BuildView: View {

    enum Target: String, CaseIterable, Identifiable {
        case all, test, mapdoc, clean, firmware, loadable
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:      return "Everything"
            case .test:     return "Everything, with checksums"
            case .mapdoc:   return "Check the memory map document"
            case .clean:    return "Clean"
            case .firmware: return "One ROM project"
            case .loadable: return "One loadable program"
            }
        }

        var detail: String {
            switch self {
            case .all:      return "make all - every ROM image and every loadable program"
            case .test:     return "make test - builds everything, then prints an md5 of each binary"
            case .mapdoc:   return "make mapdoc - checks the addresses in MEMORY_MAP.md against the linker output"
            case .clean:    return "make clean - removes the whole build folder"
            case .firmware: return "One image under build/rom, built from its own project folder"
            case .loadable: return "One program under build/load, to be sent to a running machine"
            }
        }
    }

    let settings: AppSettings
    let index: ProjectIndex
    let runner: ProcessRunner

    @State private var target: Target = .all
    @State private var firmwareProject = ""
    @State private var loadableProject = ""
    @State private var parallel = true
    @State private var jobs = 4

    var body: some View {
        OptionsAndOutput(runner: runner) {
            Form {
                Section {
                    Picker("Build", selection: $target) {
                        ForEach(Target.allCases) { Text($0.title).tag($0) }
                    }
                    if target == .firmware {
                        Picker("Project", selection: $firmwareProject) {
                            ForEach(index.firmwareProjects, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    if target == .loadable {
                        Picker("Program", selection: $loadableProject) {
                            ForEach(index.loadableProjects, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Text(target.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Target")
                }

                Section("Options") {
                    Toggle("Build in parallel", isOn: $parallel)
                    if parallel {
                        Stepper("\(jobs) jobs at a time", value: $jobs, in: 2...16)
                    }
                    LabeledContent("Address mode", value: index.addressMode)
                    LabeledContent("make", value: settings.makePath.isEmpty
                                   ? "not found" : settings.makePath)
                }

                if let product {
                    Section("Result") {
                        LabeledContent("File", value: product.lastPathComponent)
                        LabeledContent("State", value: describe(product))
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([product])
                        }
                        .disabled(!FileManager.default.fileExists(atPath: product.path))
                    }
                }

                RunBar(title: target == .clean ? "Clean" : "Build",
                       systemImage: target == .clean ? "trash" : "hammer",
                       runner: runner,
                       enabled: isReady,
                       confirm: target == .clean
                            ? "Remove Software/build and everything in it?" : nil) {
                    build()
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            if firmwareProject.isEmpty { firmwareProject = index.firmwareProjects.first ?? "" }
            if loadableProject.isEmpty { loadableProject = index.loadableProjects.first ?? "" }
        }
    }

    private var isReady: Bool {
        switch target {
        case .firmware: return !firmwareProject.isEmpty
        case .loadable: return !loadableProject.isEmpty
        default:        return true
        }
    }

    /// The one file this build produces, when it produces exactly one.
    private var product: URL? {
        switch target {
        case .firmware: return firmwareProject.isEmpty ? nil : index.romBinary(for: firmwareProject)
        case .loadable: return loadableProject.isEmpty ? nil : index.loadBinary(for: loadableProject)
        default:        return nil
        }
    }

    private func describe(_ file: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        guard let attributes,
              let size = attributes[.size] as? Int,
              let date = attributes[.modificationDate] as? Date else {
            return "not built yet"
        }
        let stamp = date.formatted(date: .abbreviated, time: .shortened)
        return "\(size) bytes, \(stamp)"
    }

    private func build() {
        var argv = [settings.makePath]
        if parallel && target != .clean { argv += ["-j", String(jobs)] }
        switch target {
        case .all:      argv.append("all")
        case .test:     argv.append("test")
        case .mapdoc:   argv.append("mapdoc")
        case .clean:    argv.append("clean")
        case .firmware: argv.append(index.makeTarget(firmware: firmwareProject))
        case .loadable: argv.append(index.makeTarget(loadable: loadableProject))
        }
        argv += settings.makeOverrides

        let workingDirectory = settings.softwareDirectory
        Task {
            await runner.run(argv, cwd: workingDirectory)
            index.reload()
        }
    }
}
