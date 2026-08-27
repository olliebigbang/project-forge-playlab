# Enemy Attack Mechanisms V1

## Purpose

This slice compiles anonymous enemy-attack data into a deterministic runtime
contract. It covers attack axes, attack selection, telegraphing, hit regions,
interruptibility, and post-attack recovery.

The slice does not infer an attack from an enemy name, change player weapon
parsing, ask the player how an attack should work, or connect the result to a
scene or enemy state machine.

Integration note: this document records the original isolated compiler slice.
The later scene/state-machine connection lives in
`docs/COMBAT_MECHANISM_INTEGRATION_V1.md` and keeps these compiler boundaries
unchanged.

## File boundary

The implementation is isolated to:

- scripts/enemy_attack/enemy_attack_mechanism_compiler.gd
- scripts/enemy_attack/enemy_attack_selector.gd
- tests/test_enemy_attack_mechanisms_v1.gd
- scripts/test_enemy_attack_mechanisms_v1.ps1
- docs/ENEMY_ATTACK_MECHANISMS_V1.md

Existing player weapon resolvers, generated-weapon code, combat actors, and
scenes remain untouched.

## Data contract

An attack declaration has exactly three top-level fields:

    {
        "attack_key": "slot_0",
        "axes": {
            "delivery": "contact",
            "target_lock": "direction_on_commit",
            "hit_shape": "capsule",
            "depth_path": "same_lane",
            "tempo": "standard",
            "stability": "tell_interruptible",
            "recovery": "punishable"
        },
        "selection": {
            "preferred_range": "close",
            "depth_fit": "aligned",
            "base_priority": 50,
            "coordination_cost": 1,
            "requires_clear_path": false,
            "selection_rank": 10
        }
    }

attack_key is an opaque cooldown address. It is returned to the runtime but is
never used to derive mechanics, score, or break ties.

Unknown top-level, axis, and selection fields fail closed. In particular,
enemy_name and enemy_kind are not accepted inputs.

## Mechanism axes

| Axis | Legal values | Compiled responsibility |
| --- | --- | --- |
| delivery | contact, rush, projectile, marked_impact | origin, motion, active time, hazard lifetime, cue family |
| target_lock | live_until_active, direction_on_commit, point_on_commit | lock event, aim reference, tracking phases |
| hit_shape | capsule, arc, circle, strip | preview and hit geometry |
| depth_path | same_lane, cross_depth, depth_band | path mode and depth tolerance |
| tempo | quick, standard, committed | telegraph and commit durations |
| stability | fragile, tell_interruptible, armored_commit | phase interrupt flags and interrupt threshold |
| recovery | brief, punishable, extended | recovery duration, movement, turning, stagger vulnerability |

Every compiled runtime family declares its owning axis in parameter_owners.

## Fixed attack phases

Every valid attack compiles to:

    telegraph -> commit -> active -> recovery

Target tracking is represented as data. direction_on_commit and
point_on_commit stop target updates at commit_start. Runtime motion always has
direction_changes_after_lock set to false.

An interruption transitions to recovery instead of skipping the authored
post-attack window.

## Telegraph and hit agreement

The compiler creates hit_region once, hashes it, and deep-copies it into
telegraph.preview_region. Both carry the same geometry signature. A consumer
therefore has one source of truth for shape, dimensions, path mode, origin,
and depth tolerance.

## Combination rules

- rush requires direction_on_commit and a capsule or strip.
- marked_impact requires point_on_commit and a circle or strip.
- projectile accepts a capsule and cannot use point_on_commit.
- live_until_active is limited to contact and projectile delivery.

Invalid combinations return structured errors without fallback guessing.

## Attack selection

The selector accepts compiled attacks and a pure context dictionary:

    {
        "distance_pixels": 180.0,
        "depth_delta_pixels": 12.0,
        "available_coordination_budget": 2,
        "clear_path": true,
        "cooldown_remaining_by_key": {},
        "previous_mechanism_signature": ""
    }

Eligibility is checked before scoring:

1. cooldown must be ready;
2. coordination cost must fit the available budget;
3. a required clear path must be available;
4. distance and depth must fit the compiled selection bands.

Eligible attacks are scored by base priority, distance fit, and depth fit.
Repeating the previous mechanism signature receives a fixed penalty. Equal
scores use selection_rank and finally declaration order, never attack_key or
enemy identity.

No eligible attack returns NO_ELIGIBLE_ATTACK. Selection never asks the player
to resolve ambiguity.

## Test coverage

The standalone test verifies:

- the fixed four-phase contract;
- shared telegraph and hit geometry;
- all four delivery families through one anonymous compiler;
- explicit target-lock timing;
- phase-specific interruptibility;
- distinct recovery punish windows;
- a finite compiled difference for every mechanism axis;
- fail-closed identity fields and invalid combinations;
- deterministic range, depth, path, budget, cooldown, repeat, and rank choice;
- absence of enemy-name and enemy-kind dispatch in mechanism sources.
