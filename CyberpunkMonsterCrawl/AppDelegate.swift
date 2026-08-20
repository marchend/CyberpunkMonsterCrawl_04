import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // `CYBERPUN-17-10-t5`: installed before `SceneDelegate` ever
        // constructs `GameViewController`/`GameScene` -- i.e. before
        // `GameScene.commonInit()` ever mounts a `PulseRingNode` -- so a
        // crash at first `.gameplay` entry or at the first pulse-button
        // press is already covered. See `CrashDiagnostics`'s own doc
        // comment for why both a POSIX signal handler and an NSException
        // handler are installed, and why neither changes behavior on the
        // non-crashing path.
        CrashDiagnostics.install()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
