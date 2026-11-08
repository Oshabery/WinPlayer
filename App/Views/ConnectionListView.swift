import SwiftData
import SwiftUI

/// 保存済みの接続先一覧。タップで接続する。
struct ConnectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Connection.createdAt) private var connections: [Connection]

    @State private var editing: Connection?
    @State private var isAdding = false
    @State private var active: Connection?

    var body: some View {
        NavigationStack {
            Group {
                if connections.isEmpty {
                    ContentUnavailableView {
                        Label("接続先がありません", systemImage: "desktopcomputer")
                    } description: {
                        Text("Windows の「設定 > システム > リモート デスクトップ」をオンにしてから、右上の ＋ で PC を追加してください。")
                    } actions: {
                        Button("PC を追加") { isAdding = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(connections) { connection in
                            Button {
                                active = connection
                            } label: {
                                ConnectionRow(connection: connection)
                            }
                            .contextMenu {
                                Button("編集", systemImage: "pencil") { editing = connection }
                                Button("削除", systemImage: "trash", role: .destructive) { delete(connection) }
                            }
                            .swipeActions {
                                Button("削除", role: .destructive) { delete(connection) }
                                Button("編集") { editing = connection }.tint(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("DeskLink")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("PC を追加", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(isPresented: $isAdding) {
                ConnectionEditView(connection: nil)
            }
            .sheet(item: $editing) { connection in
                ConnectionEditView(connection: connection)
            }
            .fullScreenCover(item: $active) { connection in
                SessionView(connection: connection)
            }
        }
    }

    private func delete(_ connection: Connection) {
        KeychainStore.setPassword(nil, for: connection.id)
        CertificateTrust.forget(host: connection.host, port: UInt16(clamping: connection.port))
        modelContext.delete(connection)
    }
}

private struct ConnectionRow: View {
    let connection: Connection

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "pc")
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let date = connection.lastConnectedAt {
                Text(date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        var parts = [connection.address.displayString]
        if !connection.username.isEmpty {
            parts.append(connection.domain.isEmpty ? connection.username : "\(connection.domain)\\\(connection.username)")
        }
        return parts.joined(separator: " · ")
    }
}
