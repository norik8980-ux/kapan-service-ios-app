import SwiftUI

struct BookingsListView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var tab = "upcoming"
    @State private var bookings: [MobileBooking] = []
    @State private var loading = false
    @State private var error: String?

    private let tabs = [
        ("today", "Today"),
        ("upcoming", "Upcoming"),
        ("completed", "Done"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Tab", selection: $tab) {
                        ForEach(tabs, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .onChange(of: tab) { _, _ in
                        Task { await load() }
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                if !loading && bookings.isEmpty && error == nil {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: "calendar.badge.checkmark")
                    } description: {
                        Text(emptySubtitle)
                    }
                    .listRowBackground(Color.clear)
                }

                ForEach(bookings) { booking in
                    NavigationLink(value: booking.id) {
                        BookingRow(booking: booking, showAssignee: session.user?.isAdmin == true)
                    }
                }
            }
            .navigationTitle(session.user?.isAdmin == true ? "All jobs" : "My jobs")
            .navigationDestination(for: String.self) { id in
                BookingDetailView(bookingId: id)
            }
            .toolbar {
                if let role = session.user?.roleLabel {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text(role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .refreshable { await load() }
            .overlay {
                if loading && bookings.isEmpty {
                    ProgressView()
                }
            }
            .task { await load() }
        }
    }

    private var emptyTitle: String {
        switch tab {
        case "today": return "No jobs today"
        case "completed": return "No completed jobs"
        default: return "No upcoming jobs"
        }
    }

    private var emptySubtitle: String {
        if session.user?.isPlumber == true {
            return "Assigned jobs will show up here."
        }
        return "New bookings from the website appear here."
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            bookings = try await APIClient.shared.bookings(tab: tab)
        } catch {
            self.error = error.localizedDescription
            await session.handleUnauthorized(error)
        }
    }
}

struct BookingRow: View {
    let booking: MobileBooking
    var showAssignee = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(booking.customerName)
                    .font(.headline)
                Spacer()
                StatusChip(status: booking.status)
            }
            Text(booking.service.name)
                .font(.subheadline)
            Text(booking.address)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                Label(booking.scheduledLabel, systemImage: "clock")
                if showAssignee {
                    Spacer(minLength: 8)
                    if let p = booking.assignedPlumber {
                        Label(p.displayName, systemImage: "person.fill")
                    } else {
                        Label("Unassigned", systemImage: "person.badge.plus")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct StatusChip: View {
    let status: String

    var body: some View {
        Text(FieldStatus.label(for: status))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(FieldStatus.color(for: status).opacity(0.15))
            .foregroundStyle(FieldStatus.color(for: status))
            .clipShape(Capsule())
    }
}
