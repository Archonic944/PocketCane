import Foundation
import UIKit

enum SceneAnalysisError: Error {
    case consentRequired
    case unavailableConfiguration
    case imageConversionFailed
    case networkError(Error)
    case invalidResponse
    case apiError(String)
}

final class SceneAnalysisService {
    static let shared = SceneAnalysisService(resolveKey: { RuntimeMaterial.resolve() })
    private let session: URLSession
    private let resolveKey: () -> String

    init(session: URLSession? = nil, resolveKey: @escaping () -> String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        self.session = session ?? URLSession(configuration: configuration)
        self.resolveKey = resolveKey
    }

    func generateContent(prompt: String, image: UIImage, completion: @escaping (Result<String, SceneAnalysisError>) -> Void) {
        guard AIPrivacy.hasConsent else {
            completion(.failure(.consentRequired))
            return
        }
        let key = resolveKey()
        guard !key.isEmpty else {
            completion(.failure(.unavailableConfiguration))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Preserve the app's UIKit renderer scale, JPEG quality and base64 encoding.
            let resizedImage = self.resizeImage(image: image, targetSize: CGSize(width: 1024, height: 1024))
            guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
                completion(.failure(.imageConversionFailed))
                return
            }
            let parameters: [String: Any] = [
                "model": AIConfiguration.model,
                "messages": [["role": "user", "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + imageData.base64EncodedString()]]
                ]]],
                "temperature": 0.4,
                "max_tokens": 100,
                "stream": false,
                "reasoning": ["enabled": false],
                "provider": [
                    "only": [AIConfiguration.provider],
                    "allow_fallbacks": false,
                    "require_parameters": true,
                    "data_collection": "deny"
                ]
            ]
            guard let body = try? JSONSerialization.data(withJSONObject: parameters) else {
                completion(.failure(.imageConversionFailed))
                return
            }
            // Consent may have been revoked while the image was being encoded.
            guard AIPrivacy.hasConsent else {
                completion(.failure(.consentRequired))
                return
            }
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            request.httpBody = body
            self.session.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(.networkError(error)))
                    return
                }
                guard let response = response as? HTTPURLResponse,
                      let data = data,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    completion(.failure(.invalidResponse))
                    return
                }
                guard (200..<300).contains(response.statusCode), json["error"] == nil else {
                    // Do not display raw provider errors, which may contain request details.
                    let message = response.statusCode == 429
                        ? "AI descriptions are busy. Please try again shortly."
                        : "AI descriptions are unavailable. Please try again."
                    completion(.failure(.apiError(message)))
                    return
                }
                guard let choices = json["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String,
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    completion(.failure(.invalidResponse))
                    return
                }
                completion(.success(content.trimmingCharacters(in: .whitespacesAndNewlines)))
            }.resume()
        }
    }

    private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size

        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height

        var newSize: CGSize
        if widthRatio > heightRatio {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
        }

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
