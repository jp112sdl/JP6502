import Foundation

/// A mounted volume a card could be.
struct Volume: Identifiable, Hashable {
    let url: URL
    let name: String
    /// What the Finder calls the filesystem, e.g. "MS-DOS (FAT32)".
    let format: String
    let capacity: Int
    let available: Int
    let isReadOnly: Bool

    var id: String { url.path }

    var display: String {
        var parts = [name.isEmpty ? url.lastPathComponent : name]
        if !format.isEmpty { parts.append(format) }
        if capacity > 0 { parts.append(Volume.size(capacity)) }
        return parts.joined(separator: " - ")
    }

    /// GeckOS reads FAT32. Anything else is almost certainly the wrong volume,
    /// but it is a warning rather than a refusal: a card can be mounted from an
    /// image, and what the Finder calls a filesystem is not a contract.
    var looksLikeFAT: Bool {
        let upper = format.uppercased()
        return upper.contains("FAT") || upper.contains("MS-DOS")
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

enum Volumes {

    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
        .volumeIsInternalKey, .volumeLocalizedFormatDescriptionKey,
        .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsReadOnlyKey,
    ]

    /// The volumes a card reader would show up as. The startup disk is left
    /// out: copying the programs into the root of it is never what was meant.
    static func removable() -> [Volume] {
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return mounted.compactMap { url -> Volume? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let removable = (values.volumeIsRemovable ?? false) || (values.volumeIsEjectable ?? false)
            guard removable, values.volumeIsInternal != true else { return nil }
            return describe(url, values)
        }
        .sorted { $0.url.path < $1.url.path }
    }

    /// One volume by path, for a folder that was picked by hand or remembered
    /// from last time.
    static func at(_ path: String) -> Volume? {
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try? url.resourceValues(forKeys: Set(keys))
        return describe(url, values)
    }

    private static func describe(_ url: URL, _ values: URLResourceValues?) -> Volume {
        Volume(url: url,
               name: values?.volumeName ?? url.lastPathComponent,
               format: values?.volumeLocalizedFormatDescription ?? "",
               capacity: values?.volumeTotalCapacity ?? 0,
               available: values?.volumeAvailableCapacity ?? 0,
               isReadOnly: values?.volumeIsReadOnly ?? false)
    }
}
