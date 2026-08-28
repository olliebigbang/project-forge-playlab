# Automatic Level Loop V1

This slice turns the enemy-mechanism work into a short playable level without asking the player to design an enemy.

## Player flow

1. Select a firearm already accepted by `PlayerWeaponArmory`, or enter from Forge with a validated ranged mechanism handoff.
2. Fight three encounters in a fixed, reproducible order.
3. Carry remaining health into the next encounter.
4. Reach a completion screen after the third encounter, or a failure screen when health is exhausted.

The three encounters teach telegraph reading, changing position, and attacking during a heavy enemy's recovery window. The player never types an enemy name and never confirms an attack mode.

## Runtime boundaries

- Enemy content comes from `offline_encounter_catalog_v1.json`; no online API is needed during the level.
- Every bundled response is revalidated by `EnemyAIBlueprintResolver` when the catalog loads, so its two attack declarations still pass the existing mechanism compiler.
- The encounter director consumes only the existing enemy profile and `attack_declarations` shapes.
- The level reads firearms only through `PlayerWeaponArmory.load_entries()` or the public ranged `RuntimeMechanismHandoff` payload.
- Runtime scripts contain no branches for individual enemy names or catalog IDs.

## Play and test

From a completed firearm result in Forge, choose **带这把枪进三战关卡**. The standalone scene is `res://scenes/automatic_level_loop.tscn`; opening it directly shows the local weapon picker.

Run the focused regression with:

```powershell
$godot = & .\scripts\find_godot.ps1
& $godot --headless --path . --script res://tests/test_automatic_level_loop.gd
```

The focused suite verifies offline blueprint acceptance, absence of player enemy input, reproducible encounter order, public weapon handoff integrity, execution of distinct compiled attacks, completion, and failure.
