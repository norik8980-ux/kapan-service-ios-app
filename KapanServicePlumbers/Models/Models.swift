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
        case "admin": return "Admin / Dispatch"
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
        status == "assigned" || status == "en_route"
    }
    var approachSMSSent: Bool { smsApproachAt != nil }
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
    var telURL: URL? {
        let digits = customerPhone.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
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
        case "pending", "confirmed": return .orange
        case "assigned": return .blue
        case "en_route": return .indigo
        case "arrived": return .teal
        case "completed": return .green
        case "canceled": return .secondary
        default: return .secondary
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
