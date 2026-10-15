import Foundation
import Testing
@testable import PetCore

@Suite struct AIChooserTests {
    func response(_ inner: String, stop: String = "end_turn") -> Data {
        let escaped = inner.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return Data(#"{"type":"message","stop_reason":"\#(stop)","content":[{"type":"thinking","thinking":""},{"type":"text","text":"\#(escaped)"}]}"#.utf8)
    }

    @Test func acceptsAValidCandidateWithSpeech() {
        let c = AIChooser.parseResponse(response(#"{"scene":"ironman/fly_across","speech":"Morning!"}"#), candidates: ["ironman/fly_across"])
        #expect(c == AIChoice(key: "ironman/fly_across", speech: "Morning!"))
    }

    @Test func rejectsUnknownKeysRefusalsAndTruncation() {
        let ok: Set = ["a/b"]
        #expect(AIChooser.parseResponse(response(#"{"scene":"x/y","speech":""}"#), candidates: ok) == nil)
        #expect(AIChooser.parseResponse(response(#"{"scene":"a/b","speech":""}"#, stop: "refusal"), candidates: ok) == nil)
        #expect(AIChooser.parseResponse(response(#"{"scene":"a/b""#, stop: "max_tokens"), candidates: ok) == nil)
        #expect(AIChooser.parseResponse(Data("not json".utf8), candidates: ok) == nil)
    }

    @Test func emptySpeechMeansNone() {
        #expect(AIChooser.parseResponse(response(#"{"scene":"a/b","speech":"  "}"#), candidates: ["a/b"])?.speech == nil)
    }

    @Test func speechIsCappedSingleLineAndFiltered() {
        #expect(AIChooser.sanitize(String(repeating: "a", count: 200))!.count == AIChooser.maxSpeechLength)
        #expect(AIChooser.sanitize("Late night again? Maybe get some sleep soon, okay friend?") == "Late night again?")
        let cut = AIChooser.sanitize("Ninety minutes of focus deserves a little stretch break now")!
        #expect(cut.count <= AIChooser.maxSpeechLength && cut.hasSuffix("…") && !cut.contains("  "))
        #expect(cut.dropLast().last != " ")
        #expect(AIChooser.sanitize("line one\nline two") == "line one line two")
        #expect(AIChooser.sanitize("well shit") == nil)
        #expect(AIChooser.sanitize("Hi 👋") == "Hi")
    }

    @Test func schemaOnlyAllowsTheCandidates() throws {
        let schema = AIChooser.schema(keys: ["a/b", "c/d"])
        let data = try JSONEncoder().encode(schema)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""enum":["a\/b","c\/d"]"#) || text.contains(#""enum":["a/b","c/d"]"#))
        #expect(text.contains(#""additionalProperties":false"#))
    }

    @Test func requestUsesLowEffortStructuredOutput() throws {
        let body = AIChooser.requestBody(model: "claude-haiku-5-5", summary: AIContextSummary(state: .idle, appCategory: nil, date: Date(), recentScenes: []),
                                         candidates: [])
        guard case .object(let o) = body, case .object(let oc)? = o["output_config"] else { Issue.record("shape"); return }
        #expect(o["model"]?.string == "claude-haiku-5-5")
        #expect(oc["effort"]?.string == "low")
        #expect(o["thinking"] == nil) // never sent: the model decides
    }

    @Test func summaryHidesTitlesUnlessGiven() throws {
        let s = AIContextSummary(state: .activeWork, appCategory: "developer-tools", date: Date(timeIntervalSince1970: 0), recentScenes: ["x"])
        #expect(s.windowTitle == nil)
        let text = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        #expect(!text.contains("windowTitle"))
    }
}

@Suite struct OpenAIChooserTests {
    func response(_ content: String?, finish: String = "stop", refusal: String? = nil) -> Data {
        var message: [String: JSONValue] = ["role": .string("assistant"), "content": content.map { .string($0) } ?? .null]
        message["refusal"] = refusal.map { .string($0) } ?? .null
        let root: JSONValue = .object(["choices": .array([.object(["index": .number(0), "finish_reason": .string(finish),
                                                                    "message": .object(message)])])])
        return try! JSONEncoder().encode(root)
    }

    @Test func requestUsesStrictJSONSchema() {
        let body = AIChooser.openAIRequestBody(model: "gpt-6-luna", summary: AIContextSummary(state: .idle, appCategory: nil, date: Date(), recentScenes: []),
                                               candidates: [])
        guard case .object(let o) = body, case .object(let rf)? = o["response_format"], case .object(let js)? = rf["json_schema"],
              case .array(let msgs)? = o["messages"] else { Issue.record("shape"); return }
        #expect(rf["type"]?.string == "json_schema")
        #expect(js["strict"]?.bool == true)
        #expect(js["name"]?.string == "scene_choice")
        #expect(msgs.count == 2)
        #expect(o["reasoning_effort"]?.string == "low")
    }

    @Test func reasoningEffortOnlyForReasoningModels() {
        #expect(AIChooser.isOpenAIReasoningModel("gpt-6-luna"))
        #expect(AIChooser.isOpenAIReasoningModel("gpt-5.6-luna"))
        #expect(AIChooser.isOpenAIReasoningModel("o4-mini"))
        #expect(!AIChooser.isOpenAIReasoningModel("gpt-4.1-mini"))
        #expect(!AIChooser.isOpenAIReasoningModel("gpt-4o-mini"))
        guard case .object(let o) = AIChooser.openAIRequestBody(model: "gpt-4.1-mini", summary: AIContextSummary(state: .idle, appCategory: nil, date: Date(), recentScenes: []), candidates: []) else { return }
        #expect(o["reasoning_effort"] == nil)
    }

    @Test func parsesAValidChoice() {
        let c = AIChooser.parseOpenAIResponse(response(#"{"scene":"batman/cape_glide","speech":"Evening."}"#), candidates: ["batman/cape_glide"])
        #expect(c == AIChoice(key: "batman/cape_glide", speech: "Evening."))
    }

    @Test func rejectsRefusalsTruncationAndUnknownKeys() {
        let ok: Set = ["a/b"]
        #expect(AIChooser.parseOpenAIResponse(response(nil, refusal: "I can't help with that."), candidates: ok) == nil)
        #expect(AIChooser.parseOpenAIResponse(response(#"{"scene":"a/b""#, finish: "length"), candidates: ok) == nil)
        #expect(AIChooser.parseOpenAIResponse(response(#"{"scene":"z/z","speech":""}"#), candidates: ok) == nil)
        #expect(AIChooser.parseOpenAIResponse(Data("{}".utf8), candidates: ok) == nil)
    }

    @Test func modelSettingIsPerProvider() {
        var s = AppSettings()
        #expect(s.aiProvider == .openai && s.aiModel == "gpt-6-luna")
        s.aiModel = "gpt-4.1-mini"
        s.aiProvider = .anthropic
        #expect(s.aiModel == "claude-haiku-5-5")
        s.aiProvider = .openai
        #expect(s.aiModel == "gpt-4.1-mini")
    }
}
