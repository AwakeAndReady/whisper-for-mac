import Foundation
import Testing
@testable import WhisperForMac

@Test
func elapsedCounterUsesMinutesUntilOneHour() {
    #expect(TranscriptionDurationFormatter.elapsedCounter(for: 8) == "00:08")
    #expect(TranscriptionDurationFormatter.elapsedCounter(for: 754) == "12:34")
    #expect(TranscriptionDurationFormatter.elapsedCounter(for: 3_599) == "59:59")
}

@Test
func elapsedCounterSwitchesToHoursAfterOneHour() {
    #expect(TranscriptionDurationFormatter.elapsedCounter(for: 3_600) == "1:00:00")
    #expect(TranscriptionDurationFormatter.elapsedCounter(for: 4_062) == "1:07:42")
    #expect(TranscriptionDurationFormatter.elapsedCounter(for: 43_389) == "12:03:09")
}

@Test
func successSentenceOmitsZeroUnits() {
    #expect(TranscriptionDurationFormatter.successSentence(for: 42) == "Transcription took 42 s.")
    #expect(TranscriptionDurationFormatter.successSentence(for: 180) == "Transcription took 3 min.")
    #expect(TranscriptionDurationFormatter.successSentence(for: 3_840) == "Transcription took 1 h and 4 min.")
}

@Test
func successSentenceUsesNaturalLongDurations() {
    #expect(TranscriptionDurationFormatter.successSentence(for: 754) == "Transcription took 12 min and 34 s.")
    #expect(TranscriptionDurationFormatter.successSentence(for: 4_062) == "Transcription took 1 h, 7 min and 42 s.")
}
