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
        case .server(let msg):
            // Opaque prod 500s used to say only "Request failed" (schema drift).
            if msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Server error. Try again."
            }
            return msg
        case .decoding:
            return "Could not read server response. Check the API URL or try again."
        case .network(let err): return err.localizedDescription
        }
    }

    /// Pull-to-refresh / navigation often aborts in-flight URLSession work.
    /// Those cancellations are not user-facing failures.
    var isCancellation: Bool {
        if case .network(let err) = self {
            return Self.isURLCancellation(err)
        }
        return false
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let api = error as? APIError { return api.isCancellation }
        return isURLCancellation(error)
    }

    private static func isURLCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
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

    func messages(bookingId: String) async throws -> (messages: [ChatMessage], allowsCustomerMessaging: Bool) {
        let r: MessagesResponse = try await get("/api/mobile/bookings/\(bookingId)/messages")
        // Fail closed when the flag is missing (completed+1h must not stay open).
        return (r.messages, r.allowsCustomerMessaging ?? false)
    }

    func sendMessage(bookingId: String, body: String) async throws -> ChatMessage {
        // Server returns 201 on SMS ok, or 502 with the same message row when Twilio fails
        // (chat row is already saved — treat as soft failure, not a throw).
        let r: MessageResponse = try await request(
            "/api/mobile/bookings/\(bookingId)/messages",
            method: "POST",
            body: ["body": body],
            authed: true,
            acceptStatuses: [201, 502]
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

    @discardableResult
    func registerDevice(token: String, platform: String = "ios") async throws -> DeviceRegisterResponse {
        try await post(
            "/api/mobile/devices",
            body: ["deviceToken": token, "platform": platform]
        )
    }

    func unregisterDevice(token: String) async throws {
        struct Ok: Codable { let ok: Bool? }
        let _: Ok = try await request(
            "/api/mobile/devices",
            method: "DELETE",
            body: ["deviceToken": token],
            authed: true
        )
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
        authed: Bool,
        acceptStatuses: Set<Int>? = nil
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
            let ok: Bool
            if let acceptStatuses {
                ok = acceptStatuses.contains(http.statusCode)
            } else {
                ok = (200...299).contains(http.statusCode)
            }
            if !ok {
                if let err = try? decoder.decode(APIErrorBody.self, from: data),
                   let message = err.error, !message.isEmpty {
                    throw APIError.server(message)
                }
                throw APIError.server(Self.nonJSONOrStatusMessage(status: http.statusCode, data: data, response: http))
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                // HTML / empty / shape drift → clearer than a bare decode failure.
                if Self.looksLikeHTML(data) || !Self.looksLikeJSON(data) {
                    throw APIError.server(Self.nonJSONOrStatusMessage(status: http.statusCode, data: data, response: http))
                }
                throw APIError.decoding
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    private static func looksLikeHTML(_ data: Data) -> Bool {
        guard let s = String(data: data.prefix(200), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return s.hasPrefix("<!doctype") || s.hasPrefix("<html")
    }

    private static func looksLikeJSON(_ data: Data) -> Bool {
        guard let s = String(data: data.prefix(64), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return s.hasPrefix("{") || s.hasPrefix("[")
    }

    private static func nonJSONOrStatusMessage(status: Int, data: Data, response: HTTPURLResponse) -> String {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if looksLikeHTML(data) || contentType.contains("text/html") {
            return "Server returned a web page (HTTP \(status)). Check the API URL."
        }
        if data.isEmpty {
            return "Empty server response (HTTP \(status))."
        }
        if !looksLikeJSON(data) {
            return "Unexpected server response (HTTP \(status))."
        }
        return "HTTP \(status)"
    }
}
