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
/// at a time. `TextureLoadingTests` proves the filtering mode on a
/// representative sample of the imported sheets.
enum TextureLoading {
    /// Loads the named catalog image as a nearest-filtered `SKTexture`.
    ///
    /// `SKTexture(imageNamed:)` never generates mipmaps on its own \u2014 there is
    /// no separate mipmap-generating call in this factory, and there must
    /// never be one added here, since mipmapping blends adjacent pixel-art
    /// texels exactly the way `.nearest` filtering is meant to avoid.
    static func texture(named name: String) -> SKTexture {
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .nearest
        return texture
    }
}
