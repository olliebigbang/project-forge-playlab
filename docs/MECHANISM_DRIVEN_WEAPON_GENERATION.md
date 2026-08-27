# Mechanism-driven weapon generation v1

This contract makes the generated 96×96 weapon silhouette expose the AI-declared mechanism axes before combat animation begins. It does not classify by weapon name and does not ask the player to choose an attack.

## Data flow

1. The semantic AI declares and validates the affordance profile.
2. `MechanismVisualBrief` converts only the structural axes into a name-free drawing contract.
3. `OpenIdentityVisualPrompt` keeps the player's object identity first, appends the drawing contract, and records prompt policy `forge-open-identity-v3`.
4. `MechanismPixelScaffold` deterministically draws the held root, primary body, optional tether, visible joints, terminal and contact face on the final 96×96 canvas. It also emits expected `GripPrimary`, `StrikePoint` and `TetherOrigin` anchors plus one shared palette.
5. The formal local generation path sends a nearest-neighbour 512×512 copy of that scaffold as the trusted edit reference. The mechanism axes own structure; FLUX or another visual provider may change only surface style and color. The player's sketch is not used as a competing structural reference on this path.
6. Provider output must already be 96×96 with a transparent background. The runner rejects wrong dimensions, opaque backgrounds and large scaffold drift instead of resizing or silently cutting out the result.
7. Godot locally searches the real Alpha near the scaffold anchors, then resolves the mechanism axes and automatic pixel visual rig from the delivered sprite.
8. `MechanismVisualReadabilityGate` checks whether the declared structures are actually visible.
9. A failed structure check produces an automatic redraw instruction. An external provider may receive at most two redraws.
10. If configuration, generation, identity evidence, Alpha preflight, or both redraws fail, the exact mechanism scaffold becomes the honest local fallback. It is labelled as a fallback, not as an external generation success. There is no player question about attack mechanics or rig repair.

Player confirmation of the source object's identity remains a separate identity step. It cannot change the AI-owned attack mechanism.

## Axis-to-drawing contract

| Mechanism axis | Required still-image evidence |
|---|---|
| `handle_length` | no detached handle, or a visibly short, medium, or long rigid held fixture |
| `body_length` | compact, medium, or long functional span from held region to contact end |
| `grip_topology` | compact one-hand zone, separated two-hand zones, integrated body grip, or clamp/ring/bracket fixture |
| `mass_distribution` | silhouette volume concentrated near the held region, balanced across the span, or concentrated near the contact end |
| `contact_surface` | a readable point, long edge, broad face, or whole-body contact outline |
| `secondary_contact_surface` | a separate second point, edge, broad face, or whole-body contact region when declared |
| `rigidity` | rigid or semi-rigid connected body when no soft topology is active |
| `flex_topology=bending_shaft` | one connected body with a curved centerline rather than a straight bar |
| `flex_topology=flexible_line` | one continuous slender, curved, tapering body |
| `flex_topology=linked_segments` | repeated connected sections with visible joints rather than one smooth line |
| `tether_topology` | a second connected path whose direction remains visibly independent from the primary body |
| `terminal_load` | a distinct light or heavy end mass wider than the path before it |
| `tether_mode=wrap` | enough returning curve to show wrapping capacity without an effect trail |
| `tether_mode=hook` | a readable angled catching point at the line end |
| `tether_deployment=fixed_length` | the attached path stays extended and transmits held motion without changing length |
| `tether_deployment=cast_retract` | a reel or line reserve supports load, outbound terminal flight, tension, and visible retrieval |
| `tether_deployment=launch_tension` | a launch guide and reserve support outbound terminal flight followed by a tensioned connection |

All requirements target chunky silhouette regions that survive pixel reduction. Micro-detail and motion trails do not count as mechanism evidence.

The deterministic scaffold has a finite-difference contract test: starting from one valid baseline, each of the 12 axes is changed alone and must alter at least 32 pixels on the final 96×96 RGBA image. This prevents an axis from existing only in text while doing nothing to the visible weapon.

## Readability gate

The gate uses the delivered pixels and rig, not the text prompt, to measure:

- grip-to-strike span relative to the canvas;
- required structural-role pixel coverage;
- primary-body curvature, turning, and slenderness;
- repeated width peaks or repeated color transitions for linked sections;
- tether length, connection, and directional independence;
- terminal pixel count and extent.

A straight bar therefore cannot pass as a flexible line, splitting one straight bar into two labels cannot pass as an independent tether, and a smooth line cannot pass as linked sections.

## Evidence files

Each mechanism-aware generation keeps:

- `visual_structure_brief.json`: exact AI-axis drawing contract;
- `mechanism_scaffold.png` and `mechanism_scaffold.json`: exact 96×96 geometry and anchor contract owned by the mechanism axes;
- `mechanism_scaffold_reference.png`: the 512×512 nearest-neighbour edit reference used by the formal local provider;
- `mechanism_scaffold_handoff.json`: real-Alpha anchor drift, Alpha IoU, authority split, and whether an external generator actually succeeded;
- `mechanism_scaffold_rejection.json`: the same preflight evidence and rejection reason when a provider image drifts away from the locked structure;
- `manifest.json`: provider, seed, redraw number, input/output hashes, Alpha preflight and provider settings, with `structure_authority=mechanism_axes`, `generator_authority=style_and_color_only`, and no API credential or image payload;
- `mechanism_visual_gate.json`: final pass/fail result and measured pixel metrics.

The fallback directory additionally keeps `processed_sprite.png`. Its manifest says `visual_mode=mechanism_scaffold_fallback`, `external_generator_succeeded=false`, and `player_mechanism_confirmation_required=false`. The later review remains only an object-identity check and cannot alter the attack mechanism.

`tools/comfyui/flux2/bridge/run_mechanism_pixel_provider_matrix.py` runs all three providers through one matrix. Retro reads `RD_API_KEY` or `RETRO_DIFFUSION_API_KEY`; PixelLab reads `PIXELLAB_API_TOKEN` or `PIXELLAB_API_KEY`. A missing credential is recorded as `skipped_missing_credential`, never as a fabricated provider result. The runner never asks for mechanism input and records that no playtest or feel tuning occurred.

This is generation/readability evidence only. It makes no playtest or combat-feel claim.
