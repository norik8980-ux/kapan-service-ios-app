import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case forbidden
    case server(String)
    case decoding
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired. Sign in again."
        case .forbidden: return "You don’t have permission for that."
        case .server(let msg): return msg
        case .decoding: return "Could not read server response."
        case .network(let err): return err.localizedDescription
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    /// Production default: https://kapanservice.com — override via AppConfig / Account.
    private(set) var baseURL: URL = AppConfig.baseURL

    private var token: String?
    private let decoder = JSONDecoder()

    func applyConfiguredBaseURL() {
        baseURL = AppConfig.baseURL
    }

    func setBaseURL(_ url: URL) {
        baseURL = url
    }

    func setToken(_ token: String?) {
        self.token = token
    }

    func login(login: String, password: String) async throws -> LoginResponse {
        try await post(
            "/api/mobile/auth/login",
            body: ["login": login, "password": password],
            authed: false
        )
    }

    func me() async throws -> MobileUser {
        struct R: Codable { let user: MobileUser }
        let r: R = try await get("/api/mobile/auth/me")
        return r.user
    }

    func bookings(tab: String) async throws -> [MobileBooking] {
        let encoded = tab.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tab
        let r: BookingsResponse = try await get("/api/mobile/bookings?tab=\(encoded)")
        return r.bookings
    }

    func booking(id: String) async throws -> MobileBooking {
        let r: BookingResponse = try await get("/api/mobile/bookings/\(id)")
        return r.booking
    }

    func updateStatus(id: String, status: String) async throws -> MobileBooking {
        let r: BookingResponse = try await patch(
            "/api/mobile/bookings/\(id)",
            body: ["status": status]
        )
        return r.booking
    }

    func assign(bookingId: String, plumberId: String?) async throws -> MobileBooking {
        let body: [String: Any]
        if let plumberId {
            body = ["plumberId": plumberId]
        } else {
            body = ["plumberId": NSNull()]
        }
        let r: BookingResponse = try await patch(
            "/api/mobile/bookings/\(bookingId)/assign",
            body: body
        )
        return r.booking
    }

    @discardableResult
    func postLocation(bookingId: String, lat: Double, lng: Double) async throws -> LocationPostResponse {
        try await post(
            "/api/mobile/bookings/\(bookingId)/location",
            body: ["lat": lat, "lng": lng]
        )
    }

    func messages(bookingId: String) async throws -> [ChatMessage] {
        let r: MessagesResponse = try await get("/api/mobile/bookings/\(bookingId)/messages")
        return r.messages
    }

    func sendMessage(bookingId: String, body: String) async throws -> ChatMessage {
        let r: MessageResponse = try await post(
            "/api/mobile/bookings/\(bookingId)/messages",
            body: ["body": body]
        )
        return r.message
    }

    func plumbers() async throws -> [PlumberAccount] {
        let r: PlumbersResponse = try await get("/api/mobile/plumbers")
        return r.plumbers
    }

    func createPlumber(
        email: String,
        name: String,
        generatePassword: Bool = true,
        password: String? = nil
    ) async throws -> CreatePlumberResponse {
        var body: [String: Any] = [
            "email": email,
            "name": name,
            "generatePassword": generatePassword,
        ]
        if let password, !password.isEmpty {
            body["password"] = password
            body["confirmPassword"] = password
            body["generatePassword"] = false
        }
        return try await post("/api/mobile/plumbers", body: body)
    }

    // MARK: - HTTP

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "GET", body: nil, authed: true)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any], authed: Bool = true) async throws -> T {
        try await request(path, method: "POST", body: body, authed: authed)
    }

    private func patch<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await request(path, method: "PATCH", body: body, authed: true)
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String,
        body: [String: Any]?,
        authed: Bool
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.server("Bad URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 30
        if authed {
            guard let token else { throw APIError.unauthorized }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.server("No response")
            }
            if http.statusCode == 401 {
                // Authed calls: session really expired. Login (authed: false) is bad credentials.
                if authed {
                    throw APIError.unauthorized
                }
                if let err = try? decoder.decode(APIErrorBody.self, from: data),
                   let message = err.error, !message.isEmpty {
                    throw APIError.server(message)
                }
                throw APIError.server("Invalid email or password")
            }
            if http.statusCode == 403 {
                throw APIError.forbidden
            }
            if !(200...299).contains(http.statusCode) {
                if let err = try? decoder.decode(APIErrorBody.self, from: data),
                   let message = err.error, !message.isEmpty {
                    throw APIError.server(message)
                }
                throw APIError.server("HTTP \(http.statusCode)")
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }
}
