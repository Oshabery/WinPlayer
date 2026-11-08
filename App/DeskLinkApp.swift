import SwiftData
import SwiftUI

@main
struct DeskLinkApp: App {
    var body: some Scene {
        WindowGroup {
            ConnectionListView()
        }
        .modelContainer(for: Connection.self)
    }
}
