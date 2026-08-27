# Pixel weapon visual rig v1

This contract keeps the delivered 96×96 RGBA weapon recognizable while its mechanism axes animate it. It is structural data, not an object-name recipe.

The pre-generation drawing contract and automatic redraw gate are documented in `docs/MECHANISM_DRIVEN_WEAPON_GENERATION.md`.

## Pipeline

1. The semantic AI declares the mechanism axes.
2. A post-image structural pass may write `visual_rig.json` for the delivered pixel image. That explicit AI structure is preferred when present.
3. If that sidecar is absent for a soft mechanism, `AutomaticPixelVisualRigBuilder` follows the real Alpha pixels from `GripPrimary` to `StrikePoint`, uses the AI mechanism axes to split handle/body/tether/terminal roles, and emits the same contract automatically.
4. `CombatFeelAssetLoader` validates the AI source, confidence, automatic ownership, masks, paths and axis compatibility.
5. `PixelWeaponVisualRig` assigns every visible source pixel to a structural role.
6. `PixelWeaponDeformer` moves the original RGBA pixels along the compiled body and tether paths.
7. Rendering and collision consume the same joined paths, deployed terminal position and live-contact portion.

If both the explicit structural pass and automatic Alpha path fail, or if the result contradicts the AI mechanism axes, the input fails closed with an `AI_VISUAL_RIG_*` error. It is sent back to AI processing; the player is never asked to choose an attack or repair the rig.

## Structural roles

- `rigid_root`: grip, guard, reel or another fixture that stays rigid at the held pivot.
- `rigid_body`: another part that follows the held rigid transform.
- `deform_body`: the primary structure driven by `flex_topology`.
- `tether`: a second structure driven independently by `tether_topology`.
- `terminal`: a rigid hook, ornament or concentrated endpoint mass that follows the final path tangent.

`tether_deployment` is separate from both path shape and hit reaction. `fixed_length` preserves the connected-line motion, `cast_retract` compresses the line during load, flies the terminal outward, holds it taut, then retrieves it, and `launch_tension` flies the terminal outward and keeps the connection tensioned. These phases are compiled from anonymous axes; no weapon name selects them.

`deform_body` and `tether` require a source centerline and mask radius. Rigid and terminal parts require an explicit mask polygon and pivot. The first point of the primary source path is also the body-to-fixture connection, so a soft body begins at the front of its handle rather than at the character's hand.

## Invariants

- `automatic` must be `true`.
- `player_confirmation_required` must be `false`.
- Confidence must be at least `0.65`.
- Every visible source pixel must be assigned exactly once for rendering.
- Active soft axes must have corresponding visual roles.
- Runtime mechanism code may not branch on an asset ID or weapon name.
- Nearest-neighbor raster evidence must retain source colors, keep rigid parts unchanged, keep connections continuous and produce distinct geometry for bending shafts, continuous lines and linked segments.

The developer samples under `data/combat_feel/live_assets/soft_weapon_v1` cover a composite shaft plus tether, a continuous soft body, a linked soft body and a rigid control. They carry no playtest or tuning claim.
