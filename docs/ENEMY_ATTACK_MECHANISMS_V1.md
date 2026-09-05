# Enemy Attack Mechanisms V1

## Purpose

This slice compiles anonymous enemy-attack data into a deterministic runtime
contract. It covers attack axes, attack selection, telegraphing, hit regions,
interruptibility, and post-attack recovery.

The compiler does not infer an attack from an enemy name, change player weapon
parsing, or ask the player how an attack should work. The same output is now
consumed by the shared arena state machine for preview, hit, persistent hazard,
directional defense, recovery, and optional modifier execution.

Integration note: the original seven axes and declarations remain backwards
compatible. The September 2026 V2 extension adds two optional axes with neutral
defaults, plus a separate anonymous modifier stack.

## File boundary

The core compiler boundary is:

- scripts/enemy_attack/enemy_attack_mechanism_compiler.gd
- scripts/enemy_attack/enemy_attack_selector.gd
- scripts/enemy_attack/enemy_attack_runtime_driver.gd
- scripts/enemy_attack/enemy_modifier_compiler.gd
- tests/test_enemy_attack_mechanisms_v1.gd
- scripts/test_enemy_attack_mechanisms_v1.ps1
- docs/ENEMY_ATTACK_MECHANISMS_V1.md

Player weapon parsing and generated-weapon identity remain outside this
contract. `gameplay_arena.gd` consumes the compiled result; it does not compile
mechanics from an enemy display name.

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
            "recovery": "punishable",
            "hazard_mode": "instant",
            "defense_mode": "none"
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
| hazard_mode (optional) | instant, lingering, pulsing | persistence duration, repeat/pulse contact windows |
| defense_mode (optional) | none, frontal_guard, channel_guard | defended phases, facing arc, break threshold and exposure |

Omitting either optional axis is identical to `instant` and `none`; old data
does not gain a hidden zone or guard. Persistent danger stores the same frozen
origin, direction, and hit region that was previewed. Directional guard consumes
incoming direction and the weapon interaction resolver's interrupt/armor-break
result; it cannot defend from behind unless an explicit 360-degree modifier is
present.

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

## Sunny role separation through existing axes

The September 3 audit found that the spore raider and wind wisp both reached the
same compiled `rush + strip + cross_depth` direction. Different sprites therefore
presented substantially the same movement question. The fix did not add an enemy
identity branch or a new delivery family:

| Catalog role | Close pressure | Far pressure | Player-readable consequence |
| --- | --- | --- | --- |
| Spore raider | committed, tell-interruptible rush with an extended active path | existing projectile | interrupt the wind-up or leave the committed line |
| Wind wisp | quick, fragile contact arc with `live_until_active` tracking | committed `marked_impact` strip, `point_on_commit`, `depth_band`, pulsing hazard | respond to the close swoop, or leave the warned lane before it locks |

The normal selector chooses these declarations from distance, depth, path,
coordination budget, cooldown, priority, and repeat penalty. During the wisp's far
telegraph the point may still follow the target; `point_on_commit` freezes the
origin at commit, so later target movement does not drag the active lane. Strip
and capsule persistent hazards are filled from the same compiled length, width,
direction, and origin used for contact. The fill is presentation of the existing
region, not a second cosmetic hitbox.

Sunny integration tests exercise the near and far selections, the follow-then-lock
transition, and the final active origin. The visual contract expects contact plus
marked impact for the wisp, while the spore rush remains committed and extended.
The balance probe also records attempts, active entries, and warning duration by
delivery, so two declarations cannot silently collapse back into one observed
behavior.

## Anonymous modifiers

An enemy profile may pass a separate list of `{modifier_key, family}` records.
The legal V1 families are `echo`, `barrier`, and `residue`. Keys are opaque; the
runtime branches only on the family. Echo schedules one smaller repeat,
barrier gives one visible breakable all-direction charge, and residue converts
the compiled danger zone into a lower-damage lingering zone. Duplicate families
and unknown fields fail closed. Sunny now assigns all three families to periodic
champions from their existing compiled attack axes. A delayed echo preserves the
original locked origin, direction, and hit region. Residue preserves the same
contact region or rush path after the active phase, including close and rush
deliveries rather than only projectile or marked-impact attacks. Barrier remains
one visible breakable charge. The visual adapter reads only the compiled family:
purple afterimage motes denote echo, green pods/drops denote residue, and cyan
crystal plates denote barrier. The preview and live contact both consume the same
compiled region; no separate cosmetic hitbox is introduced.

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
- neutral compatibility for old declarations;
- distinct instant, lingering, and pulsing runtime contacts;
- frontal/channel direction and phase defense, including an explicit break;
- anonymous echo, barrier, and residue modifiers;
- live clear-path rejection and recovery movement/turn/stagger multipliers.
