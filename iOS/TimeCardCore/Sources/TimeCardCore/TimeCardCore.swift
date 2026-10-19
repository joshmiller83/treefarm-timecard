import Foundation
@_exported import TreeFarmKit

/// Settings the whole app agrees on.
public enum TimeCardCore {
    /// The production server. Settings can point the app somewhere else (advanced).
    public static let defaultServerURL = URL(string: "https://timecard.joshnliz.com")!
}
