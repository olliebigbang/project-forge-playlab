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
