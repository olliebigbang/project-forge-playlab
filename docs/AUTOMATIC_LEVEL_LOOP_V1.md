# Automatic Level Loop V2

This slice turns the enemy-mechanism work into a short playable level without asking the player to design an enemy.

## Player flow

1. Describe any supported handheld object in Forge. AI identifies the object and declares its mechanism axes without asking the player how it attacks.
2. Enter with either a validated general-object mechanism handoff or a validated firearm handoff. Opening the level directly still offers the accepted firearm armory as a fallback.
3. Fight three encounters in a fixed, reproducible order.
4. Carry remaining health into the next encounter.
5. Reach a completion screen after the third encounter, or a failure screen when health is exhausted.

The three encounters teach telegraph reading, changing position, and attacking during a heavy enemy's recovery window. The player never types an enemy name and never confirms an attack mode.

## Runtime boundaries

- Enemy content comes from `offline_encounter_catalog_v1.json`; no online API is needed during the level.
- Every bundled response is revalidated by `EnemyAIBlueprintResolver` when the catalog loads, so its two attack declarations still pass the existing mechanism compiler.
- The encounter director consumes only the existing enemy profile and `attack_declarations` shapes.
- The level consumes both public `RuntimeMechanismHandoff` payloads: AI-resolved whole-object/soft mechanisms and AI-compiled firearms.
- Soft weapon pixels are deformed from `flex_topology`, `tether_topology`, and `tether_deployment`; the level does not branch on names such as fishing rod or whip.
- The three accepted enemy blueprints resolve formal pixel sprites through `enemy_visual_assets_v1.json`. Identity art is presentation-only; attack selection, telegraphs, hit regions, interruption, and recovery still come from compiled attack axes.
- `ruined_ember_forge_courtyard_v1.png` provides the arena background while the existing world rectangle remains the authoritative movement and combat space.
- Runtime scripts contain no branches for individual enemy names or catalog IDs.

## Play and test

From a completed firearm result in Forge, choose **带这把枪进三战关卡**. From a completed general-object mechanism card, choose **带这个物件进三战关卡**. The standalone scene is `res://scenes/automatic_level_loop.tscn`; opening it directly shows the local firearm picker.

Run the focused regression with:

```powershell
$godot = & .\scripts\find_godot.ps1
& $godot --headless --path . --script res://tests/test_automatic_level_loop.gd
```

The focused suite verifies offline blueprint acceptance, absence of player enemy input, reproducible encounter order, both public handoff types, visible soft-weapon deployment, formal enemy/background resource coverage, execution of distinct compiled attacks, completion, and failure.
