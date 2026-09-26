import Foundation
import Observation

/// The few things worth remembering between launches: where the checkout is,
/// which interpreter to run the tools with, and the ports and baud rates last
/// used - retyping the port every time is the one thing that would make this
/// slower than the Terminal.
@Observable
final class AppSettings {

    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var projectRootPath: String { didSet { defaults.set(projectRootPath, forKey: "projectRootPath") } }
    var pythonPath: String      { didSet { defaults.set(pythonPath, forKey: "pythonPath") } }
    var makePath: String        { didSet { defaults.set(makePath, forKey: "makePath") } }

    /// CC65_HOME, the prefix cc65 keeps asminc, include, lib and cfg under.
    /// The makefile does not pass it and ca65 cannot always work it out on its
    /// own, so the app hands it over - see Shell.cc65Home().
    var cc65Home: String        { didSet { defaults.set(cc65Home, forKey: "cc65Home") } }

    /// The clock the ROMs are built for. "" leaves it to the makefile, which
    /// is the right answer until the board runs at something else - and the
    /// board does not change often, so it is worth remembering.
    var clockMode: String       { didSet { defaults.set(clockMode, forKey: "clockMode") } }

    /// "" means "let the tool pick the port itself", which both flashtool.py
    /// and basicsend.py do when exactly one USB adapter is plugged in.
    var flashPort: String       { didSet { defaults.set(flashPort, forKey: "flashPort") } }
    var flashBaud: Int          { didSet { defaults.set(flashBaud, forKey: "flashBaud") } }
    var flashResetDelay: String { didSet { defaults.set(flashResetDelay, forKey: "flashResetDelay") } }
    var flashDevice: String     { didSet { defaults.set(flashDevice, forKey: "flashDevice") } }
    var flashVerbose: Bool      { didSet { defaults.set(flashVerbose, forKey: "flashVerbose") } }

    /// The image the Flash tab writes. Kept here rather than in the view so
    /// the GeckOS tab can hand its ROM straight over, and so the choice
    /// survives a relaunch.
    var flashFilePath: String   { didSet { defaults.set(flashFilePath, forKey: "flashFilePath") } }

    /// GeckOS builds for a clock too, but its own way: whole MHz passed as
    /// CLOCK, where Software takes a CLOCK_MODE name. "" leaves both to their
    /// makefiles.
    var geckosClock: String     { didSet { defaults.set(geckosClock, forKey: "geckosClock") } }
    /// What the Makefile calls SHELLS: "" for both shells, or the define that
    /// leaves one of them out.
    var geckosShells: String    { didSet { defaults.set(geckosShells, forKey: "geckosShells") } }
    /// The colours of the text screen, TMS9918 numbers passed as FG and BG.
    /// "" leaves them to the makefile.
    var geckosFG: String        { didSet { defaults.set(geckosFG, forKey: "geckosFG") } }
    var geckosBG: String        { didSet { defaults.set(geckosBG, forKey: "geckosBG") } }
    /// Where the card was last mounted. Volumes come and go, so this is a
    /// starting guess rather than a setting.
    var sdCardPath: String      { didSet { defaults.set(sdCardPath, forKey: "sdCardPath") } }

    var basicPort: String       { didSet { defaults.set(basicPort, forKey: "basicPort") } }
    var basicBaud: Int          { didSet { defaults.set(basicBaud, forKey: "basicBaud") } }

    private init() {
        let bundled = Bundle.main.object(forInfoDictionaryKey: "JP6502ProjectRoot") as? String
        projectRootPath = defaults.string(forKey: "projectRootPath")
            ?? URL(fileURLWithPath: bundled ?? "").standardizedFileURL.path
        pythonPath = defaults.string(forKey: "pythonPath") ?? Shell.pythonWithPySerial()
        makePath = defaults.string(forKey: "makePath") ?? Shell.findFirst(["make"])
        clockMode = defaults.string(forKey: "clockMode") ?? ""
        cc65Home = defaults.string(forKey: "cc65Home") ?? Shell.cc65Home()

        flashPort = defaults.string(forKey: "flashPort") ?? ""
        flashBaud = defaults.object(forKey: "flashBaud") as? Int ?? 225000
        flashResetDelay = defaults.string(forKey: "flashResetDelay") ?? "2.0"
        flashDevice = defaults.string(forKey: "flashDevice") ?? ""
        flashVerbose = defaults.bool(forKey: "flashVerbose")

        flashFilePath = defaults.string(forKey: "flashFilePath") ?? ""
        geckosClock = defaults.string(forKey: "geckosClock") ?? ""
        geckosShells = defaults.string(forKey: "geckosShells") ?? ""
        geckosFG = defaults.string(forKey: "geckosFG") ?? ""
        geckosBG = defaults.string(forKey: "geckosBG") ?? ""
        sdCardPath = defaults.string(forKey: "sdCardPath") ?? ""

        basicPort = defaults.string(forKey: "basicPort") ?? ""
        basicBaud = defaults.object(forKey: "basicBaud") as? Int ?? 19200
    }

    var projectRoot: URL { URL(fileURLWithPath: projectRootPath) }

    var softwareDirectory: URL { projectRoot.appendingPathComponent("Software") }
    var toolsDirectory: URL { softwareDirectory.appendingPathComponent("tools") }
    var basicDirectory: URL { softwareDirectory.appendingPathComponent("basic") }
    var buildDirectory: URL { softwareDirectory.appendingPathComponent("build") }
    var romDirectory: URL { buildDirectory.appendingPathComponent("rom") }
    var loadDirectory: URL { buildDirectory.appendingPathComponent("load") }
    var flashToolsDirectory: URL {
        projectRoot.appendingPathComponent("FlashPROMv2").appendingPathComponent("tools")
    }

    // GeckOS-V2 is a submodule with its own makefile, under the board's own
    // arch folder. A checkout that was cloned without --recursive has the
    // folder and nothing in it, which is why the tab checks for the makefile
    // rather than for the directory.
    var geckosDirectory: URL { projectRoot.appendingPathComponent("GeckOS-V2") }
    var geckosArchDirectory: URL {
        geckosDirectory.appendingPathComponent("arch").appendingPathComponent("jp6502")
    }
    var geckosMakefile: URL { geckosArchDirectory.appendingPathComponent("Makefile") }
    var geckosBootDirectory: URL { geckosArchDirectory.appendingPathComponent("boot") }
    var geckosROM: URL { geckosBootDirectory.appendingPathComponent("geckos.bin") }
    var geckosCardDirectory: URL { geckosBootDirectory.appendingPathComponent("sdcard") }

    var hasGeckOS: Bool { FileManager.default.fileExists(atPath: geckosMakefile.path) }

    var basicSendScript: URL { toolsDirectory.appendingPathComponent("basicsend.py") }
    var basicRecvScript: URL { toolsDirectory.appendingPathComponent("basicrecv.py") }
    var flashToolScript: URL { flashToolsDirectory.appendingPathComponent("flashtool.py") }

    /// A folder is the checkout if the makefile and the flash tool are where
    /// they are in the repository. Anything else and every tab would fail with
    /// a different confusing error.
    var isProjectRootValid: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: softwareDirectory.appendingPathComponent("makefile").path)
            && fm.fileExists(atPath: flashToolScript.path)
    }

    /// What the cc65 tools need in their environment, on top of PATH.
    ///
    /// CC65_HOME rather than CA65_INC: it covers asminc, which is where the
    /// longbranch macro every cc65-generated .s includes lives, and the
    /// include folder cc65 looks for stdlib.h in, and lib and cfg besides. One
    /// variable instead of three, and nothing else in the build changes,
    /// because the makefile's own -I and -C are passed explicitly and come
    /// first.
    var toolchainEnvironment: [String: String] {
        cc65Home.isEmpty ? [:] : ["CC65_HOME": cc65Home]
    }

    var isCC65HomeValid: Bool { Shell.isCC65Home(cc65Home) }

    /// The makefile defaults to `python` and `md5sum`, neither of which a
    /// stock macOS has. Handing make what was actually found keeps the mapdoc
    /// and test targets working without editing the makefile.
    var makeOverrides: [String] {
        var overrides = ["PYTHON_BINARY=\(pythonPath)"]
        overrides.append("MD5_BINARY=\(Shell.findFirst(["md5sum", "gmd5sum", "md5"]))")
        return overrides
    }
}
