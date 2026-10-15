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
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let booking {
                content(booking)
            } else if loadFailed, let error {
                ErrorStateView(message: error) {
                    Task { await reload() }
                }
            } else {
                LoadingStateView(message: "Loading job…")
            }
        }
        .navigationTitle("Job")
        .navigationBarTitleDisplayMode(.inline)
        .tint(KapanTheme.orange)
        .task { await reload() }
        .onChange(of: location.sessionExpired) { _, expired in
            if expired {
                Task { await session.signOut() }
            }
        }
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
                        Label("Sharing location", systemImage: "location.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KapanTheme.blue)
                        if let miles = location.lastDistanceMiles {
                            Text(String(format: "%.1f miles from job", miles))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if location.lastApproachSent || booking.approachSMSSent {
                            Text("Approach SMS sent")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(red: 0.18, green: 0.64, blue: 0.36))
                        }
                        if location.permissionDenied {
                            Text("Location permission denied — enable it in Settings.")
                                .font(.caption)
                                .foregroundStyle(KapanTheme.destructive)
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

            Section("Notes") {
                Text(booking.notes.isEmpty ? "No notes." : booking.notes)
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
                if let p = booking.assignedPlumber {
                    LabeledContent("Plumber", value: p.displayName)
                } else {
                    LabeledContent("Plumber", value: "Unassigned")
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
                    .disabled(busy || booking.status == "canceled" || booking.status == "completed")
                    if booking.assignedPlumber != nil {
                        Button("Unassign", role: .destructive) {
                            Task { await assign(nil) }
                        }
                        .disabled(busy || booking.status == "canceled" || booking.status == "completed")
                    }
                }
            }

            Section("Field status") {
                if canChangeStatus {
                    statusButton(
                        title: "On my way",
                        status: "en_route",
                        systemImage: "car.fill",
                        enabled: booking.status != "en_route"
                            && booking.status != "completed"
                            && booking.status != "canceled"
                            && booking.status != "arrived"
                    )
                    statusButton(
                        title: "Arrived",
                        status: "arrived",
                        systemImage: "mappin.and.ellipse",
                        enabled: booking.status == "en_route"
                            || booking.status == "assigned"
                            || booking.status == "confirmed"
                    )
                    statusButton(
                        title: "Complete",
                        status: "completed",
                        systemImage: "checkmark.circle.fill",
                        enabled: booking.status != "completed" && booking.status != "canceled"
                    )
                } else {
                    Text(statusLockedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                NavigationLink {
                    ChatView(bookingId: booking.id, customerName: booking.customerName)
                } label: {
                    Label("Message customer", systemImage: "bubble.left.and.bubble.right")
                }
            }

            if let err = location.lastError, location.activeBookingId == booking.id {
                Section {
                    Text(err).foregroundStyle(KapanTheme.destructive).font(.caption)
                }
            }
            if let error {
                Section {
                    InlineErrorRow(message: error) {
                        Task { await reload() }
                    }
                }
            }
        }
        .disabled(busy)
        .overlay {
            if busy {
                ProgressView()
                    .tint(KapanTheme.orange)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
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

    private var statusLockedMessage: String {
        if session.user?.isPlumber == true {
            return "Not assigned to you — status locked."
        }
        return "Only the assigned plumber or admin can update status."
    }

    private func statusButton(
        title: String,
        status: String,
        systemImage: String,
        enabled: Bool
    ) -> some View {
        Button {
            Task { await setStatus(status) }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .disabled(!enabled || busy)
    }

    private func reload() async {
        error = nil
        loadFailed = false
        do {
            let loaded = try await APIClient.shared.booking(id: bookingId)
            booking = loaded
            if session.user?.isAdmin == true {
                do {
                    plumbers = try await APIClient.shared.plumbers()
                } catch {
                    self.error = "Couldn’t load plumbers list: \(error.localizedDescription)"
                    await session.handleUnauthorized(error)
                }
            }
            location.sync(with: loaded, isPlumber: session.user?.isPlumber == true)
        } catch {
            self.error = error.localizedDescription
            if booking == nil {
                loadFailed = true
            }
            await session.handleUnauthorized(error)
        }
    }

    private func setStatus(_ status: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let updated = try await APIClient.shared.updateStatus(id: bookingId, status: status)
            booking = updated
            error = nil
            if session.user?.isPlumber == true {
                switch status {
                case "en_route":
                    location.start(bookingId: updated.id)
                case "arrived", "completed", "canceled":
                    if location.activeBookingId == updated.id {
                        location.stop()
                    }
                default:
                    break
                }
            } else if location.activeBookingId == updated.id {
                location.stop()
            }
        } catch {
            self.error = error.localizedDescription
            await session.handleUnauthorized(error)
        }
    }

    private func assign(_ plumberId: String?) async {
        guard !busy else { return }
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
    @State private var localError: String?

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

                if let localError {
                    Section {
                        Text(localError).foregroundStyle(KapanTheme.destructive).font(.subheadline)
                    }
                }

                Section("Choose plumber") {
                    if plumbers.isEmpty {
                        ContentUnavailableView {
                            Label("No active plumbers", systemImage: "person.slash")
                        } description: {
                            Text("Add one in the Plumbers tab.")
                        }
                        .listRowBackground(Color.clear)
                    }
                    ForEach(plumbers) { p in
                        Button {
                            Task {
                                guard !busy else { return }
                                busy = true
                                localError = nil
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
                                        .foregroundStyle(Color(red: 0.18, green: 0.64, blue: 0.36))
                                }
                            }
                        }
                        .disabled(busy)
                    }
                }
            }
            .navigationTitle("Assign")
            .navigationBarTitleDisplayMode(.inline)
            .tint(KapanTheme.orange)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(busy)
                }
            }
            .overlay {
                if busy { ProgressView().tint(KapanTheme.orange) }
            }
            .interactiveDismissDisabled(busy)
        }
    }
}
