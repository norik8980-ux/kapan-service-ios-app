import SwiftUI
import UIKit

struct ChatView: View {
    let bookingId: String
    var customerName: String = "Customer"
    /// Optional hint from job detail (used when GET omits reason).
    var initialClosedReason: String? = nil

    @EnvironmentObject private var session: SessionStore
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var error: String?
    @State private var sending = false
    @State private var loading = false
    @State private var hasLoadedOnce = false
    /// Closed until GET /messages returns flags (avoids composer flash + POST racing 403).
    @State private var allowsCustomerMessaging = false
    @State private var closedReason: String? = nil

    private var closedDescription: String {
        switch closedReason ?? initialClosedReason {
        case "before_job_day":
            return "Messaging opens on the day of the job."
        case "canceled":
            return "This job was canceled. Messaging is closed."
        case "post_complete_window", "missing_complete_anchor":
            return "The 1-hour window after job completion has ended."
        default:
            return "Messaging is not available for this job."
        }
    }

    private var closedFooter: String {
        switch closedReason ?? initialClosedReason {
        case "before_job_day":
            return "Messaging opens on the day of the job."
        case "canceled":
            return "Messaging is closed for this canceled job."
        case "post_complete_window", "missing_complete_anchor":
            return "Messaging is no longer available for this completed job."
        default:
            return "Messaging is not available for this job."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if loading && messages.isEmpty {
                LoadingStateView(message: "Loading messages…")
            } else if let error, messages.isEmpty, hasLoadedOnce {
                ErrorStateView(message: error) {
                    Task { await load() }
                }
            } else if messages.isEmpty && hasLoadedOnce {
                ContentUnavailableView {
                    Label(
                        allowsCustomerMessaging ? "No messages yet" : "Messaging closed",
                        systemImage: "bubble.left"
                    )
                } description: {
                    Text(
                        allowsCustomerMessaging
                            ? "Send a text to \(customerName)."
                            : closedDescription
                    )
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(messages) { msg in
                        messageRow(msg)
                            .id(msg.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                    .listStyle(.plain)
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            if let error, !messages.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(KapanTheme.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            if allowsCustomerMessaging {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Message \(customerName)…", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .padding(10)
                        .background(KapanTheme.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(sending)
                    Button {
                        Task { await send() }
                    } label: {
                        if sending {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 36, height: 36)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                        }
                    }
                    .background(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending
                            ? KapanTheme.orange.opacity(0.45)
                            : KapanTheme.orange
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(.bar)
            } else if hasLoadedOnce {
                Text(closedFooter)
                    .font(.footnote)
                    .foregroundStyle(KapanTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.bar)
            }
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .tint(KapanTheme.orange)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func messageRow(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.isOutbound { Spacer(minLength: 40) }
            VStack(alignment: msg.isOutbound ? .trailing : .leading, spacing: 4) {
                Text(msg.senderLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(msg.body)
                    .padding(10)
                    .background(
                        msg.isOutbound
                            ? KapanTheme.orange.opacity(0.15)
                            : Color(.secondarySystemBackground)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 6) {
                    Text(msg.createdLabel)
                    if !msg.smsStatus.isEmpty {
                        Text("·")
                        Text(msg.smsStatus)
                    }
                    if !msg.smsError.isEmpty {
                        Text("· \(msg.smsError)")
                            .foregroundStyle(KapanTheme.destructive)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            if !msg.isOutbound { Spacer(minLength: 40) }
        }
    }

    private func load() async {
        loading = true
        defer {
            loading = false
            hasLoadedOnce = true
        }
        do {
            let result = try await APIClient.shared.messages(bookingId: bookingId)
            messages = result.messages
            allowsCustomerMessaging = result.allowsCustomerMessaging
            closedReason = result.contactActionsClosedReason ?? initialClosedReason
            error = nil
        } catch {
            if APIError.isCancellation(error) || Task.isCancelled { return }
            self.error = error.localizedDescription
            await session.handleUnauthorized(error)
        }
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowsCustomerMessaging, !body.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }
        do {
            let msg = try await APIClient.shared.sendMessage(bookingId: bookingId, body: body)
            messages.append(msg)
            draft = ""
            error = nil
            // Soft SMS failure still returns the saved chat row.
            if msg.smsStatus == "error" {
                self.error = msg.smsError.isEmpty
                    ? "Message saved, but SMS delivery failed."
                    : "Message saved, but SMS failed: \(msg.smsError)"
            }
        } catch {
            if APIError.isCancellation(error) || Task.isCancelled { return }
            self.error = error.localizedDescription
            // Server closes the window with 403 — hide composer.
            if case APIError.forbidden = error {
                allowsCustomerMessaging = false
                if closedReason == nil {
                    closedReason = initialClosedReason ?? "post_complete_window"
                }
            }
            await session.handleUnauthorized(error)
        }
    }
}
