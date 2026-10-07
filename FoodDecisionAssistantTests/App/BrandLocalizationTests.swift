import Foundation
import Testing

struct BrandLocalizationTests {
    @Test("The built app contains each approved localized display name", arguments: [
        ("en", "Evenfare"),
        ("zh-Hans", "食衡"),
    ])
    func localizedDisplayNames(localization: String, expected: String) throws {
        let url = try #require(Bundle.main.url(
            forResource: "InfoPlist",
            withExtension: "strings",
            subdirectory: nil,
            localization: localization
        ))
        #expect(url.deletingLastPathComponent().lastPathComponent == "\(localization).lproj")
        let data = try Data(contentsOf: url)
        let values = try #require(try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: String])
        #expect(values["CFBundleDisplayName"] == expected)
        #expect(values.count == 1, "B-1 localizes only the public display name.")
    }

    @Test("Brand changes preserve the installed app identity and executable")
    func installedAppIdentity() {
        #expect(Bundle.main.bundleIdentifier == "com.ning6y6.ShiHeng")
        #expect(Bundle.main.infoDictionary?["CFBundleExecutable"] as? String == "ShiHeng")
        #expect(Bundle.main.bundleURL.lastPathComponent == "ShiHeng.app")
        #expect(Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String == "Evenfare")
    }
}
