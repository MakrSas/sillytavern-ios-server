import Foundation

struct ControlClient {
    let port: Int

    private var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    func health() async throws -> RuntimeHealth {
        let request = URLRequest(url: baseURL.appendingPathComponent("health"))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(RuntimeHealth.self, from: data)
    }

    func command(_ command: String, preferredPort: Int) async throws -> ControlResult {
        var request = URLRequest(url: baseURL.appendingPathComponent(command))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["port": preferredPort])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(ControlResult.self, from: data)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
