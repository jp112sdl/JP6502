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

    /// "" means "let the tool pick the port itself", which both flashtool.py
    /// and basicsend.py do when exactly one USB adapter is plugged in.
    var flashPort: String       { didSet { defaults.set(flashPort, forKey: "flashPort") } }
    var flashBaud: Int          { didSet { defaults.set(flashBaud, forKey: "flashBaud") } }
    var flashResetDelay: String { didSet { defaults.set(flashResetDelay, forKey: "flashResetDelay") } }
    var flashDevice: String     { didSet { defaults.set(flashDevice, forKey: "flashDevice") } }
    var flashVerbose: Bool      { didSet { defaults.set(flashVerbose, forKey: "flashVerbose") } }

    var basicPort: String       { didSet { defaults.set(basicPort, forKey: "basicPort") } }
    var basicBaud: Int          { didSet { defaults.set(basicBaud, forKey: "basicBaud") } }

    private init() {
        let bundled = Bundle.main.object(forInfoDictionaryKey: "JP6502ProjectRoot") as? String
        projectRootPath = defaults.string(forKey: "projectRootPath")
            ?? URL(fileURLWithPath: bundled ?? "").standardizedFileURL.path
        pythonPath = defaults.string(forKey: "pythonPath") ?? Shell.pythonWithPySerial()
        makePath = defaults.string(forKey: "makePath") ?? Shell.findFirst(["make"])

        flashPort = defaults.string(forKey: "flashPort") ?? ""
        flashBaud = defaults.object(forKey: "flashBaud") as? Int ?? 225000
        flashResetDelay = defaults.string(forKey: "flashResetDelay") ?? "2.0"
        flashDevice = defaults.string(forKey: "flashDevice") ?? ""
        flashVerbose = defaults.bool(forKey: "flashVerbose")

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

    /// The makefile defaults to `python` and `md5sum`, neither of which a
    /// stock macOS has. Handing make what was actually found keeps the mapdoc
    /// and test targets working without editing the makefile.
    var makeOverrides: [String] {
        var overrides = ["PYTHON_BINARY=\(pythonPath)"]
        overrides.append("MD5_BINARY=\(Shell.findFirst(["md5sum", "gmd5sum", "md5"]))")
        return overrides
    }
}
