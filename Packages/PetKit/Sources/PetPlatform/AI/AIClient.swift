import AppKit
import Foundation
import PetCore
import Security

/// API keys (one per provider), stored only in the login Keychain.
public enum AIKeychain {
    private static let service = "dev.jefflabs.AmbientPets"

    private static func query(_ provider: AIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "\(provider.rawValue)-api-key"]
    }

    public static func hasKey(_ provider: AIProvider) -> Bool { read(provider) != nil }

    static func read(_ provider: AIProvider) -> String? {
        var q = query(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        let key = String(decoding: data, as: UTF8.self)
        return key.isEmpty ? nil : key
    }

    @discardableResult
    public static func save(_ key: String, for provider: AIProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        SecItemDelete(query(provider) as CFDictionary)
        var q = query(provider)
        q[kSecValueData as String] = Data(trimmed.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    public static func delete(_ provider: AIProvider) { SecItemDelete(query(provider) as CFDictionary) }
}

/// Opt-in scene chooser backed by OpenAI Chat Completions or the Claude Messages API (raw HTTP).
/// Any failure (no key, network, non-200, refusal, timeout, invalid answer) returns nil and the rule chooser runs.
public enum AIClient {
    public static let timeout: Double = 2

    public struct Outcome: Sendable {
        public var choice: AIChoice?
        public var latency: Double
        public var error: String?
    }

    public static func choose(provider: AIProvider, model: String, request r: AIRequest) async -> Outcome {
        let start = Date()
        guard let key = AIKeychain.read(provider) else { return Outcome(choice: nil, latency: 0, error: "no \(provider.displayName) API key") }
        let json: JSONValue = provider == .openai ? AIChooser.openAIRequestBody(model: model, r) : AIChooser.requestBody(model: model, r)
        let candidates = r.candidates
        let blockNames = Set(r.blocks.keys), moodPets = r.moodPets
        guard let body = try? JSONEncoder().encode(json) else { return Outcome(choice: nil, latency: 0, error: "encoding failed") }
        let endpoint = provider == .openai ? "https://api.openai.com/v1/chat/completions" : "https://api.anthropic.com/v1/messages"
        var request = URLRequest(url: URL(string: endpoint)!, timeoutInterval: timeout)
        request.httpMethod = "POST"
        switch provider {
        case .openai:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body
        let keys = Set(candidates.map(\.key))
        let finalRequest = request

        // Hard wall-clock limit: whichever finishes first, the request or the timer.
        let result: Outcome = await withTaskGroup(of: Outcome?.self) { group in
            group.addTask {
                do {
                    let (data, response) = try await URLSession.shared.data(for: finalRequest)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        // Surface the API's own message (e.g. unknown model) for the Settings "Test" button.
                        let message = (try? JSONDecoder().decode(JSONValue.self, from: data)).flatMap { root -> String? in
                            guard case .object(let o) = root, case .object(let e)? = o["error"] else { return nil }
                            return e["message"]?.string
                        }
                        return Outcome(choice: nil, latency: 0, error: "HTTP \(status)\(message.map { ": \($0.prefix(120))" } ?? "")")
                    }
                    let choice = provider == .openai
                        ? AIChooser.parseOpenAIResponse(data, candidates: keys, blocks: blockNames, moodPets: moodPets)
                        : AIChooser.parseResponse(data, candidates: keys, blocks: blockNames, moodPets: moodPets)
                    return Outcome(choice: choice, latency: 0, error: choice == nil ? "no valid choice (refusal or invalid answer)" : nil)
                } catch {
                    return Outcome(choice: nil, latency: 0, error: (error as? URLError)?.code == .timedOut ? "timed out" : "network error")
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout + 0.1))
                return Outcome(choice: nil, latency: 0, error: "timed out")
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? Outcome(choice: nil, latency: 0, error: "cancelled")
        }
        var out = result
        out.latency = Date().timeIntervalSince(start)
        return out
    }

    /// The frontmost app's App Store category ("developer-tools"), never its name.
    @MainActor
    public static func frontmostCategory() -> String? {
        guard let url = NSWorkspace.shared.frontmostApplication?.bundleURL,
              let cat = Bundle(url: url)?.infoDictionary?["LSApplicationCategoryType"] as? String else { return nil }
        return cat.replacingOccurrences(of: "public.app-category.", with: "")
    }

    /// The frontmost window title, only when the user allowed it and Screen Recording is granted.
    @MainActor
    public static func frontmostWindowTitle() -> String? {
        guard ContextMonitor.hasScreenRecording, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        for w in ContextMonitor.onScreenWindows() where ContextMonitor.ownerPID(w) == pid && ContextMonitor.layer(w) == 0 {
            if let t = w[kCGWindowName as String] as? String, !t.isEmpty { return String(t.prefix(80)) }
        }
        return nil
    }
}
