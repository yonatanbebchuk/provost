import SwiftUI

struct RootView: View {
    @Environment(DemoStore.self) private var store

    var body: some View {
        Text(AppConfig.productName)
            .task { await store.loadRecents() }
    }
}
