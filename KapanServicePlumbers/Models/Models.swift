import Foundation
import SwiftUI

struct MobileUser: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let name: String
    let role: String

    var isAdmin: Bool { role == "admin" }
    var isPlumber: Bool { role == "plumber" }
    var displayName: String { name.isEmpty ? email : name }
    var roleLabel: String {
        switch role {
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

    /// Message / tel stay open for 1h after completed.
    ///
    /// Defense in depth (owner may be on a stale API or leave Job open):
    /// 1. Canceled → always closed
    /// 2. `contactActionsUntil` past local now → closed
    /// 3. Completed + local 1h from `completedAt`/`updatedAt` expired → closed
    ///    (closes even if a stale payload still has `allowsCustomerMessaging: true`)
    /// 4. Else prefer server `allowsCustomerMessaging` / `allowsCustomerCall`
    /// 5. Else local window fallback
    var canMessageCustomer: Bool {
        contactActionAllowed(serverFlag: allowsCustomerMessaging)
    }

    var canCallCustomer: Bool {
        contactActionAllowed(serverFlag: allowsCustomerCall)
    }

    private func contactActionAllowed(serverFlag: Bool?) -> Bool {
        let normalized = status.lowercased()
        if normalized == "canceled" || normalized == "cancelled" { return false }
        if contactDeadlinePassed { return false }
        if normalized == "completed", !contactWindowOpenFallback { return false }
        if let flag = serverFlag { return flag }
        return contactWindowOpenFallback
    }

    private var contactDeadlinePassed: Bool {
        guard let until = ISO8601Helper.date(from: contactActionsUntil ?? "") else {
            return false
        }
        return Date() >= until
    }

    /// Local 1h window from completedAt (preferred) or updatedAt.
    /// For non-completed / non-canceled jobs this is `true` (Message available).
    private var contactWindowOpenFallback: Bool {
        let normalized = status.lowercased()
        // Canceled jobs close Message/tel immediately (matches server policy).
        if normalized == "canceled" || normalized == "cancelled" { return false }
        guard normalized == "completed" else { return true }
        let anchor =
            ISO8601Helper.date(from: completedAt ?? "")
            ?? ISO8601Helper.date(from: updatedAt)
        guard let anchor else { return false }
        return Date().timeIntervalSince(anchor) < 60 * 60
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
            ?? ISO8601Helper.date(from: updatedAt)
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
    let ok: Bool
    let token: String
    let user: MobileUser
}

struct BookingsResponse: Codable {
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
    let skipped: Bool
    let reason: String?
    let sent: Bool?
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
