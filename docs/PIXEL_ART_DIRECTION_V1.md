# Forge pixel art direction V1

This document defines the production look for the playable forge arena. It is a rendering contract, not a combat-mechanism input.

## Readability order

1. Enemy telegraph and active hit region.
2. Player, held object, enemy silhouette and projectile.
3. Health and action state.
4. Environment detail.

The arena may be atmospheric, but it must never compete with the combat layer.

## Pixel discipline

- Runtime textures use nearest-neighbour filtering.
- Player and enemy silhouettes use hard alpha with no light fringe.
- Character art uses deliberate pixel clusters and a compact palette; isolated one-pixel noise is rejected.
- The 1280x720 arena background is authored from a 640x360 pixel master and displayed at exactly 2x.
- Thin decorative lines, debug grids and soft vector circles do not substitute for finished sprites.

## Palette hierarchy

- Environment: soot black, iron blue and desaturated slate, with restrained ember orange.
- Player: muted cyan accent and a warm skin value, surrounded by a dark outline.
- Enemies: one identity accent per family (ember, electric cyan or frost blue).
- Telegraphs: warm warning red/orange; safe player feedback: cyan/white.

## Scale and composition

- The player reads at approximately 80 pixels tall.
- Standard enemies occupy a 160x128 presentation canvas; the heavy enemy may fill more of that canvas.
- The middle of the floor stays visually calm. High-frequency masonry detail belongs at the frame and horizon.
- Weapons remain real generated object pixels. Character art must support their grip anchors instead of hiding them.

## Rejection checks

- Baked checkerboard or non-transparent sprite background.
- Bilinear filtering, soft alpha halo or fractional display scaling.
- Background detail crossing a combat silhouette at the same brightness.
- A player, enemy or weapon that reads as a placeholder geometric primitive.
- Identity decoration that hides an attack telegraph or changes the compiled mechanism.

## Church sample variant (2026-08-30)

The independent `art_vertical_slice_v1` scene tests one cohesive Ansimuz
GothicVania Church set. It does not silently replace the production forge theme.
Its palette is purple stone, dark plum cloth and warm fire/skin with the source
hero's cyan scarf. Player and enemy sheets remain unchanged and display at 2x;
the hero reads at approximately 90px tall. A perspective stone floor is composed
from a restrained derivative of the source palette, not a second artist's pack.

Keep the two-dimensional walk plane, real weapon pixels and grip geometry.
Sprites sample the existing enemy attack phases; never change the hit timeline
to fit a convenient animation. Depth-sort units, then draw the authoritative
warning regions above them. Do not obscure warnings with a foreground sprite.

This variant is a playable art sample, not a completed all-level reskin. Gun and
object art is still the accepted AI cache and may retain a finer pixel density
than the imported characters. Source provenance, review and scope are recorded
in [Church art sample](CHURCH_ART_VERTICAL_SLICE_V1.md).

### Generated Church objects

The independent `church_forge` adds opt-in `church_v1` generation through the
existing AI/FAL bridges. It uses an explicit text art contract and fixed palette
normalization before anchors/compilation, not reference-image conditioning or a
trained style model. Technical checks do not certify aesthetic quality.

Keep identity accents, source Alpha and object proportions. Do not recolour all
modern objects purple or redesign them as fantasy props. For styled linked
structures, preserve their dark outlines and actual link holes in deformation;
do not bleach the source palette or paint a continuous solid strand across holes.
Do not apply the compact solid-body scale cap to a hanging linked body. Weapon
contact continues to use the same pixel-snapped geometry as the visible object.

See [Church AI Forge](CHURCH_AI_FORGE_V1.md) for live generation and review evidence.
