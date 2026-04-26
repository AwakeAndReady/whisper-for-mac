import Foundation
import Testing
@testable import WhisperForMac

@Test
func defaultsToDesktop() async throws {
    let input = URL(fileURLWithPath: "/tmp/sample.mov")
    let resolved = OutputDirectoryResolver.resolve(for: input, preferences: .default)
    let desktop = try #require(FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first)

    #expect(resolved.path == desktop.path)
}

@Test
func honorsCustomDirectory() async throws {
    let input = URL(fileURLWithPath: "/tmp/sample.mov")
    var preferences = AppPreferences.default
    preferences.outputLocationMode = .custom
    preferences.customOutputDirectory = URL(fileURLWithPath: "/tmp/custom-output")

    let resolved = OutputDirectoryResolver.resolve(for: input, preferences: preferences)

    #expect(resolved.path == "/tmp/custom-output")
}

@Test
func nextToSourceUsesInputDirectory() async throws {
    let input = URL(fileURLWithPath: "/tmp/source-folder/sample.mov")
    var preferences = AppPreferences.default
    preferences.outputLocationMode = .nextToSource
    preferences.customOutputDirectory = URL(fileURLWithPath: "/tmp/custom-output")

    let resolved = OutputDirectoryResolver.resolve(for: input, preferences: preferences)

    #expect(resolved.path == "/tmp/source-folder")
}
