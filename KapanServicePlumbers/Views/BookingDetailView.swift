import SwiftUI

struct BookingDetailView: View {
    let bookingId: String
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var location: LocationPublisher
    @Environment(\.openURL) private var openURL

    @State private var booking: MobileBooking?
    @State private var plumbers: [PlumberAccount] = []
    @State private var error: String?
    @State private var busy = false
    @State private var showAssignSheet = false
    @State private var loadFailed = false
    /// Bumps so Message/tel re-evaluate when the 1h deadline elapses while Job is open.
    @State private var contactWindowTick = 0

    var body: some View {
        Group {
            if let booking {
                content(booking)
                    // Read tick so SwiftUI re-renders when the local deadline fires.
                    .id("contact-\(contactWindowTick)-\(booking.canMessageCustomer)")
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
        .task(id: booking?.id) {
            await watchContactDeadline()
        }
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

    /// Sleep until `contactActionsUntil` (or local 1h) then force a UI refresh.
    private func watchContactDeadline() async {
        while !Task.isCancelled {
            guard let booking, let remaining = booking.contactActionsRemaining else {
                return
            }
            // Cap sleep so a long remaining window still re-checks after status changes.
            let sleepFor = min(max(remaining, 0.5), 60)
            try? await Task.sleep(nanoseconds: UInt64(sleepFor * 1_000_000_000))
            if Task.isCancelled { return }
            contactWindowTick &+= 1
            // Soft refresh once past the deadline so flags/PII match server.
            if booking.contactActionsRemaining == nil {
                await reload()
                return
            }
        }
    }

    @ViewBuilder
    private func content(_ booking: MobileBooking) -> some View {
        ZStack {
            KapanTheme.canvasGradient

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        headerCard(booking)
                        if location.isSharing && location.activeBookingId == booking.id {
                            locationCard(booking)
                        }
                        customerCard(booking)
                        notesCard(booking)
                        jobCard(booking)
                        if session.user?.isAdmin == true {
                            assignCard(booking)
                        }
                        // Fail-closed: never show Message on completed/canceled
                        // outside the 1h window (see MobileBooking.canMessageCustomer).
                        if booking.canMessageCustomer {
                            chatCard(booking)
                        }
                        if let err = location.lastError, location.activeBookingId == booking.id {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(KapanTheme.destructive)
                                .padding(.horizontal, 4)
                        }
                        if let error {
                            InlineErrorRow(message: error) {
                                Task { await reload() }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, canChangeStatus ? 120 : 28)
                }
                .refreshable { await reload() }

                if canChangeStatus {
                    fieldActionsBar(booking)
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
    }

    private func headerCard(_ booking: MobileBooking) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.customerName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(KapanTheme.ink)
                    Text(booking.service.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(KapanTheme.ink.opacity(0.72))
                }
                Spacer(minLength: 8)
                StatusChip(status: booking.status)
            }
            Label(booking.scheduledLabel, systemImage: "clock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(KapanTheme.ink.opacity(0.78))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(detailCardBackground)
    }

    private func locationCard(_ booking: MobileBooking) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sharing location", systemImage: "location.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KapanTheme.blue)
            if let miles = location.lastDistanceMiles {
                Text(String(format: "%.1f miles from job", miles))
                    .font(.caption)
                    .foregroundStyle(KapanTheme.muted)
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(detailCardBackground)
    }

    private func customerCard(_ booking: MobileBooking) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Customer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KapanTheme.muted)
                .textCase(.uppercase)

            detailIconRow(systemImage: "person.fill", tint: KapanTheme.blue) {
                Text(booking.customerName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(KapanTheme.ink)
            }

            if booking.canCallCustomer, let tel = booking.telURL {
                Button {
                    openURL(tel)
                } label: {
                    detailIconRow(systemImage: "phone.fill", tint: KapanTheme.orange) {
                        Text(booking.customerPhone)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(KapanTheme.orangeDeep)
                            .underline()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call \(booking.customerPhone)")
            } else if !booking.customerPhone.isEmpty {
                detailIconRow(systemImage: "phone.fill", tint: KapanTheme.muted) {
                    Text(booking.customerPhone)
                        .font(.body.weight(.medium))
                        .foregroundStyle(KapanTheme.ink)
                }
            }

            if !booking.isPiiMasked, let mail = booking.mailtoURL {
                Button {
                    openURL(mail)
                } label: {
                    detailIconRow(systemImage: "envelope.fill", tint: KapanTheme.blue) {
                        Text(booking.customerEmail)
                            .font(.body.weight(.medium))
                            .foregroundStyle(KapanTheme.ink)
                    }
                }
                .buttonStyle(.plain)
            } else if !booking.customerEmail.isEmpty {
                detailIconRow(systemImage: "envelope.fill", tint: KapanTheme.muted) {
                    Text(booking.customerEmail)
                        .font(.body.weight(.medium))
                        .foregroundStyle(KapanTheme.ink)
                }
            }

            detailIconRow(systemImage: "mappin.and.ellipse", tint: KapanTheme.blue) {
                Text(booking.address)
                    .font(.body.weight(.medium))
                    .foregroundStyle(KapanTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if booking.status == "canceled" || booking.status == "cancelled" {
                Text("This job was canceled. Call and Message are closed; street and phone are hidden.")
            } else if booking.status == "completed", !booking.canMessageCustomer || !booking.canCallCustomer || booking.isPiiMasked {
                Text("Call and Message close 1 hour after the job is finished. Street and phone are hidden after that.")
                    .font(.caption)
                    .foregroundStyle(KapanTheme.muted)
            }

            // Prefer lat/lng Maps after street is masked (address string may be •••).
            if let maps = booking.mapsURL, booking.jobLat != nil || !booking.isPiiMasked {
                Button {
                    openURL(maps)
                } label: {
                    Label("Open in Apple Maps", systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KapanTheme.blue)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(detailCardBackground)
    }

    private func notesCard(_ booking: MobileBooking) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KapanTheme.muted)
                .textCase(.uppercase)
            Text(booking.notes.isEmpty ? "No notes." : booking.notes)
                .font(.body)
                .foregroundStyle(booking.notes.isEmpty ? KapanTheme.muted : KapanTheme.ink)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(detailCardBackground)
    }

    private func jobCard(_ booking: MobileBooking) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Job")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KapanTheme.muted)
                .textCase(.uppercase)

            detailIconRow(systemImage: "wrench.and.screwdriver.fill", tint: KapanTheme.orange) {
                Text(booking.service.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(KapanTheme.ink)
            }
            detailIconRow(systemImage: "clock", tint: KapanTheme.blue) {
                Text(booking.scheduledLabel)
                    .font(.body.weight(.medium))
                    .foregroundStyle(KapanTheme.ink)
            }
            detailIconRow(systemImage: "creditcard.fill", tint: KapanTheme.muted) {
                Text("\(booking.paymentStatus) · \(booking.amountLabel)")
                    .font(.body.weight(.medium))
                    .foregroundStyle(KapanTheme.ink)
            }
            detailIconRow(systemImage: "person.fill", tint: KapanTheme.blue) {
                Text(booking.assignedPlumber?.displayName ?? "Unassigned")
                    .font(.body.weight(.medium))
                    .foregroundStyle(
                        booking.assignedPlumber == nil ? KapanTheme.orange : KapanTheme.ink
                    )
            }

            if !canChangeStatus {
                Text(statusLockedMessage)
                    .font(.caption)
                    .foregroundStyle(KapanTheme.muted)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(detailCardBackground)
    }

    private func assignCard(_ booking: MobileBooking) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assign")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KapanTheme.muted)
                .textCase(.uppercase)
            Button {
                showAssignSheet = true
            } label: {
                Label(
                    booking.assignedPlumber == nil ? "Assign plumber" : "Transfer / reassign",
                    systemImage: "person.badge.plus"
                )
                .font(.subheadline.weight(.semibold))
            }
            .disabled(busy || booking.status == "canceled" || booking.status == "completed")
            if booking.assignedPlumber != nil {
                Button("Unassign", role: .destructive) {
                    Task { _ = await assign(nil) }
                }
                .disabled(busy || booking.status == "canceled" || booking.status == "completed")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(detailCardBackground)
    }

    private func chatCard(_ booking: MobileBooking) -> some View {
        NavigationLink {
            ChatView(bookingId: booking.id, customerName: booking.customerName)
        } label: {
            Label("Message customer", systemImage: "bubble.left.and.bubble.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KapanTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(detailCardBackground)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func fieldActionsBar(_ booking: MobileBooking) -> some View {
        VStack(spacing: 10) {
            if showsStartSlide(booking) {
                SlideToActControl(
                    title: "Slide to start",
                    tint: KapanTheme.orange,
                    systemImage: "car.fill",
                    disabled: busy
                ) {
                    await setStatus("en_route")
                }
            }

            if showsArrivedSlide(booking) {
                SlideToActControl(
                    title: "Slide to arrived",
                    tint: KapanTheme.blue,
                    systemImage: "mappin.and.ellipse",
                    disabled: busy
                ) {
                    await setStatus("arrived")
                }
            }

            if showsFinishSlide(booking) {
                SlideToActControl(
                    title: "Slide to finished",
                    tint: Color(red: 0.18, green: 0.64, blue: 0.36),
                    systemImage: "checkmark",
                    disabled: busy
                ) {
                    await setStatus("completed")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(KapanTheme.border.opacity(0.7))
                .frame(height: 1)
        }
    }

    private func detailIconRow<Content: View>(
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)
            content()
            Spacer(minLength: 0)
        }
    }

    private var detailCardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(KapanTheme.border, lineWidth: 1)
            )
            .shadow(color: KapanTheme.ink.opacity(0.06), radius: 12, y: 4)
    }

    private var canChangeStatus: Bool {
        guard let user = session.user else { return false }
        guard let booking else { return false }
        // Completed / canceled: no field slides (matches server plumber graph).
        if booking.status == "completed" || booking.status == "canceled" {
            return user.isAdmin
        }
        if user.isAdmin { return true }
        if user.isPlumber {
            return booking.assignedPlumberId == user.id
        }
        return false
    }

    private var statusLockedMessage: String {
        if session.user?.isPlumber == true {
            return "Not assigned to you — status locked."
        }
        return "Only the assigned plumber or admin can update status."
    }

    private func showsStartSlide(_ booking: MobileBooking) -> Bool {
        switch booking.status {
        case "en_route", "arrived", "completed", "canceled":
            return false
        default:
            return true
        }
    }

    private func showsArrivedSlide(_ booking: MobileBooking) -> Bool {
        booking.status == "en_route"
    }

    private func showsFinishSlide(_ booking: MobileBooking) -> Bool {
        booking.status == "en_route" || booking.status == "arrived"
    }

    private func reload() async {
        loadFailed = false
        do {
            // Always replace from detail GET so list-row flags cannot leave
            // Message visible after the 1h window.
            let loaded = try await APIClient.shared.booking(id: bookingId)
            booking = loaded
            contactWindowTick &+= 1
            error = nil
            if session.user?.isAdmin == true {
                do {
                    plumbers = try await APIClient.shared.plumbers()
                } catch {
                    if APIError.isCancellation(error) || Task.isCancelled { return }
                    self.error = "Couldn’t load plumbers list: \(error.localizedDescription)"
                    await session.handleUnauthorized(error)
                }
            }
            location.sync(with: loaded, isPlumber: session.user?.isPlumber == true)
        } catch {
            if APIError.isCancellation(error) || Task.isCancelled { return }
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
            // Success: always replace local job so chips / slides match server
            // (e.g. arrived → completed after Slide to finished).
            booking = updated
            error = nil
            loadFailed = false
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
            if APIError.isCancellation(error) || Task.isCancelled { return }
            // Keep existing `booking` so detail stays usable after a failed finish.
            let action: String = {
                switch status {
                case "en_route": return "start"
                case "arrived": return "arrived"
                case "completed": return "finished"
                default: return "update"
                }
            }()
            self.error = "Couldn’t mark \(action): \(error.localizedDescription)"
            await session.handleUnauthorized(error)
        }
    }

    /// Returns an error message for the assign sheet; nil on success.
    @discardableResult
    private func assign(_ plumberId: String?) async -> String? {
        guard !busy else { return nil }
        busy = true
        defer { busy = false }
        do {
            booking = try await APIClient.shared.assign(bookingId: bookingId, plumberId: plumberId)
            showAssignSheet = false
            error = nil
            return nil
        } catch {
            if APIError.isCancellation(error) || Task.isCancelled { return nil }
            let message = error.localizedDescription
            self.error = message
            await session.handleUnauthorized(error)
            return message
        }
    }
}

struct AssignPlumberSheet: View {
    let booking: MobileBooking
    let plumbers: [PlumberAccount]
    /// Returns nil on success, or an error string to show in the sheet.
    let onAssign: (String?) async -> String?

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
                                localError = await onAssign(p.id)
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
