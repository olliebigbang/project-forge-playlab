# V1 Build Report

Date: 2026-08-01 (Australia/Sydney)

## Environment

- Godot: `4.7.1.stable.official.a13da4feb`
- Renderer: GL Compatibility / WebGL 2
- Primary platform: Windows desktop tooling, Web export
- Runtime services: offline Mock only

## Commands executed

```powershell
./scripts/test.ps1
./scripts/build_web.ps1
./scripts/serve_web.ps1
```

The Web build was opened in a Chromium browser through Playwright at `http://127.0.0.1:8060`. The Forge page, three-weapon gallery, review, anchor debug screen, training area, touch controls, sustained firing, and room-one combat were exercised. Browser console result: 0 errors and 0 warnings after the final UI/font/layout fixes.

The deterministic suite reports 15 passed and 0 failed. A direct Godot scene-tree flow diagnostic additionally reached `room_1 → intermission → delta → room_2 → survey → complete` before the temporary diagnostic was removed.

## Evidence

- `screenshots/fixed-weapons.png`: all three fixtures and resolved anchors.
- `screenshots/anchor-debug.png`: bounds, axis, five anchors, confidence, and source.
- `screenshots/character-holding.png`: character, both hands, mounted weapon, training targets, and touch controls.
- `screenshots/muzzle-fire.png`: blue projectiles visibly originating at the muzzle.
- `screenshots/review.png`: player-facing interpretation and generated pixel weapon.
- `screenshots/forge-input.png`: final Chinese input and sketch layout from the exported Web build.

## Delivery assessment

`CONFIRMED`: The build is ready for a moderated human V1 playtest. It is not a production build and should not be merged directly into either formal Project Forge repository.

Highest-risk items to validate with people:

1. Whether a rough sketch materially improves perceived ownership rather than merely changing proportions.
2. Whether automatic grip/muzzle anchors remain believable on genuinely poor, unusual silhouettes.
3. Whether one bounded modification feels meaningfully different in room two without exposing internal rules.
