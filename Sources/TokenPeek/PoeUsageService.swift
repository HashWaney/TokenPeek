import Foundation

struct PoeUsageService {
    private let endpoint = URL(string: "https://api.poe.com/usage/current_balance")!

    func fetch(apiKey: String) async throws -> PoeUsage {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UsageError.invalidResponse }
            switch http.statusCode {
            case 200:
                let payload = try JSONDecoder().decode(Payload.self, from: data)
                return PoeUsage(balance: payload.currentPointBalance)
            case 401, 403: throw UsageError.poeAuthentication
            case 429: throw UsageError.rateLimited
            default: throw UsageError.network("Poe 服务返回 HTTP \(http.statusCode)")
            }
        } catch let error as UsageError {
            throw error
        } catch {
            throw UsageError.network("Poe 网络请求失败：\(error.localizedDescription)")
        }
    }

    private struct Payload: Decodable {
        let currentPointBalance: Int
        enum CodingKeys: String, CodingKey { case currentPointBalance = "current_point_balance" }
    }
}
