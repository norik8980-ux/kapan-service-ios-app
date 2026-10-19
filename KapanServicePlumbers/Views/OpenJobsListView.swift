import SwiftUI

/// Open jobs board — privacy-safe list; Accept only via Slide to Accept on detail.
struct OpenJobsListView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var bookings: [MobileBooking] = []
    @State private var loading = false
    @State private var error: String?
    @State private var hasLoadedOnce = false
    @State private var path = NavigationPath()

    private var sections: [BookingDaySection] {
        BookingDateSections.group(bookings, reverseDays: false)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                KapanTheme.canvasGradient
                // Large title sits outside refreshable content so pull-to-refresh
                // only rubber-bands the list (nav large-title mode moves with ScrollView).
                VStack(alignment: .leading, spacing: 0) {
                    screenTitle
                    content
                }
            }
            .navigationTitle("Open jobs")
            .navigationBarTitleDisplayMode(.inline)
            // Root: hide chrome so the in-content hero title matches Account large-title weight.
            .toolbar(path.isEmpty ? .hidden : .automatic, for: .navigationBar)
            .tint(KapanTheme.orange)
            .navigationDestination(for: OpenJobsRoute.self) { route in
                switch route {
                case .openDetail(let id):
                    OpenJobDetailView(bookingId: id) { claimed in
                        bookings.removeAll { $0.id == claimed.id }
                        // Replace stack with full assigned job detail (PII unlocked).
                        path = NavigationPath()
                        path.append(OpenJobsRoute.assignedDetail(claimed.id))
                    }
                case .assignedDetail(let id):
                    BookingDetailView(bookingId: id)
                }
            }
            .task { await load() }
        }
    }

    private var screenTitle: some View {
        Text("Open jobs")
            // Match pre-inline nav large title (~34pt bold); same size as My jobs.
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(KapanTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var content: some View {
        if loading && bookings.isEmpty && !hasLoadedOnce {
            ScrollView {
                LoadingStateView(message: "Loading open jobs…")
                    .frame(maxWidth: .infinity, minHeight: 360)
            }
            .refreshable { await load() }
        } else if let error, bookings.isEmpty {
            ScrollView {
                ErrorStateView(message: error) {
                    Task { await load() }
                }
                .frame(maxWidth: .infinity, minHeight: 360)
            }
            .refreshable { await load() }
        } else if !loading && bookings.isEmpty && error == nil && hasLoadedOnce {
            ScrollView {
                emptyState
                    .frame(maxWidth: .infinity, minHeight: 420)
            }
            .refreshable { await load() }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                    if let error {
                        InlineErrorRow(message: error) {
                            Task { await load() }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(KapanTheme.border, lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                    }

                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(KapanTheme.muted)
                                .textCase(.none)
                                .padding(.horizontal, 20)
                                .padding(.top, 4)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(section.bookings) { booking in
                                NavigationLink(value: OpenJobsRoute.openDetail(booking.id)) {
                                    OpenJobRow(booking: booking)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .padding(.bottom, 28)
                .padding(.top, 8)
            }
            .refreshable { await load() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 48)
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(KapanTheme.blue)
            Text("No open jobs")
                .font(.title3.weight(.semibold))
                .foregroundStyle(KapanTheme.ink)
            Text("Unassigned jobs you can accept will show here. Pull to refresh.")
                .font(.subheadline)
                .foregroundStyle(KapanTheme.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let next = try await APIClient.shared.openBookings()
            bookings = next
            error = nil
            hasLoadedOnce = true
            await session.refreshFeatures()
        } catch {
            if APIError.isCancellation(error) || Task.isCancelled { return }
            self.error = error.localizedDescription
            hasLoadedOnce = true
            await session.handleUnauthorized(error)
        }
    }
}

private enum OpenJobsRoute: Hashable {
    case openDetail(String)
    case assignedDetail(String)
}

struct OpenJobRow: View {
    let booking: MobileBooking
    private let cardRadius: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.service.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(KapanTheme.ink)
                        .lineLimit(2)
                    if !booking.customerName.isEmpty {
                        Text(booking.customerName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(KapanTheme.ink.opacity(0.72))
                    }
                }
                Spacer(minLength: 8)
                StatusChip(status: booking.status)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(booking.address)
                        .lineLimit(2)
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(KapanTheme.blue)
                }
                .font(.subheadline)
                .foregroundStyle(KapanTheme.ink.opacity(0.82))

                Label(booking.scheduledCardDateTimeLabel, systemImage: "clock")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(KapanTheme.ink.opacity(0.78))

                Label(booking.amountLabel, systemImage: "creditcard.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KapanTheme.ink.opacity(0.82))

                if !booking.notes.isEmpty {
                    Text(booking.notes)
                        .font(.subheadline)
                        .foregroundStyle(KapanTheme.muted)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .stroke(KapanTheme.border, lineWidth: 1)
        )
        .shadow(color: KapanTheme.ink.opacity(0.07), radius: 14, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens open job details")
    }
}

struct OpenJobDetailView: View {
    let bookingId: String
    var onClaimed: (MobileBooking) -> Void

    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    @State private var booking: MobileBooking?
    @State private var error: String?
    @State private var loadFailed = false
    @State private var busy = false
    @State private var claimAlert: String?

    private var canAccept: Bool { session.user?.isPlumber == true }

    var body: some View {
        Group {
            if let booking {
                detail(booking)
            } else if loadFailed, let error {
                ErrorStateView(message: error) {
                    Task { await reload() }
                }
            } else {
                LoadingStateView(message: "Loading job…")
            }
        }
        .navigationTitle("Open job")
        .navigationBarTitleDisplayMode(.inline)
        .tint(KapanTheme.orange)
        .task { await reload() }
        .alert("Couldn’t accept", isPresented: Binding(
            get: { claimAlert != nil },
            set: { if !$0 { claimAlert = nil } }
        )) {
            Button("OK", role: .cancel) { claimAlert = nil }
        } message: {
            Text(claimAlert ?? "")
        }
    }

    @ViewBuilder
    private func detail(_ booking: MobileBooking) -> some View {
        ZStack {
            KapanTheme.canvasGradient

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(booking.service.name)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(KapanTheme.ink)

                            // Match list-card SF Symbols: grey clock, muted card, person.
                            detailIconRow(systemImage: "clock", tint: KapanTheme.muted) {
                                Text(booking.scheduledLabel)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(KapanTheme.ink.opacity(0.78))
                            }
                            detailIconRow(systemImage: "creditcard.fill", tint: KapanTheme.muted) {
                                Text(booking.amountLabel)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(KapanTheme.ink.opacity(0.82))
                            }
                            if !booking.customerName.isEmpty {
                                detailIconRow(systemImage: "person.fill", tint: KapanTheme.blue) {
                                    Text(booking.customerName)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(KapanTheme.ink)
                                }
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(detailCardBackground)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Approximate area")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(KapanTheme.muted)
                                .textCase(.uppercase)

                            detailIconRow(systemImage: "mappin.and.ellipse", tint: KapanTheme.blue) {
                                Text(booking.address)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(KapanTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if booking.jobLat != nil, booking.jobLng != nil {
                                Button {
                                    openApproxMaps(booking)
                                } label: {
                                    Label("View approximate area", systemImage: "map")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(KapanTheme.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(detailCardBackground)

                        // Always show Notes before accept (open-board API returns notes;
                        // hide-when-empty looked broken when notes were present but missed).
                        notesCard(booking)

                        if session.user?.isAdmin == true, !canAccept {
                            Text("Browse only — sign in as a plumber to accept jobs.")
                                .font(.footnote)
                                .foregroundStyle(KapanTheme.muted)
                        }

                        if let error {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, canAccept ? 120 : 28)
                }

                if canAccept {
                    acceptSlideBar
                }
            }
        }
    }

    private func notesCard(_ booking: MobileBooking) -> some View {
        let trimmed = booking.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let empty = trimmed.isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KapanTheme.muted)
                .textCase(.uppercase)
            Text(empty ? "No notes." : booking.notes)
                .font(.body)
                .foregroundStyle(empty ? KapanTheme.muted : KapanTheme.ink)
                .textSelection(.enabled)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(detailCardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(empty ? "Notes: No notes" : "Notes: \(booking.notes)")
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

    private var acceptSlideBar: some View {
        VStack(spacing: 8) {
            Text("Exact address and customer contact unlock after you accept.")
                .font(.caption)
                .foregroundStyle(KapanTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            SlideToActControl(
                title: "Slide to Accept",
                tint: KapanTheme.orange,
                systemImage: "checkmark",
                disabled: busy
            ) {
                await claim()
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

    private func openApproxMaps(_ booking: MobileBooking) {
        guard let lat = booking.jobLat, let lng = booking.jobLng else { return }
        var comps = URLComponents(string: "https://maps.apple.com/")
        comps?.queryItems = [
            URLQueryItem(name: "ll", value: "\(lat),\(lng)"),
            URLQueryItem(name: "q", value: "Approximate area"),
        ]
        if let url = comps?.url {
            openURL(url)
        }
    }

    private func reload() async {
        do {
            let list = try await APIClient.shared.openBookings()
            if let match = list.first(where: { $0.id == bookingId }) {
                booking = match
                loadFailed = false
                error = nil
            } else {
                // Fall back to assigned detail if already claimed elsewhere.
                booking = try await APIClient.shared.booking(id: bookingId)
                loadFailed = false
                error = nil
            }
        } catch {
            if APIError.isCancellation(error) { return }
            self.error = error.localizedDescription
            loadFailed = booking == nil
            await session.handleUnauthorized(error)
        }
    }

    private func claim() async {
        busy = true
        defer { busy = false }
        do {
            let claimed = try await APIClient.shared.claimBooking(id: bookingId)
            onClaimed(claimed)
        } catch let api as APIError {
            if case .alreadyClaimed = api {
                claimAlert = "Already claimed by another plumber. Refreshing…"
                await loadAndDrop()
            } else {
                claimAlert = api.localizedDescription
                await session.handleUnauthorized(api)
            }
        } catch {
            claimAlert = error.localizedDescription
        }
    }

    private func loadAndDrop() async {
        do {
            let list = try await APIClient.shared.openBookings()
            if list.contains(where: { $0.id == bookingId }) {
                booking = list.first { $0.id == bookingId }
            } else {
                booking = nil
                loadFailed = true
                error = "This job was already claimed."
            }
        } catch {
            /* ignore */
        }
    }
}
