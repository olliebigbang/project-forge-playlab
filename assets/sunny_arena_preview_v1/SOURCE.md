# SunnyLand environment sample provenance

Date: 2026-08-31. Independent local prototype, not the production theme.

## Original licensed assets

Author: Luis Zuno / Ansimuz.
Official page: https://ansimuz.itch.io/sunny-land-pixel-game-art
Downloaded **Sunny-land-files.zip** using the official free download flow.
No payment, premium Plus pack, music or Dead Revolver assets were acquired.
ZIP SHA256: `EC01249AE89BBEEF94E7B385E36E28F5616F50998B309DF3BBCB608CB0F713AF`.

The included `public-license.pdf` was rendered and visually read. Page 1 states
CC0 for assets in the package. Preserve that source document here. This is source
provenance, not a legal opinion about unrelated assets or generated images.

Original paths below are relative to `Sunny-land-files/` in the ZIP. Files are
copied without pixel edits; only names change. Sprite frame boundaries include
transparent padding: Foxy 33x32, frog 35x32. Do not assume 32px-wide frames.

| Local file | Source |
|---|---|
| fox_idle.png | Assets/Characters/Foxy/idle/spritesheet.png |
| fox_run.png | Assets/Characters/Foxy/run/spritesheet.png |
| frog_idle.png | Assets/Characters/frog/Spritesheets/frog-idle.png |
| bush.png | Assets/environment/Props/bush.png |
| public-license.pdf | public-license.pdf |

SHA256:

```text
fox_idle.png  7FDF3D4BCBAC14B1E8FC5C4333E125E8193F52EC12FCF38DDAE2EB8BF4202A45
fox_run.png   80E78A1B6EDA23A0ADB16A52CF96726474F815695115B9419AEF3A8361CBCC5B
frog_idle.png F978AC4C2C2EC0A61757CDCEA4F9CF67678AB20A60F71511CF2D21D2F01D3D69
bush.png      9577FE3B30BA3A6058AB3FB7DEC99DFEE3DB6815CBE31B0B226F15413041ACE5
public-license.pdf 8F390318202D99975D873F49E7B3390C88D6BE36E68E921824C562521D8AFB53
```

## Newly generated environment

`clearing_generated_v1.png`, `clearing_generated_v2.png` and
`clearing_generated_v3.png` are **AI-generated reference-conditioned environment
art**, not an original Ansimuz tilemap and not a claimed hand-pixelled asset.
The complete environment composition was generated, including the new broad
ground. Existing platform cliff tiles were not stretched. Background houses,
trees and sky imitate the references, rather than being unmodified source tiles.

Tool: built-in image generation (not FAL, not the game's live object pipeline).
The initial sample used two built-in calls: first composition, then a targeted
pixel-density refinement. The subsequent optimization used one more built-in
edit, with v2 as the edit target and the official SunnyLand overview as a style
reference. Original 1672x941 rasters copied unchanged; retained metadata.
The scene now uses **v3**; press B to compare v2 at the same character position
where the shared floor permits it. Both v1 and v2 remain intact.

v1 SHA256:
`DA99A490E0954DE5BAD1DD8864FE98B8B264477C2D573B098F8708DBDEE46C59`.
v2 SHA256:
`785F561CDBDE87370D3889E2519ED716C13046A2130C0CB4B65A2A3383BC3075`.
v3 SHA256:
`BE277E86F42F83EF40DD180302205E5925E4A591C7EDFCEFF64FA95C04C51CFC`.

Reference inputs, from the official page's public previews:

- https://img.itch.zone/aW1hZ2UvMTQ3NzQ3LzI1NjQ4MjU4LmdpZg==/original/OFQaB4.gif
- https://img.itch.zone/aW1hZ2UvMTQ3NzQ3LzE1NTQxMDc2LnBuZw==/original/SzJgDt.png

Runtime samples the entire world into a **320x180 viewport**, composites it at 2x
under the 640x360 Chinese UI, then integer-nearest scales to the window (default
1280x720). Original sprite pixels and sampled background share the world grid.
This ensures a consistent display grid, but
does not prove a hand-authored compact palette or identical pixel-cluster density
to the original pack. It is a style/space sample, not final production assets.

Exact prompts: [v1/v2](PROMPT.md), [v3 edit](PROMPT_V3.md).
The v3 prompt requested a strict compact palette and a farther-back horizon;
the output only partially followed those directions. It is paler, with fewer
ground marks and a cleaner rear grass edge, but visible gradients and rounded
tree shading remain. Runtime floor bounds follow the observed image, not the
unmet horizon position requested in the prompt.
