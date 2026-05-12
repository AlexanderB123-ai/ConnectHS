import SwiftUI

@main
struct ConnectHSApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    DeepLinkRouter.shared.enqueue(url)
                }
        }
    }
}
