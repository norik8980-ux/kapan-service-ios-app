import Foundation
import SwiftUI

struct MobileUser: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let name: String
    let role: String

    /// Normalized role for comparisons (API may vary casing).
    private var normalizedRole: String { role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    var isAdmin: Bool { normalizedRole == "admin" }
    var isPlumber: Bool { normalizedRole == "plumber" }
    /// Open jobs tab: always shown for plumber + admin (no visibility toggle).
    var canBrowseOpenJobs: Bool { isPlumber || isAdmin }
    var displayName: String { name.isEmpty ? email : name }
    var roleLabel: String {
        switch normalizedRole {
        case "admin": return "Admin"
        case "plumber": return "Plumber"
        default: return role.capitalized
        }
    }
}

struct ServiceInfo: Codable, Equatable {
    let id: String
    let name: String
    let slug: String
    let durationMin: Int
    let category: String
}

struct PlumberRef: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let name: String

    var displayName: String { name.isEmpty ? email : name }
}

struct MobileBooking: Codable, Identifiable, Equatable {
    let id: String
    let status: String
    let paymentStatus: String
    let customerName: String
    let customerEmail: String
    let customerPhone: String
    let address: String
    /// True when phone/email/street were redacted (plumber, after completed 1h window).
    let piiMasked: Bool?
    /// Server: Message allowed (false after 1h on completed).
    let allowsCustomerMessaging: Bool?
    /// Server: tel: call allowed (false after 1h on completed).
    let allowsCustomerCall: Bool?
    /// ISO time when Message/tel close on completed jobs.
    let contactActionsUntil: String?
    let completedAt: String?
    /// Stamped once when complete SMS runs — preferred over `updatedAt`.
    let smsCompleteAt: String?
    let notes: String
    let locale: String
    let scheduledAt: String
    let amountCents: Int
    let assignedPlumberId: String?
    let assignedPlumber: PlumberRef?
    let service: ServiceInfo
    let jobLat: Double?
    let jobLng: Double?
    let lastPlumberLat: Double?
    let lastPlumberLng: Double?
    let lastPlumberLocationAt: String?
    let smsApproachAt: String?
    let createdAt: String
    let updatedAt: String
    /// Open jobs board: coords are fuzzed (~3 mi); Maps is approximate.
    let approximateLocation: Bool?

    var isApproximateLocation: Bool { approximateLocation == true }

    var statusLabel: String { FieldStatus.label(for: status) }
    var isActiveFieldJob: Bool {
        // Web admin assign may leave status as confirmed until On my way.
        status == "confirmed" || status == "assigned" || status == "en_route"
    }
    var approachSMSSent: Bool { smsApproachAt != nil }
    var isPiiMasked: Bool {
        if let flag = piiMasked { return flag }
        let normalized = status.lowercased()
        // Offline-safe: canceled jobs hide contact until a fresh payload arrives.
        if normalized == "canceled" || normalized == "cancelled" { return true }
        return false
    }
    var amountLabel: String {
        let dollars = Double(amountCents) / 100.0
        return dollars.formatted(.currency(code: "USD"))
    }
    var scheduledDate: Date? { ISO8601Helper.date(from: scheduledAt) }
    var scheduledLabel: String {
        guard let date = scheduledDate else { return scheduledAt }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    var scheduledTimeLabel: String {
        guard let date = scheduledDate else { return scheduledAt }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Date + time for list cards (section headers alone are not enough).
    var scheduledCardDateTimeLabel: String {
        guard let date = scheduledDate else { return scheduledAt }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Start slider: only on the job’s local calendar day (plumber device).
    var isScheduledOnLocalCalendarDay: Bool {
        guard let date = scheduledDate else { return false }
        return Calendar.current.isDate(date, inSameDayAs: Date())
    }

    /// Message / tel stay open for 1h after completed.
    ///
    /// Fail-closed (tip after 540725d): never keep Message open from a bumped
    /// `updatedAt` alone. Completed jobs require a real completion stamp
    /// (`completedAt` or `smsCompleteAt`); otherwise hide.
    ///
    /// Order:
    /// 1. Canceled → closed
    /// 2. Server `allowsCustomerMessaging` / `allowsCustomerCall` == false → closed
    /// 3. `piiMasked` == true → closed
    /// 4. `contactActionsUntil` past → closed
    /// 5. Completed: open only if within 1h of completion stamp (see anchors)
    /// 6. Non-completed: prefer server true / default open
    var canMessageCustomer: Bool {
        contactActionAllowed(serverFlag: allowsCustomerMessaging)
    }

    var canCallCustomer: Bool {
        contactActionAllowed(serverFlag: allowsCustomerCall)
    }

    private func contactActionAllowed(serverFlag: Bool?) -> Bool {
        let normalized = status.lowercased()
        if normalized == "canceled" || normalized == "cancelled" { return false }
        // Explicit server close always wins (even if local clocks / stamps lag).
        if serverFlag == false { return false }
        if piiMasked == true { return false }
        if contactDeadlinePassed { return false }

        if normalized == "completed" {
            return completedContactWindowOpen
        }

        return serverFlag ?? true
    }

    private var contactDeadlinePassed: Bool {
        guard let until = ISO8601Helper.date(from: contactActionsUntil ?? "") else {
            return false
        }
        return Date() >= until
    }

    /// Completion anchors for the 1h Message/tel window.
    /// Prefer `completedAt`, then `smsCompleteAt`. Never open from `updatedAt`
    /// or a lone future `contactActionsUntil` (both reopen forever when the
    /// row is touched after complete without a real completion stamp).
    private var completedContactWindowOpen: Bool {
        let now = Date()
        let oneHour: TimeInterval = 60 * 60

        if let completed = ISO8601Helper.date(from: completedAt ?? "") {
            return now.timeIntervalSince(completed) < oneHour
        }
        if let sms = ISO8601Helper.date(from: smsCompleteAt ?? "") {
            return now.timeIntervalSince(sms) < oneHour
        }
        // No reliable completion stamp → hide (fail closed).
        return false
    }

    /// Seconds until Message/tel should close; nil if already closed or N/A.
    var contactActionsRemaining: TimeInterval? {
        let normalized = status.lowercased()
        if normalized == "canceled" || normalized == "cancelled" { return nil }
        if !canMessageCustomer && !canCallCustomer { return nil }
        if let until = ISO8601Helper.date(from: contactActionsUntil ?? "") {
            let left = until.timeIntervalSinceNow
            return left > 0 ? left : nil
        }
        guard normalized == "completed" else { return nil }
        let anchor =
            ISO8601Helper.date(from: completedAt ?? "")
            ?? ISO8601Helper.date(from: smsCompleteAt ?? "")
        guard let anchor else { return nil }
        let left = 60 * 60 - Date().timeIntervalSince(anchor)
        return left > 0 ? left : nil
    }

    var telURL: URL? {
        guard canCallCustomer, !isPiiMasked else { return nil }
        // Prefer E.164-ish digits so Phone app opens reliably (keeps leading country code).
        let trimmed = customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digits = trimmed.filter(\.isNumber)
        // Masked values like •••-•••-0199 only leave 4 digits — not dialable.
        guard digits.count >= 7 else { return nil }
        if trimmed.hasPrefix("+") {
            return URL(string: "tel:+\(digits)")
        }
        return URL(string: "tel:\(digits)")
    }

    var mailtoURL: URL? {
        guard !isPiiMasked else { return nil }
        let email = customerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, email.contains("@"), !email.contains("•••") else { return nil }
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return URL(string: "mailto:\(encoded)")
    }
    var mapsURL: URL? {
        if let lat = jobLat, let lng = jobLng {
            return URL(string: "http://maps.apple.com/?daddr=\(lat),\(lng)")
        }
        let q = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard !q.isEmpty else { return nil }
        return URL(string: "http://maps.apple.com/?daddr=\(q)")
    }
}

enum FieldStatus {
    static let all = [
        "pending", "confirmed", "assigned", "en_route", "arrived", "completed", "canceled",
    ]

    static func label(for status: String) -> String {
        switch status {
        case "pending": return "Pending"
        case "confirmed": return "Confirmed"
        case "assigned": return "Assigned"
        case "en_route": return "En route"
        case "arrived": return "Arrived"
        case "completed": return "Completed"
        case "canceled": return "Canceled"
        default: return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func color(for status: String) -> Color {
        switch status {
        case "pending", "confirmed": return KapanTheme.orange
        case "assigned": return KapanTheme.blue
        case "en_route": return KapanTheme.orangeDeep
        case "arrived": return KapanTheme.blue
        case "completed": return Color(red: 0.18, green: 0.64, blue: 0.36)
        case "canceled": return KapanTheme.muted
        default: return KapanTheme.muted
        }
    }
}

struct ChatMessage: Codable, Identifiable, Equatable {
    let id: String
    let bookingId: String
    let senderUserId: String
    let senderRole: String
    let direction: String
    let body: String
    let smsStatus: String
    let smsError: String
    let createdAt: String

    var isOutbound: Bool { direction == "outbound" }
    var createdLabel: String {
        guard let date = ISO8601Helper.date(from: createdAt) else { return createdAt }
        return date.formatted(date: .omitted, time: .shortened)
    }
    var senderLabel: String {
        switch senderRole {
        case "admin": return "Office"
        case "plumber": return "Plumber"
        case "customer": return "Customer"
        default: return senderRole.capitalized
        }
    }
}

struct PlumberAccount: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let name: String
    let role: String
    let active: Bool
    let createdAt: String
    let updatedAt: String

    var displayName: String { name.isEmpty ? email : name }
}

struct LoginResponse: Codable {
    /// Present on healthy API responses (`ok: true`). Optional so a missing
    /// field does not block sign-in if `token` + `user` are present.
    let ok: Bool?
    let token: String
    let user: MobileUser
}

struct MobileFeatures: Codable, Equatable {
    let openJobsClaim: Bool?

    /// Fail-open only when the server explicitly sends `true`.
    var isOpenJobsClaimEnabled: Bool { openJobsClaim == true }

    static let disabled = MobileFeatures(openJobsClaim: false)

    enum CodingKeys: String, CodingKey {
        case openJobsClaim
    }

    init(openJobsClaim: Bool?) {
        self.openJobsClaim = openJobsClaim
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Accept bool or common string/number truthy shapes so a settings
        // serialization quirk does not drop the whole `/me` payload.
        if let bool = try? container.decodeIfPresent(Bool.self, forKey: .openJobsClaim) {
            openJobsClaim = bool
        } else if let raw = try? container.decodeIfPresent(String.self, forKey: .openJobsClaim) {
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            openJobsClaim = (v == "1" || v == "true" || v == "yes" || v == "on")
        } else if let num = try? container.decodeIfPresent(Int.self, forKey: .openJobsClaim) {
            openJobsClaim = num != 0
        } else {
            openJobsClaim = nil
        }
    }
}

struct MeResponse: Codable {
    let user: MobileUser
    let features: MobileFeatures?

    enum CodingKeys: String, CodingKey {
        case user
        case features
    }

    init(user: MobileUser, features: MobileFeatures?) {
        self.user = user
        self.features = features
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decode(MobileUser.self, forKey: .user)
        // If `features` is malformed, keep user and treat flags as off —
        // do not fail the entire `/me` decode (would leave session stuck).
        if container.contains(.features) {
            features = try? container.decodeIfPresent(MobileFeatures.self, forKey: .features)
        } else {
            features = nil
        }
    }
}

struct BookingsResponse: Codable {
    let bookings: [MobileBooking]
}

struct OpenBookingsResponse: Codable {
    let enabled: Bool?
    let bookings: [MobileBooking]
}

struct BookingResponse: Codable {
    let booking: MobileBooking
}

struct MessagesResponse: Codable {
    let messages: [ChatMessage]
    let allowsCustomerMessaging: Bool?
}

struct MessageResponse: Codable {
    let message: ChatMessage
}

struct PlumbersResponse: Codable {
    let plumbers: [PlumberAccount]
}

struct CreatePlumberResponse: Codable {
    let plumber: PlumberAccount
    let temporaryPassword: String?
}

struct DeviceRegisterResponse: Codable {
    struct Device: Codable {
        let id: String
        let deviceToken: String
        let platform: String
        let updatedAt: String
    }
    let device: Device
    let warning: String?
}

struct ApproachPing: Codable, Equatable {
    let skipped: Bool?
    let reason: String?
    let sent: Bool?
    /// Server auto-set status to arrived after approach SMS (no Arrived slider).
    let autoArrived: Bool?
}

struct LocationPostResponse: Codable {
    let booking: MobileBooking
    let approach: ApproachPing?
    let distanceMiles: Double?
    let approachRadiusMiles: Double?
}

struct APIErrorBody: Codable {
    let error: String?
}

enum ISO8601Helper {
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from string: String) -> Date? {
        withFractional.date(from: string) ?? plain.date(from: string)
    }
}
