import SwiftUI

struct BookingsListView: View {
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
                Picker("Tab", selection: $tab) {
                    ForEach(tabs, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .onChange(of: tab) { _, _ in
                    Task { await load() }
                }

                if let error {
                    Text(error).foregroundStyle(.red)
                }

                ForEach(bookings) { booking in
                    NavigationLink(value: booking.id) {
                        BookingRow(booking: booking)
                    }
                }
            }
            .navigationTitle("Jobs")
            .navigationDestination(for: String.self) { id in
                BookingDetailView(bookingId: id)
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

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            bookings = try await APIClient.shared.bookings(tab: tab)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct BookingRow: View {
    let booking: MobileBooking

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(booking.customerName).font(.headline)
                Spacer()
                Text(booking.status.replacingOccurrences(of: "_", with: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(booking.service.name)
                .font(.subheadline)
            Text(booking.address)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(booking.scheduledAt)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
