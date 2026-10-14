import SwiftUI

struct ChatView: View {
    let bookingId: String
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var error: String?
    @State private var sending = false

    var body: some View {
        VStack(spacing: 0) {
            List(messages) { msg in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(msg.senderRole.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(msg.smsStatus)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(msg.body)
                }
            }
            .listStyle(.plain)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            HStack {
                TextField("Message to customer…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("Chat")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            messages = try await APIClient.shared.messages(bookingId: bookingId)
            error = nil
        } catch {
            self.error = error.localizedDescription
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
        }
    }
}
