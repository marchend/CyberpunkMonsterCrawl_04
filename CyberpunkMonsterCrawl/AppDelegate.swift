import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // `SCAFFOLDING(CYBERPUN-17-10)`: arm the DEBUG-only crash capture
        // before `SceneDelegate` ever constructs `GameViewController`/
        // `GameScene` -- i.e. before `GameScene.commonInit()` ever mounts a
        // `PulseRingNode` -- so a crash at first `.gameplay` entry or at
        // the first pulse-button press is already covered. See
        // `CrashDiagnostics`'s own doc comment for why both a POSIX signal
        // handler and an NSException handler are installed, and why neither
        // changes behavior on the non-crashing path.
        //
        // Compiled out of Release along with `CrashDiagnostics` itself
        // (`#if DEBUG` here and at the top of that file -- the
        // `LaunchGotoState` launch hook this gating was modelled on is
        // gone, deleted as scaffolding by `CYBERPUN-17-13-t3`/PR #51), so
        // a shipped binary keeps its own
        // process-wide exception/signal dispositions untouched. Deleted
        // together with that file once the still-unfiled crash-cause ticket
        // names the frame and closes.
        #if DEBUG
        CrashDiagnostics.install()
        #endif
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
