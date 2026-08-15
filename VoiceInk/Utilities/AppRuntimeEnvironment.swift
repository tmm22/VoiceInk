import Foundation

enum AppRuntimeEnvironment {
    /// XCTest launches the application as a test host before loading the test bundle.
    /// Keep that bootstrap isolated from persistent stores and physical hardware.
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCInjectBundleInto"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()
}
