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

    /// The clock modes common/makefile translates into a clock_mode_flag, in
    /// the order it lists them, and the one it falls back on.
    private(set) var clockModes: [String] = []
    private(set) var defaultClockMode = ""

    /// GeckOS: the programs waiting in boot/sdcard to be put on a card, and
    /// the clock its makefile builds for when it is not told otherwise.
    private(set) var geckosPrograms: [URL] = []
    private(set) var defaultGeckosClock = ""

    /// The clocks GeckOS accepts. Unlike CLOCK_MODE there is no conditional to
    /// read them out of - CLOCK goes straight to xa as -DCLOCK_MHZ, and the
    /// set that makes sense is written down in a comment in jp6502def.i65.
    let geckosClocks = ["1", "2", "4", "8"]

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

        let common = settings.softwareDirectory
            .appendingPathComponent("common").appendingPathComponent("makefile")
        let commonText = (try? String(contentsOf: common, encoding: .utf8)) ?? ""
        clockModes = clockModeNames(in: commonText)
        defaultClockMode = variable("CLOCK_MODE", in: commonText).first ?? ""

        let geckosText = (try? String(contentsOf: settings.geckosMakefile, encoding: .utf8)) ?? ""
        defaultGeckosClock = variable("CLOCK", in: geckosText).first ?? ""
        geckosPrograms = programs(in: settings.geckosCardDirectory)
    }

    /// Everything in boot/sdcard. They are o65 binaries with no extension, so
    /// what is there is what goes on the card - minus anything the Finder left
    /// behind.
    private func programs(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { !$0.lastPathComponent.hasPrefix(".") }
                       .sorted { $0.lastPathComponent < $1.lastPathComponent }
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

    /// The clock modes, taken from the conditional that turns each one into a
    /// clock_mode_flag. Reading them rather than listing them here is what
    /// keeps a mode added to the makefile from needing a change in this app -
    /// and keeps one that was removed out of a picker that would then build
    /// nothing.
    private func clockModeNames(in makefile: String) -> [String] {
        var names: [String] = []
        for line in makefile.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("ifeq") || trimmed.hasPrefix("else ifeq"),
                  let open = trimmed.range(of: "$(CLOCK_MODE)") else { continue }
            var rest = trimmed[open.upperBound...].drop(while: { $0 == "," || $0 == " " })
            if let close = rest.firstIndex(of: ")") { rest = rest[..<close] }
            let name = rest.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !names.contains(name) { names.append(name) }
        }
        return names
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
