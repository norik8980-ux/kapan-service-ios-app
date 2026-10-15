import SwiftUI

struct BookingsListView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var tab = "upcoming"
    @State private var bookings: [MobileBooking] = []
    @State private var loading = false
    @State private var error: String?
    @State private var hasLoadedOnce = false

    private let tabs = [
        ("today", "Today"),
        ("upcoming", "Upcoming"),
        ("completed", "Done"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                KapanTheme.canvasGradient

                VStack(spacing: 0) {
                    tabPicker
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    content
                }
            }
            .navigationTitle(session.user?.isAdmin == true ? "All jobs" : "My jobs")
            .navigationBarTitleDisplayMode(.large)
            .tint(KapanTheme.orange)
            .navigationDestination(for: String.self) { id in
                BookingDetailView(bookingId: id)
            }
            .task { await load() }
        }
    }

    private var tabPicker: some View {
        Picker("Tab", selection: $tab) {
            ForEach(tabs, id: \.0) { Text($0.1).tag($0.0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: tab) { _, _ in
            Task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading && bookings.isEmpty && !hasLoadedOnce {
            // ScrollView so pull-to-refresh works even on first load.
            ScrollView {
                LoadingStateView(message: "Loading jobs…")
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
            // Empty state must be scrollable — .refreshable only works on scroll views.
            ScrollView {
                emptyState
                    .frame(maxWidth: .infinity, minHeight: 420)
            }
            .refreshable { await load() }
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
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
                    }

                    ForEach(bookings) { booking in
                        NavigationLink(value: booking.id) {
                            BookingRow(booking: booking, showAssignee: session.user?.isAdmin == true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .padding(.top, 2)
            }
            .refreshable { await load() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 48)
            Image(systemName: "calendar")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(KapanTheme.blue)
            Text(emptyTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(KapanTheme.ink)
            Text(emptySubtitle)
                .font(.subheadline)
                .foregroundStyle(KapanTheme.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private var emptyTitle: String {
        switch tab {
        case "today": return "No jobs today"
        case "completed": return "No completed jobs"
        default: return "No open jobs"
        }
    }

    private var emptySubtitle: String {
        switch tab {
        case "today":
            return "Jobs scheduled for other days are under Upcoming (including overdue). Pull down to refresh."
        case "completed":
            return "Finished jobs show here. Open jobs are under Today or Upcoming. Pull down to refresh."
        default:
            return "Open assigned jobs (including past dates) show here. Check Today for today’s schedule. Pull down to refresh."
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let next = try await APIClient.shared.bookings(tab: tab)
            bookings = next
            error = nil
            hasLoadedOnce = true
        } catch {
            // Aborted refresh (URLError.cancelled) must not surface as a red error card.
            if APIError.isCancellation(error) || Task.isCancelled { return }
            self.error = error.localizedDescription
            hasLoadedOnce = true
            await session.handleUnauthorized(error)
        }
    }
}

struct BookingRow: View {
    let booking: MobileBooking
    var showAssignee = false

    private let cardRadius: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.customerName)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(KapanTheme.ink)
                        .lineLimit(2)

                    Text(booking.service.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(KapanTheme.ink.opacity(0.72))
                        .lineLimit(2)
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

                HStack(spacing: 14) {
                    Label(booking.scheduledLabel, systemImage: "clock")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(KapanTheme.ink.opacity(0.78))

                    if showAssignee {
                        if let plumber = booking.assignedPlumber {
                            Label(plumber.displayName, systemImage: "person.fill")
                                .font(.subheadline)
                                .foregroundStyle(KapanTheme.ink.opacity(0.72))
                                .lineLimit(1)
                        } else {
                            Label("Unassigned", systemImage: "person.badge.plus")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(KapanTheme.orange)
                                .lineLimit(1)
                        }
                    }
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
        .accessibilityHint("Opens job details")
    }
}

struct StatusChip: View {
    let status: String

    private var tint: Color { FieldStatus.color(for: status) }

    var body: some View {
        Text(FieldStatus.label(for: status))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(tint)
            .clipShape(Capsule())
            .shadow(color: tint.opacity(0.28), radius: 4, y: 2)
            .accessibilityLabel("Status \(FieldStatus.label(for: status))")
    }
}
