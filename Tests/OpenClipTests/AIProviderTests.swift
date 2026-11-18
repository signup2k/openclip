import XCTest
@testable import OpenClip

@MainActor
final class AIProviderTests: XCTestCase {
    func testExplanationPromptAndSelectionFillBrowserPlaceholderWithoutExtraColon() throws {
        let provider = BrowserRedirectProvider(template: "https://example.com/?q={text}")
        let prompt = "搜索、分析后，ELI25，用中文简洁解释："
        let url = try provider.requestURL(prompt: prompt, text: "A&B + 中文")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
        XCTAssertEqual(query, prompt + "\nA&B + 中文")
    }

    // MARK: - Apple Intelligence

    func testAppleIntelligenceRejectsEmptyText() async {
        let provider = AppleIntelligenceProvider()
        do {
            _ = try await provider.process(prompt: "Summarize", text: "   \n")
            XCTFail("Expected emptyInput error")
        } catch let error as AIError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Cloud API

    func testCloudAPIRejectsMissingKey() async {
        let provider = CloudAPIProvider(apiKey: "", model: "gpt-4o-mini")
        do {
            _ = try await provider.process(prompt: "Fix", text: "hello")
            XCTFail("Expected missingAPIKey")
        } catch let error as AIError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Ollama

    func testOllamaNormalizesEmptyBaseURLAndModel() {
        let provider = OllamaProvider(baseURL: "", model: "  ")
        XCTAssertEqual(provider.baseURL, "http://localhost:11434")
        XCTAssertEqual(provider.model, "llama3")
    }

    // MARK: - Extract Result & Reasoning Tags

    func testExtractResultText() {
        // Standard XML tags
        XCTAssertEqual(AIRequestSupport.extractResultText("<result>Clean text</result>"), "Clean text")
        XCTAssertEqual(AIRequestSupport.extractResultText("<output>Clean output</output>"), "Clean output")
        
        // DeepSeek/reasoning <think> tag stripping
        let thinkingOutput = "<think>Analyzing grammar and spelling...</think><result>Corrected sentence.</result>"
        XCTAssertEqual(AIRequestSupport.extractResultText(thinkingOutput), "Corrected sentence.")

        // Unclosed <think> during streaming should return empty to suppress raw thinking tokens
        let partialThink = "<think>Analyzing user prompt..."
        XCTAssertEqual(AIRequestSupport.extractResultText(partialThink), "")

        // Unclosed <result> tag during streaming should return in-progress content
        let partialResult = "<result>In progress streaming text"
        XCTAssertEqual(AIRequestSupport.extractResultText(partialResult), "In progress streaming text")

        // Empty closed tags should fall back to original text rather than returning closing tag
        XCTAssertEqual(AIRequestSupport.extractResultText("<result></result>"), "<result></result>")
        XCTAssertEqual(AIRequestSupport.extractResultText("<output>   </output>"), "<output>   </output>")

        // Plain text without tags
        XCTAssertEqual(AIRequestSupport.extractResultText("Simple raw response"), "Simple raw response")
    }

    func testCloudAPIEffectiveBaseURL() {
        let defaultOpenAI = CloudAPIProvider(apiKey: "key", model: "gpt-4o", serviceProvider: .openai)
        XCTAssertEqual(defaultOpenAI.effectiveBaseURL, "https://api.openai.com/v1")

        let anthropic = CloudAPIProvider(apiKey: "key", model: "claude-3-5-sonnet", serviceProvider: .anthropic, customBaseURL: "https://my-proxy.internal/v1")
        XCTAssertEqual(anthropic.effectiveBaseURL, CloudServiceProvider.anthropic.defaultBaseURL)

        let custom = CloudAPIProvider(apiKey: "key", model: "model", serviceProvider: .custom, customBaseURL: "https://my-proxy.internal/v1")
        XCTAssertEqual(custom.effectiveBaseURL, "https://my-proxy.internal/v1")
    }

    func testSystemPromptAndUserContentFormatting() {
        let customPrompt = "Translate into pirate English"
        let systemPrompt = AIRequestSupport.systemPrompt(for: customPrompt)
        XCTAssertTrue(systemPrompt.contains("Task:\nTranslate into pirate English"))
        XCTAssertTrue(systemPrompt.contains("Output ONLY the transformed text"))
        XCTAssertTrue(systemPrompt.contains("<result>...</result>"))

        let emptyTaskPrompt = AIRequestSupport.systemPrompt(for: "  ")
        XCTAssertFalse(emptyTaskPrompt.contains("Task:"))

        let userContent = AIRequestSupport.userContent(for: "Hello World")
        XCTAssertEqual(userContent, "<text>\nHello World\n</text>")
    }
}
