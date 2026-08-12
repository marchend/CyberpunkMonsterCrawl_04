import SpriteKit

/// The single sanctioned way to construct an `SKTexture` from a name in
/// `Assets.xcassets`.
///
/// `docs/bootstrap.md` \u00a71 pins the art direction to "1\u00d7 art only, integer
/// scaling": `SKTexture.filteringMode = .nearest`, no mipmaps, so pixel-art
/// sprites upscale losslessly with hard edges instead of a blurred bilinear
/// blend. Every future consumer of an atlas-sheet texture (player, raccoons,
/// bullets, pickups, pulse, hit puff, signs, the ground tileset) must go
/// through `TextureLoading.texture(named:)` rather than constructing an
/// `SKTexture` directly, so this convention cannot be forgotten one call site
/// at a time. `TextureLoadingTests` proves both halves of that convention \u2014
/// filtering mode and mipmaps \u2014 on every atlas sheet the contract references.
enum TextureLoading {
    /// Loads the named catalog image as a nearest-filtered, mipmap-free
    /// `SKTexture`.
    ///
    /// `SKTexture(imageNamed:)` never generates mipmaps on its own, but
    /// `usesMipmaps` is set explicitly rather than left to the default so the
    /// invariant is stated where it is enforced: mipmapping blends adjacent
    /// pixel-art texels exactly the way `.nearest` filtering is meant to
    /// avoid, and `TextureLoadingTests` asserts it stays off.
    static func texture(named name: String) -> SKTexture {
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .nearest
        texture.usesMipmaps = false
        return texture
    }
}
