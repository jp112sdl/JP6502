import Foundation
import IOKit
import IOKit.serial

struct SerialPort: Identifiable, Hashable {
    /// The /dev/cu.* path, which is what every tool here wants after -p.
    let path: String
    /// What the adapter calls itself, when it says. Two USB adapters plugged
    /// in at once is the normal case - the programmer on one, the 6502 on the
    /// other - and the /dev name alone does not say which is which.
    let label: String

    var id: String { path }

    var display: String {
        let name = (path as NSString).lastPathComponent
        return label.isEmpty ? name : "\(name) - \(label)"
    }

    /// USB adapters first: the built-in Bluetooth port is never the one meant.
    var looksLikeUSB: Bool {
        let name = path.lowercased()
        return name.contains("usbserial") || name.contains("usbmodem")
            || name.contains("wchusb") || name.contains("slab")
            || name.contains("ftdi") || name.contains("cu.usb")
    }
}

enum SerialPorts {

    static func list() -> [SerialPort] {
        var ports = fromIOKit()
        if ports.isEmpty { ports = fromDev() }
        return ports.sorted {
            if $0.looksLikeUSB != $1.looksLikeUSB { return $0.looksLikeUSB }
            return $0.path < $1.path
        }
    }

    private static func fromIOKit() -> [SerialPort] {
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return [] }
        let query = matching as NSMutableDictionary
        query[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           query as CFDictionary,
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var ports: [SerialPort] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let path = string(service, kIOCalloutDeviceKey) else { continue }
            ports.append(SerialPort(path: path, label: describe(service)))
        }
        return ports
    }

    /// Everything that looks like a callout device, for the case where the
    /// registry query comes back empty.
    private static func fromDev() -> [SerialPort] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return names.filter { $0.hasPrefix("cu.") }
                    .map { SerialPort(path: "/dev/\($0)", label: "") }
    }

    private static func describe(_ service: io_object_t) -> String {
        for key in ["USB Product Name", "Product Name", kIOTTYDeviceKey] {
            if let value = searchUp(service, key), !value.isEmpty { return value }
        }
        return ""
    }

    private static func string(_ service: io_object_t, _ key: String) -> String? {
        let value = IORegistryEntryCreateCFProperty(service, key as CFString,
                                                    kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? String
    }

    /// The name usually sits on the USB device a few levels up the tree, not
    /// on the serial node itself.
    private static func searchUp(_ service: io_object_t, _ key: String) -> String? {
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        let value = IORegistryEntrySearchCFProperty(service, kIOServicePlane,
                                                    key as CFString,
                                                    kCFAllocatorDefault, options)
        return value as? String
    }
}
