import SwiftUI

struct MainWindowView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        MenuBarContentView(store: store, fixedWidth: nil)
            .frame(minWidth: 560, minHeight: 460, alignment: .topLeading)
            .background(.regularMaterial)
    }
}
