import Foundation
import Observation

/// What is in the checkout right now: which projects the makefile builds,
/// which binaries are on disk, which BASIC programs are there, and which chips
/// the programmer firmware knows.
///
/// All of it is read from the repository rather than written down here, so
/// adding a project to the makefile or a chip to Device.h shows up in the
/// pickers without touching this app.
@Observable
final class ProjectIndex {

    private(set) var firmwareProjects: [String] = []
    private(set) var loadableProjects: [String] = []
    private(set) var romBinaries: [URL] = []
    private(set) var loadBinaries: [URL] = []
    private(set) var basicPrograms: [URL] = []
    private(set) var flashDevices: [String] = []

    /// What the makefile calls it: the .ext in build/rom/os1.ext.bin.
    private(set) var addressMode = "ext"

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        reload()
    }

    func reload() {
        let makefile = settings.softwareDirectory.appendingPathComponent("makefile")
        let text = (try? String(contentsOf: makefile, encoding: .utf8)) ?? ""
        firmwareProjects = variable("FIRMWARE_PROJECTS", in: text)
        loadableProjects = variable("LOADABLE_PROJECTS", in: text)
        addressMode = variable("ADDRESS_MODE", in: text).first ?? "ext"

        romBinaries = binaries(in: settings.romDirectory)
        loadBinaries = binaries(in: settings.loadDirectory)

        let basics = (try? FileManager.default.contentsOfDirectory(
            at: settings.basicDirectory, includingPropertiesForKeys: nil)) ?? []
        basicPrograms = basics.filter { $0.pathExtension.uppercased() == "BAS" }
                              .sorted { $0.lastPathComponent < $1.lastPathComponent }

        flashDevices = deviceNames()
    }

    /// The firmware binary the makefile would produce for a project, whether
    /// or not it has been built yet.
    func romBinary(for project: String) -> URL {
        settings.romDirectory.appendingPathComponent("\(project).\(addressMode).bin")
    }

    func loadBinary(for project: String) -> URL {
        settings.loadDirectory.appendingPathComponent("\(project).load.bin")
    }

    /// The make target for one project, which is just the file it produces -
    /// the makefile has a pattern rule for each.
    func makeTarget(firmware project: String) -> String {
        "build/rom/\(project).\(addressMode).bin"
    }

    func makeTarget(loadable project: String) -> String {
        "build/load/\(project).load.bin"
    }

    private func binaries(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.pathExtension == "bin" }
                       .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A make variable's words, with the backslash continuations the project
    /// lists are written across joined back up first.
    private func variable(_ name: String, in makefile: String) -> [String] {
        var joined = ""
        var collecting = false
        for rawLine in makefile.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if !collecting {
                guard line.hasPrefix(name) else { continue }
                let rest = line.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
                guard rest.hasPrefix("=") else { continue }   // not FIRMWARE_PROJECTS_FOLDER
                joined = String(rest.dropFirst())
                collecting = true
            } else {
                joined += " " + line
            }
            if joined.hasSuffix("\\") {
                joined.removeLast()
            } else {
                break
            }
        }
        return joined.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }

    /// The chip names in the firmware's FLASH_TYPES table. They are the last
    /// field of each row, in quotes.
    private func deviceNames() -> [String] {
        let header = settings.projectRoot
            .appendingPathComponent("FlashPROMv2")
            .appendingPathComponent("Device.h")
        guard let text = try? String(contentsOf: header, encoding: .utf8) else { return [] }

        var names: [String] = []
        for line in text.components(separatedBy: .newlines) {
            guard line.contains("ID_SEQ_"), let quote = line.range(of: "\"") else { continue }
            let rest = line[quote.upperBound...]
            guard let end = rest.range(of: "\"") else { continue }
            let name = String(rest[..<end.lowerBound])
            if !name.isEmpty && !names.contains(name) { names.append(name) }
        }
        return names
    }
}
