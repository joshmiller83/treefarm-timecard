import Foundation
import TreeFarmKit

/// Words the screens need that `WatchDisplay` doesn't have yet. Each is asked of the lead, to
/// move into `WatchDisplay` (slice 0 owns it); until then they live here, in one place.
enum WatchCopy {
    /// The Today page's title.
    static let today = "Today"
}
