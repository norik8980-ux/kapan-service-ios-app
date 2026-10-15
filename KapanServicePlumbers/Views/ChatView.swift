import SwiftUI
import UIKit

struct ChatView: View {
    let bookingId: String
    var customerName: String = "Customer"

    @EnvironmentObject private var session: SessionStore
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var error: String?
    @State private var sending = false
    @State private var loading = false
    @State private var hasLoadedOnce = false
    @State private var allowsCustomerMessaging = true

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
                            : "The 1-hour window after job completion has ended."
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
                Text("Messaging is no longer available for this completed job.")
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
            error = nil
        } catch {
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
        } catch {
            self.error = error.localizedDescription
            // Server closes the window with 403 — hide composer.
            if case APIError.forbidden = error {
                allowsCustomerMessaging = false
            }
            await session.handleUnauthorized(error)
        }
    }
}
