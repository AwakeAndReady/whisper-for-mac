import Foundation
import Testing
@testable import WhisperForMac

@Test
func defaultsNextToSource() async throws {
    let input = URL(fileURLWithPath: "/tmp/sample.mov")
    let resolved = OutputDirectoryResolver.resolve(for: input, preferences: .default)

    #expect(resolved.path == "/tmp/Whisper Output")
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
