import UIKit

/// Shared "Pixel Grit" direction colors (docs/bootstrap.md \u00a71 / CYBERPUN-17-2's
/// "heavy dark, hot neon accents" menu-chrome direction).
///
/// Centralized here so every screen (`MenuScreenNode` today;
/// `GameplayScreenNode` / `DeathScreenNode` / `HighScoresScreenNode`
/// skeletons) draws from one palette instead of scattering literal
/// `UIColor`s that could quietly drift apart between screens.
enum PixelGritPalette {
    /// Heavy dark background fill behind every screen.
    static let background = UIColor(white: 0.04, alpha: 1.0)

    /// Hot neon accent (cyan) reserved for the primary call-to-action
    /// (PLAY).
    static let neonAccent = UIColor(red: 0.0, green: 0.95, blue: 0.85, alpha: 1.0)

    /// Secondary, lower-emphasis neon accent (magenta) used for skeleton /
    /// placeholder screen chrome so it reads as "not final" without being
    /// invisible.
    static let neonSecondary = UIColor(red: 0.95, green: 0.05, blue: 0.65, alpha: 1.0)

    /// Plain dark plate fill for non-primary buttons (RUN AGAIN, back-to-menu,
    /// the HIGH SCORES placeholder entry).
    static let plate = UIColor(white: 0.12, alpha: 1.0)
}
