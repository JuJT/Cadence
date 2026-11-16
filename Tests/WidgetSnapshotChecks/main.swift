import Foundation

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }
}

// A snapshot from the original shipping version, before weekly/course summaries.
let legacy = Data("""
{"updatedAt":800000000,"courseMeasured":3600,"courseEstimated":900,"revisions":1800,"isPaused":false}
""".utf8)
let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: legacy)
expect(decoded.weekDays == nil && decoded.upcomingCourses == nil, "Legacy snapshots must remain readable")
expect(decoded.courseMeasured == 3600 && decoded.revisions == 1800, "Legacy real durations must be preserved")

let now = Date(timeIntervalSinceReferenceDate: 800000000)
let days = (0..<7).map { offset in
    WidgetDaySummary(date: now.addingTimeInterval(Double(offset) * 86400), courses: 3600, revisions: 1200, estimated: 600)
}
let courses = (0..<12).map { offset in
    WidgetCourseSummary(title: String(repeating: "é", count: 120),
        start: now.addingTimeInterval(Double(offset) * 3600), end: now.addingTimeInterval(Double(offset + 1) * 3600))
}
let snapshot = WidgetSnapshot(updatedAt: now, courseMeasured: 3600, courseEstimated: 900, revisions: 1800,
    activeSubject: "Français", activeKind: "Révision", isPaused: true,
    nextCourseTitle: "Anglais", nextCourseStart: now.addingTimeInterval(3600),
    weekDays: days, topSubjectName: "Français", upcomingCourses: courses)
let data = try JSONEncoder().encode(snapshot)
expect(data.count < 16_384, "The bounded widget aggregate must fit its transport limit")
let roundTrip = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
expect(roundTrip.weekDays?.count == 7 && roundTrip.upcomingCourses?.count == 12, "Full summaries must survive serialization")
expect(roundTrip.weekDays?.reduce(0, { $0 + $1.measured }) == 33_600, "Measured totals exclude estimated time")
expect(CompactDuration.text(.infinity) == "0 min" && CompactDuration.clock(.nan) == "00:00:00", "Invalid duration input must never crash a widget")
print("WidgetSnapshot: legacy decoding, real-data round trip, transport size, accounting separation and safe duration formatting passed.")

// Pure binary fixtures, with fictitious group names. No keychain or profile read.
func words(_ values: [UInt32], little: Bool) -> Data {
    Data(values.flatMap { value in
        let shifts: [UInt32] = little ? [0, 8, 16, 24] : [24, 16, 8, 0]
        return shifts.map { UInt8((value >> $0) & 255) }
    })
}
func executable(groups: [String]) throws -> Data {
    let plist = try PropertyListSerialization.data(fromPropertyList: ["keychain-access-groups": groups], format: .xml, options: 0)
    let blob = words([0xfade7171, UInt32(8 + plist.count)], little: false) + plist
    let signature = words([0xfade0cc0, UInt32(20 + blob.count), 1, 5, 20], little: false) + blob
    let header = words([0xfeedfacf, 0x0100000c, 0, 2, 1, 16, 0, 0], little: true)
    let command = words([0x1d, 16, 48, UInt32(signature.count)], little: true)
    return header + command + signature
}
let privateName = "FAKETEAM12.com.example.cadenza.renamed"
let sharedName = "FAKETEAM12.com.example.shared.random-suffix"
let signedFixture = try executable(groups: [privateName, sharedName, sharedName, "FAKETEAM12.*", "invalid/control\n", "UNSIGNED00.com.example"])
expect(SignedKeychainGroups.groups(in: signedFixture) == [privateName, sharedName], "Read exact renamed groups, rejecting wildcards/placeholders and duplicates")
let fatHeader = words([0xcafebabe, 1, 0x0100000c, 0, 28, UInt32(signedFixture.count), 0], little: false)
expect(SignedKeychainGroups.groups(in: fatHeader + signedFixture) == [privateName, sharedName], "Fat architecture offsets are relative to their own Mach-O slice")
let fatWide = words([0xcafebabf, 1, 0x0100000c, 0, 0, 40, 0, UInt32(signedFixture.count), 0, 0], little: false)
expect(SignedKeychainGroups.groups(in: fatWide + signedFixture) == [privateName, sharedName], "Fat64 architecture offsets remain bounded")
let padded = Data([0, 0, 0, 0]) + signedFixture
expect(SignedKeychainGroups.groups(in: padded.dropFirst(4)) == [privateName, sharedName], "Data slice indices must not cause an invalid read")
for prefix in [0, 4, 27, 31, 40, 49, signedFixture.count - 1] {
    expect(SignedKeychainGroups.groups(in: signedFixture.prefix(prefix)).isEmpty, "Truncated signatures must fail safely")
}
for (offset, value) in [(16, UInt32.max), (36, UInt32.max), (40, UInt32.max), (52, UInt32.max), (64, UInt32.max)] {
    var malformed = signedFixture
    malformed.replaceSubrange(offset..<(offset + 4), with: words([value], little: offset < 48))
    expect(SignedKeychainGroups.groups(in: malformed).isEmpty, "Malformed counts/lengths/offsets must fail safely")
}
expect(SignedKeychainGroups.groups(in: Data(repeating: 0, count: SignedKeychainGroups.maximumFileBytes + 1)).isEmpty, "Oversized executables are rejected before parsing")
let excessiveGroups = try executable(groups: Array(repeating: sharedName, count: 65))
expect(SignedKeychainGroups.groups(in: excessiveGroups).isEmpty, "Unbounded group lists must be rejected")
print("SignedKeychainGroups: exact renamed groups, fat slices, truncation, malicious offsets and resource limits passed without keychain access.")
