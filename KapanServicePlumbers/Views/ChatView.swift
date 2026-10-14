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

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty && error == nil {
                ContentUnavailableView {
                    Label("No messages yet", systemImage: "bubble.left")
                } description: {
                    Text("Send a text to \(customerName). It goes out as SMS.")
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

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("SMS to \(customerName)…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
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
                    .background(msg.isOutbound ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 6) {
                    Text(msg.createdLabel)
                    if !msg.smsStatus.isEmpty {
                        Text("·")
                        Text(msg.smsStatus)
                    }
                    if !msg.smsError.isEmpty {
                        Text("· \(msg.smsError)")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            if !msg.isOutbound { Spacer(minLength: 40) }
        }
    }

    private func load() async {
        do {
            messages = try await APIClient.shared.messages(bookingId: bookingId)
            error = nil
        } catch {
            self.error = error.localizedDescription
            await session.handleUnauthorized(error)
        }
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            let msg = try await APIClient.shared.sendMessage(bookingId: bookingId, body: body)
            messages.append(msg)
            draft = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
            await session.handleUnauthorized(error)
        }
    }
}
