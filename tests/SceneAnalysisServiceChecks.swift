import UIKit
import Foundation

// Compile with SceneAnalysisService.swift and Config.swift; no real credential is used.
enum RuntimeMaterial { static func resolve() -> String { "" } }

final class MockProtocol: URLProtocol {
    static var count = 0
    static var status = 200
    static var payload: [String: Any] = [:]
    static var request: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.count += 1
        Self.request = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: Self.payload))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIViewController()
        window?.makeKeyAndVisible()
        DispatchQueue.global().async { self.runChecks() }
        return true
    }

    func runChecks() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: config)
        let service = SceneAnalysisService(session: session, resolveKey: { "test-key" })
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400))
        let image = renderer.image { _ in UIColor.red.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 300, height: 400)) }
        func call(_ target: SceneAnalysisService = service) -> Result<String, SceneAnalysisError> {
            let semaphore = DispatchSemaphore(value: 0)
            var result: Result<String, SceneAnalysisError>?
            target.generateContent(prompt: "unchanged prompt", image: image) { result = $0; semaphore.signal() }
            precondition(semaphore.wait(timeout: .now() + 10) == .success, "Completion timed out")
            return result!
        }
        AIPrivacy.revokeConsent()
        guard case .failure(.consentRequired) = call() else { fatalError("Request allowed without consent") }
        precondition(MockProtocol.count == 0)
        UserDefaults.standard.set("outdated-consent", forKey: AIPrivacy.consentKey)
        guard case .failure(.consentRequired) = call() else { fatalError("Outdated consent accepted") }
        AIPrivacy.grantConsent()
        let noKey = SceneAnalysisService(session: session, resolveKey: { "" })
        guard case .failure(.unavailableConfiguration) = call(noKey) else { fatalError("Missing key accepted") }
        precondition(MockProtocol.count == 0)
        MockProtocol.payload = ["choices": [["message": ["content": "  Door ahead. Move right. \n"]]]]
        guard case .success(let text) = call(), text == "Door ahead. Move right." else { fatalError("Response parsing failed") }
        let request = MockProtocol.request!
        precondition(request.url!.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var bytes = [UInt8](repeating: 0, count: 8192)
            while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(contentsOf: bytes.prefix(n)) }
            body = data
        }
        let json = try! JSONSerialization.jsonObject(with: body!) as! [String: Any]
        precondition(json["model"] as? String == "bytedance-seed/seed-2.0-lite")
        precondition(json["max_tokens"] as? Int == 100)
        precondition((json["reasoning"] as? [String: Bool])?["enabled"] == false)
        let provider = json["provider"] as! [String: Any]
        precondition(provider["only"] as? [String] == ["seed/fp8"])
        precondition(provider["allow_fallbacks"] as? Bool == false)
        precondition(provider["data_collection"] as? String == "deny")
        let messages = json["messages"] as! [[String: Any]]
        let content = messages[0]["content"] as! [[String: Any]]
        precondition(content[0]["text"] as? String == "unchanged prompt")
        let dataURL = (content[1]["image_url"] as! [String: String])["url"]!
        let jpeg = Data(base64Encoded: String(dataURL.dropFirst("data:image/jpeg;base64,".count)))!
        let output = UIImage(data: jpeg)!.cgImage!
        precondition(output.width == 2304 && output.height == 3072, "App image scale changed")
        MockProtocol.status = 429
        MockProtocol.payload = ["error": ["message": "private request details"]]
        guard case .failure(.apiError(let error)) = call(), !error.contains("private") else { fatalError("Unsafe provider error") }
        MockProtocol.status = 200
        MockProtocol.payload = ["choices": [["message": ["content": "  "]]]]
        guard case .failure(.invalidResponse) = call() else { fatalError("Empty response accepted") }
        MockProtocol.payload = ["error": ["message": "failure"]]
        guard case .failure(.apiError) = call() else { fatalError("HTTP 200 API error accepted") }
        let count = MockProtocol.count
        AIPrivacy.revokeConsent()
        guard case .failure(.consentRequired) = call() else { fatalError("Revocation ignored") }
        precondition(MockProtocol.count == count)
        print("PASS: consent, outdated consent, revocation, missing key, request schema, image encoding, success parsing, rate-limit sanitization, empty response, API errors")
        fflush(stdout)
        exit(0)
    }
}
