import SwiftUI

struct BookingDetailView: View {
    let bookingId: String
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var location: LocationPublisher

    @State private var booking: MobileBooking?
    @State private var plumbers: [PlumberAccount] = []
    @State private var error: String?
    @State private var busy = false
    @State private var showAssignSheet = false

    var body: some View {
        Group {
            if let booking {
                content(booking)
            } else if let error {
                ContentUnavailableView(
                    "Couldn’t load job",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Job")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .sheet(isPresented: $showAssignSheet) {
            if let booking {
                AssignPlumberSheet(
                    booking: booking,
                    plumbers: plumbers.filter(\.active)
                ) { plumberId in
                    await assign(plumberId)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ booking: MobileBooking) -> some View {
        List {
            if location.isSharing && location.activeBookingId == booking.id {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Sharing location for this job", systemImage: "location.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.indigo)
                        if let miles = location.lastDistanceMiles {
                            Text(String(format: "%.1f miles from job · approach SMS at 3 miles", miles))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("GPS posts while status is En route. Customer gets one SMS within 3 miles.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if location.lastApproachSent || booking.approachSMSSent {
                            Text("Approach SMS sent")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        if location.permissionDenied {
                            Text("Location permission denied. Enable it in Settings to notify the customer.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Section("Customer") {
                LabeledContent("Name", value: booking.customerName)
                if let tel = booking.telURL {
                    Link(destination: tel) {
                        Label(booking.customerPhone, systemImage: "phone.fill")
                    }
                } else if !booking.customerPhone.isEmpty {
                    LabeledContent("Phone", value: booking.customerPhone)
                }
                if !booking.customerEmail.isEmpty {
                    LabeledContent("Email", value: booking.customerEmail)
                }
                Text(booking.address)
                if let maps = booking.mapsURL {
                    Link(destination: maps) {
                        Label("Open in Apple Maps", systemImage: "map")
                    }
                }
            }

            Section("Customer notes") {
                Text(booking.notes.isEmpty ? "No notes left at booking." : booking.notes)
                    .foregroundStyle(booking.notes.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
            }

            Section("Job") {
                LabeledContent("Service", value: booking.service.name)
                LabeledContent("When", value: booking.scheduledLabel)
                HStack {
                    Text("Status")
                    Spacer()
                    StatusChip(status: booking.status)
                }
                LabeledContent("Payment", value: "\(booking.paymentStatus) · \(booking.amountLabel)")
                LabeledContent("SMS language", value: booking.locale.uppercased())
                if let p = booking.assignedPlumber {
                    LabeledContent("Plumber", value: p.displayName)
                } else {
                    LabeledContent("Plumber", value: "Unassigned")
                }
                if booking.approachSMSSent {
                    LabeledContent("Approach SMS", value: "Sent")
                }
            }

            if session.user?.isAdmin == true {
                Section("Assign") {
                    Button {
                        showAssignSheet = true
                    } label: {
                        Label(
                            booking.assignedPlumber == nil ? "Assign plumber" : "Transfer / reassign",
                            systemImage: "person.badge.plus"
                        )
                    }
                    if booking.assignedPlumber != nil {
                        Button("Unassign", role: .destructive) {
                            Task { await assign(nil) }
                        }
                    }
                }
            }

            Section("Field status") {
                if canChangeStatus {
                    statusButton(
                        title: "On my way",
                        status: "en_route",
                        systemImage: "car.fill",
                        enabled: booking.status != "en_route" && booking.status != "completed" && booking.status != "canceled"
                    ) {
                        location.start(bookingId: booking.id)
                    }
                    statusButton(
                        title: "Arrived",
                        status: "arrived",
                        systemImage: "mappin.and.ellipse",
                        enabled: booking.status == "en_route" || booking.status == "assigned"
                    ) {
                        location.stop()
                    }
                    statusButton(
                        title: "Complete",
                        status: "completed",
                        systemImage: "checkmark.circle.fill",
                        enabled: booking.status != "completed" && booking.status != "canceled"
                    ) {
                        location.stop()
                    }
                } else {
                    Text("Only the assigned plumber or admin can update field status.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                NavigationLink {
                    ChatView(bookingId: booking.id, customerName: booking.customerName)
                } label: {
                    Label("Chat → customer SMS", systemImage: "bubble.left.and.bubble.right")
                }
            } footer: {
                Text("Messages send as SMS to the customer phone. Inbound replies are not in this MVP.")
            }

            if let err = location.lastError, location.activeBookingId == booking.id {
                Section {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .disabled(busy)
        .refreshable { await reload() }
    }

    private var canChangeStatus: Bool {
        guard let user = session.user else { return false }
        if user.isAdmin { return true }
        if user.isPlumber {
            return booking?.assignedPlumberId == user.id
        }
        return false
    }

    private func statusButton(
        title: String,
        status: String,
        systemImage: String,
        enabled: Bool,
        extra: @escaping () -> Void = {}
    ) -> some View {
        Button {
            Task {
                await setStatus(status)
                extra()
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .disabled(!enabled || busy)
    }

    private func reload() async {
        error = nil
        do {
            let loaded = try await APIClient.shared.booking(id: bookingId)
            booking = loaded
            if session.user?.isAdmin == true {
                plumbers = try await APIClient.shared.plumbers()
            }
            location.sync(with: loaded, isPlumber: session.user?.isPlumber == true)
        } catch {
            self.error = error.localizedDescription
            await session.handleUnauthorized(error)
        }
    }

    private func setStatus(_ status: String) async {
        busy = true
        defer { busy = false }
        do {
            booking = try await APIClient.shared.updateStatus(id: bookingId, status: status)
            error = nil
        } catch {
            self.error = error.localizedDescription
            await session.handleUnauthorized(error)
        }
    }

    private func assign(_ plumberId: String?) async {
        busy = true
        defer { busy = false }
        do {
            booking = try await APIClient.shared.assign(bookingId: bookingId, plumberId: plumberId)
            showAssignSheet = false
            error = nil
        } catch {
            self.error = error.localizedDescription
            await session.handleUnauthorized(error)
        }
    }
}

struct AssignPlumberSheet: View {
    let booking: MobileBooking
    let plumbers: [PlumberAccount]
    let onAssign: (String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(booking.customerName).font(.headline)
                    Text(booking.address).font(.caption).foregroundStyle(.secondary)
                    if let current = booking.assignedPlumber {
                        Text("Currently: \(current.displayName)")
                            .font(.caption)
                    }
                }

                Section("Choose plumber") {
                    if plumbers.isEmpty {
                        Text("No active plumbers. Add one in the Plumbers tab.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(plumbers) { p in
                        Button {
                            Task {
                                busy = true
                                await onAssign(p.id)
                                busy = false
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(p.displayName)
                                    Text(p.email).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if booking.assignedPlumberId == p.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .disabled(busy)
                    }
                }
            }
            .navigationTitle("Assign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay {
                if busy { ProgressView() }
            }
        }
    }
}
