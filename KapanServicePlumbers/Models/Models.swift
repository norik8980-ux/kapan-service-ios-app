import Foundation

struct MobileUser: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let name: String
    let role: String

    var isAdmin: Bool { role == "admin" }
    var isPlumber: Bool { role == "plumber" }
    var displayName: String { name.isEmpty ? email : name }
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

struct APIErrorBody: Codable {
    let error: String?
}
