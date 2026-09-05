# Sunny adventurer V2: source and limitations

Date: 2026-08-31. Generated with the built-in `image_gen` tool, using the imagegen skill. No FAL/CLI fallback or new purchase.

- `adventurer_atlas_draft.png`: first concept, 1254×1254 RGB; contains a painted checkerboard. Rejected for runtime use; retained as provenance.
- `adventurer_atlas.png`: second generation (edit request), 1536×1024 RGBA. Modular head/torso/arms/fist/reference character. AI-generated, not a commissioned hand-pixelled atlas.
- Used atlas SHA256: `2BC90368D8DA7A3A895DFA3E3C062351F2960603A63A3667298254AEFF6790D9`.
- Draft tool output: `<USERPROFILE>/.codex/generated_images/019fe6eb-7780-7481-9107-a5f11c987f4e/exec-07e88447-fe8b-4682-a005-f2e4f4b71feb.png`.
- Used tool output: `<USERPROFILE>/.codex/generated_images/019fe6eb-7780-7481-9107-a5f11c987f4e/exec-3a97b76b-4b69-41fe-9952-7e9e7014bb85.png`.
- Initial visual reference: actual previous Sunny game capture `.tools/sunny-player/review-1788153488-32764/01-idle-right.png`; used for environment palette/context, not to claim official SunnyLand authorship.

The second output carries real alpha but also unwanted translucent glow. The game samples explicit atlas regions with nearest filtering and applies a runtime alpha cutout at 0.94. No external raster editing, manual redraw, or baked corrected-alpha file is claimed. The source PNG is preserved byte-for-byte. Runtime region cropping, limb transforms and clothing modulation are assembly operations, not a complete authored animation set. V2 originally used a neck patch; V2.1 removes it and positions the head from the actual torso-neck socket. Each arm now uses its own real sleeve socket, with distinct wrist and palm/grip positions. The V2.1 assembly correction made no image-generation calls and leaves the atlas SHA256 above unchanged.

Motion/leg silhouettes and fixed arm lengths remain from the user's licensed Dead Revolver package; see `../dead_revolver_player_v1/SOURCE.md`. No original package image was overwritten. New torso/head detail density is still higher than the prototype legs; this is an intermediate playable art direction, not final commercial art.

## Generation prompt

```text
Use case: stylized-concept
Asset type: production 2D pixel-game modular character sprite atlas, genuinely transparent PNG.
Primary request: design a charming, clean, lightly adventurous HUMAN hero for the bright side-on Sunny training arena in reference image 1. Replace the unattractive bald mannequin with a coherent finished look. A youthful adult explorer with short tousled chestnut hair, visible friendly face looking RIGHT, muted teal short-sleeved travel jacket over ivory shirt, small warm ochre neckerchief, slim navy trousers, warm brown belt/boots. Not chibi, not gritty, not armor.
Reference image 1 is environment and scale/style context only. Do NOT reproduce its background, text, weapon, frog, UI, or mannequin.
Composition: a square atlas divided invisibly into exactly 3 columns by 2 rows of equally sized cells. Each cell has one centered isolated component on transparent background, generous padding, nothing touching another cell. No printed grid or labels.
TOP LEFT: only a complete head including chestnut hair, visible eye, nose, ear and short neck, in RIGHT-facing strict side/three-quarter-side view.
TOP MIDDLE: only a complete ARMLESS torso with teal jacket, ivory shirt, small ochre scarf, belt, and hips; no head, no arms, no legs. Shoulder attachment intact. Right-facing side view.
TOP RIGHT: a single straight upper arm, long axis vertical pointing downward, rounded shoulder at top and elbow at bottom; short teal sleeve covering upper half, warm skin lower half. No forearm or hand.
BOTTOM LEFT: a single straight slim forearm long axis vertical downward, elbow at top and wrist at bottom; warm skin, small brown wrist cuff. No fist and no upper arm.
BOTTOM MIDDLE: a single small closed right-facing hand/fist, warm skin with simple clear thumb and fingers, suitable to wrap a gun grip.
BOTTOM RIGHT: one complete assembled reference hero using precisely these components and navy trousers/brown ankle boots, facing right in relaxed neutral stance, no object held.
All six cells are separate, at the SAME conceptual pixel density with consistent anatomy. Intended final standing hero is about 72-80 game pixels tall, head about 16 pixels tall, torso about 28 pixels tall, slender arms not bodybuilding. Art should look like an excellent hand-authored platform action sprite at small size: crisp deliberate square pixel clusters, one-pixel dark blue-green outlines, around 18-24 colors total, only 2-3 shades per material. Large readable shapes over small ornament. No gradient, no painterly texture, no dither/noise, no glows, no anti-aliasing fringes, no vector curves. Do not draw one huge character instead of the component atlas. Actual transparent alpha, not a drawn checkerboard. No text, logos, weapons, scenery or shadows.
```

## Second-call edit prompt

```text
Use case: background-extraction / precise-object-edit.
Edit the supplied modular adventurer atlas. Correct ONLY its background: the first image contains a painted pale checkerboard, which is a defect. Remove the entire white/light-gray checkerboard and provide ACTUAL alpha transparency, including every gap between the six isolated components. Preserve all six component silhouettes, their positions, all colors, anatomy, dark outlines, pixel details and the exact 3-column/2-row layout. Do not redraw the hero or add labels. Do not output a checkerboard as imagery again. The result is a texture for a game, not a preview illustration. If the output format cannot carry alpha, use a perfectly FLAT UNIFORM saturated magenta #FF00FF field instead, with NO checkerboard, no shadow, no gradient and no antialias blend into that field; this would be explicitly treated as a keyed source, not claimed to be transparent. Keep the six subjects unchanged.
```
