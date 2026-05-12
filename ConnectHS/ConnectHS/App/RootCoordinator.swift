import SwiftUI
import Observation

/// Lightweight cross-tab coordinator. Holds the navigation path for the feed
/// tab so deep-link routing can append destinations from outside `FeedView`,
/// and exposes a one-shot `cameraRequest` token that `FeedView` watches via
/// `.onChange` to present the capture sheet.
///
/// We keep this separate from `AuthViewModel` because routing concerns
/// outlive auth-state transitions and shouldn't be entangled with bootstrap.
@MainActor
@Observable
final class RootCoordinator {

    /// The selected tab index for `MainTabView`. Deep links flip this so the
    /// feed tab is foregrounded before pushing a post or memory destination.
    var selectedTab: Int = 0

    /// Drives `FeedView`'s `navigationDestination(for: FeedPost.self)`.
    /// Lifted out of `FeedView` so deep-link handlers can append onto it.
    var feedPath = NavigationPath()

    /// Bumping this UUID asks `FeedView` to present the camera. We don't use
    /// a Bool because dismissing the sheet would clear it, and a second deep
    /// link with the same value wouldn't re-fire.
    var cameraRequest: UUID?

    /// Set by deep-link handling when a `connecths://group/{id}` link arrives
    /// for a group the user isn't currently viewing (or isn't a member of).
    /// `MainTabView` consumes and clears it.
    var pendingGroupSwitch: UUID?
}
