import SwiftUI

struct BookingDetailView: View {
    let bookingId: String
    @EnvironmentObject private var session: SessionStore
    @StateObject private var location = LocationPublisher()

    @State private var booking: MobileBooking?
    @State private var plumbers: [PlumberAccount] = []
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        Group {
            if let booking {
                content(booking)
            } else if error != nil {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error ?? ""))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Job")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .onDisappear { location.stop() }
    }

    @ViewBuilder
    private func content(_ booking: MobileBooking) -> some View {
        List {
            Section("Customer") {
                LabeledContent("Name", value: booking.customerName)
                if !booking.customerPhone.isEmpty {
                    Link(booking.customerPhone, destination: URL(string: "tel:\(booking.customerPhone.filter(\.isNumber))")!)
                }
                Text(booking.address)
                if let maps = mapsURL(for: booking) {
                    Link("Open in Apple Maps", destination: maps)
                }
            }

            Section("Notes") {
                Text(booking.notes.isEmpty ? "No notes" : booking.notes)
                    .foregroundStyle(booking.notes.isEmpty ? .secondary : .primary)
            }

            Section("Job") {
                LabeledContent("Service", value: booking.service.name)
                LabeledContent("Status", value: booking.status)
                LabeledContent("Locale", value: booking.locale.uppercased())
                LabeledContent("When", value: booking.scheduledAt)
                if let p = booking.assignedPlumber {
                    LabeledContent("Plumber", value: p.displayName)
                }
            }

            if session.user?.isAdmin == true {
                Section("Assign") {
                    ForEach(plumbers.filter(\.active)) { p in
                        Button(p.displayName) {
                            Task { await assign(p.id) }
                        }
                    }
                    Button("Unassign", role: .destructive) {
                        Task { await assign(nil) }
                    }
                }
            }

            Section("Status") {
                if session.user?.isPlumber == true || session.user?.isAdmin == true {
                    statusButton("On my way", "en_route") {
                        location.start(bookingId: booking.id)
                    }
                    statusButton("Arrived", "arrived") {
                        location.stop()
                    }
                    statusButton("Complete", "completed") {
                        location.stop()
                    }
                }
            }

            Section {
                NavigationLink("Chat (SMS)") {
                    ChatView(bookingId: booking.id)
                }
            }

            if let err = location.lastError {
                Section {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .disabled(busy)
        .refreshable { await reload() }
    }

    private func statusButton(_ title: String, _ status: String, extra: @escaping () -> Void = {}) -> some View {
        Button(title) {
            Task {
                await setStatus(status)
                extra()
            }
        }
    }

    private func mapsURL(for booking: MobileBooking) -> URL? {
        let q = booking.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "http://maps.apple.com/?daddr=\(q)")
    }

    private func reload() async {
        error = nil
        do {
            booking = try await APIClient.shared.booking(id: bookingId)
            if session.user?.isAdmin == true {
                plumbers = try await APIClient.shared.plumbers()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setStatus(_ status: String) async {
        busy = true
        defer { busy = false }
        do {
            booking = try await APIClient.shared.updateStatus(id: bookingId, status: status)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func assign(_ plumberId: String?) async {
        busy = true
        defer { busy = false }
        do {
            booking = try await APIClient.shared.assign(bookingId: bookingId, plumberId: plumberId)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
