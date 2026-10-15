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
            .refreshable { await load() }
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
            LoadingStateView(message: "Loading jobs…")
        } else if let error, bookings.isEmpty {
            ErrorStateView(message: error) {
                Task { await load() }
            }
        } else if !loading && bookings.isEmpty && error == nil && hasLoadedOnce {
            emptyState
        } else {
            List {
                if let error {
                    Section {
                        InlineErrorRow(message: error) {
                            Task { await load() }
                        }
                        .listRowBackground(Color.white)
                    }
                }

                ForEach(bookings) { booking in
                    NavigationLink(value: booking.id) {
                        BookingRow(booking: booking, showAssignee: session.user?.isAdmin == true)
                    }
                    .listRowBackground(Color.white)
                    .listRowSeparatorTint(KapanTheme.border)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
        default: return "No upcoming jobs"
        }
    }

    private var emptySubtitle: String {
        "Pull down to refresh."
    }

    private func load() async {
        loading = true
        error = nil
        defer {
            loading = false
            hasLoadedOnce = true
        }
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
                    .foregroundStyle(KapanTheme.ink)
                Spacer(minLength: 8)
                StatusChip(status: booking.status)
            }
            Text(booking.service.name)
                .font(.subheadline)
                .foregroundStyle(KapanTheme.ink.opacity(0.85))
            Text(booking.address)
                .font(.caption)
                .foregroundStyle(KapanTheme.muted)
                .lineLimit(2)
            HStack {
                Label(booking.scheduledLabel, systemImage: "clock")
                if showAssignee {
                    Spacer(minLength: 8)
                    if let p = booking.assignedPlumber {
                        Label(p.displayName, systemImage: "person.fill")
                    } else {
                        Label("Unassigned", systemImage: "person.badge.plus")
                            .foregroundStyle(KapanTheme.orange)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(KapanTheme.muted)
        }
        .padding(.vertical, 4)
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
