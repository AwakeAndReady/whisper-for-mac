import Testing
@testable import WhisperForMac

@Test
func parsesRunnerEvents() async throws {
    let event = RunnerEventParser.parse(line: "WFM_EVENT\t{\"kind\":\"status\",\"phase\":\"loading_model\",\"message\":\"Loading model\",\"fraction\":0.25}")

    #expect(event?.kind == .status)
    #expect(event?.phase == "loading_model")
    #expect(event?.message == "Loading model")
    #expect(event?.fraction == 0.25)
}
