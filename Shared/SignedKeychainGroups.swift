import Foundation

/// Reads only this process's executable metadata using the public Mach-O format.
/// Returned names are candidates, never proof of permission: Security still
/// authorizes every SecItem operation. No signature or profile is modified.
/// Formats: Apple cctools loader.h and xnu osfmk/kern/cs_blobs.h.
enum SignedKeychainGroups {
    static let maximumFileBytes = 32 * 1024 * 1024
    static let current = values(in: Bundle.main, key: "keychain-access-groups")
    private static let app: Bundle? = {
        if Bundle.main.bundleURL.pathExtension == "appex" {
            return Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent())
        }
        return Bundle.main
    }()
    private static let widget: Bundle? = {
        if Bundle.main.bundleURL.pathExtension == "appex" { return Bundle.main }
        guard let directory = Bundle.main.builtInPlugInsURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        return urls.compactMap { Bundle(url: $0) }.first { bundle in
            let attributes = bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any]
            return attributes?["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension"
        }
    }()
    static let commonKeychain: [String] = {
        let widgetGroups = Set(values(in: widget, key: "keychain-access-groups"))
        return values(in: app, key: "keychain-access-groups").filter { group in
            widgetGroups.contains(group) && ![app?.bundleIdentifier, widget?.bundleIdentifier].compactMap { $0 }.contains { group.hasSuffix("." + $0) }
        }
    }()
    static let commonContainers: [String] = {
        let key = "com.apple.security.application-groups"
        let widgetGroups = Set(values(in: widget, key: key))
        return values(in: app, key: key).filter { widgetGroups.contains($0) }
    }()
    private static func values(in bundle: Bundle?, key: String) -> [String] {
        guard let url = bundle?.executableURL,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= maximumFileBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        return groups(in: data, key: key)
    }

    static func groups(in data: Data, key: String = "keychain-access-groups") -> [String] {
        guard data.count >= 28, data.count <= maximumFileBytes else { return [] }
        let reader = Reader(data: data)
        guard let magic = reader.word(0, little: false) else { return [] }
        if magic == 0xcafebabe || magic == 0xcafebabf {
            guard let count = reader.word(4, little: false), count > 0, count <= 16 else { return [] }
            let wide = magic == 0xcafebabf
            let stride = wide ? 32 : 20
            guard 8 + Int(count) * stride <= data.count else { return [] }
            for index in 0..<Int(count) {
                let record = 8 + index * stride
                let offset: Int?
                let size: Int?
                if wide {
                    offset = reader.boundedWide(record + 8)
                    size = reader.boundedWide(record + 16)
                } else {
                    offset = reader.word(record + 8, little: false).map(Int.init)
                    size = reader.word(record + 12, little: false).map(Int.init)
                }
                guard let offset, let size, offset >= 8 + Int(count) * stride,
                      size >= 28, offset <= data.count, size <= data.count - offset else { continue }
                let groups = thin(reader, base: offset, size: size, key: key)
                if !groups.isEmpty { return groups }
            }
            return []
        }
        return thin(reader, base: 0, size: data.count, key: key)
    }

    private static func thin(_ r: Reader, base: Int, size: Int, key: String) -> [String] {
        guard let magic = r.word(base, little: true), magic == 0xfeedfacf || magic == 0xfeedface,
              let count = r.word(base + 16, little: true), count <= 4096,
              let commandBytes = r.word(base + 20, little: true) else { return [] }
        let header = magic == 0xfeedfacf ? 32 : 28
        guard size >= header, Int(commandBytes) <= size - header else { return [] }
        var position = base + header
        let commandEnd = position + Int(commandBytes)
        for _ in 0..<Int(count) {
            guard position <= commandEnd - 8,
                  let command = r.word(position, little: true),
                  let length = r.word(position + 4, little: true), length >= 8,
                  Int(length) <= commandEnd - position else { return [] }
            if command == 0x1d { // LC_CODE_SIGNATURE, linkedit_data_command
                guard length >= 16,
                      let offset = r.word(position + 8, little: true),
                      let bytes = r.word(position + 12, little: true),
                      Int(offset) >= header + Int(commandBytes), Int(offset) <= size,
                      Int(bytes) <= size - Int(offset) else { return [] }
                return signature(r, start: base + Int(offset), size: Int(bytes), key: key)
            }
            position += Int(length)
        }
        return []
    }

    private static func signature(_ r: Reader, start: Int, size: Int, key: String) -> [String] {
        guard size >= 12, r.word(start, little: false) == 0xfade0cc0,
              let length = r.word(start + 4, little: false), Int(length) <= size, length >= 12,
              let count = r.word(start + 8, little: false), count <= 128,
              12 + Int(count) * 8 <= Int(length) else { return [] }
        for index in 0..<Int(count) {
            let entry = start + 12 + index * 8
            guard r.word(entry, little: false) == 5,
                  let offset = r.word(entry + 4, little: false),
                  Int(offset) >= 12 + Int(count) * 8, Int(offset) <= Int(length) - 8 else { continue }
            let blob = start + Int(offset)
            guard r.word(blob, little: false) == 0xfade7171,
                  let blobLength = r.word(blob + 4, little: false), blobLength >= 8,
                  blobLength <= 131_072, Int(blobLength) <= Int(length) - Int(offset),
                  let payload = r.bytes(blob + 8, count: Int(blobLength) - 8),
                  let plist = try? PropertyListSerialization.propertyList(from: payload, options: [], format: nil),
                  let dictionary = plist as? [String: Any],
                  let groups = dictionary[key] as? [String], groups.count <= 64 else { continue }
            var seen = Set<String>()
            return groups.filter { value in
                !value.isEmpty && value.utf8.count <= 512 && !value.contains("*") &&
                !value.hasPrefix("UNSIGNED00.") &&
                value.utf8.allSatisfy { (45...46).contains($0) || (48...57).contains($0) || (65...90).contains($0) || $0 == 95 || (97...122).contains($0) } &&
                seen.insert(value).inserted
            }
        }
        // Unsigned, unsupported or DER-only executables use the existing default
        // and profile candidates. Never infer a grant from an unparsed blob.
        return []
    }

    private struct Reader {
        let data: Data
        func word(_ offset: Int, little: Bool) -> UInt32? {
            guard offset >= 0, offset <= data.count - 4 else { return nil }
            let bytes = (0..<4).map { UInt32(data[data.startIndex + offset + $0]) }
            if little { return bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 24 }
            return bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]
        }
        func boundedWide(_ offset: Int) -> Int? {
            guard let high = word(offset, little: false), let low = word(offset + 4, little: false) else { return nil }
            let value = UInt64(high) << 32 | UInt64(low)
            guard value <= UInt64(data.count) else { return nil }
            return Int(value)
        }
        func bytes(_ offset: Int, count: Int) -> Data? {
            guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else { return nil }
            return data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + count))
        }
    }
}
