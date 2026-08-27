# Perceptible mechanism experiment

## Purpose

This branch tests one narrow response to the orthogonal-composer human result
of 3/5: convert subtle parameter differences into categorical contact outcomes
that change the player's decision.

The 3/5 result remains valid. This experiment is not a human-feel pass, does
not replace frozen evidence, and is not wired into the normal player flow.

Branch: `experiment/perceptible-mechanism-verbs`

## Hypothesis

An affordance axis is perceptible when it changes all three layers together:

1. the shape of valid targets;
2. the state caused on contact;
3. the audiovisual/readout language explaining the result.

The experiment therefore maps contact surface to a verb instead of relying on
small differences in startup, knockback, or camera shake:

| Contact surface | Verb | Categorical outcome | Intended decision |
|---|---|---|---|
| `point` | Pin | one nearest target is immobilized and interrupted | choose the dangerous target |
| `edge` | Cleave | an arc can damage several targets | line enemies up across the swing |
| `broad` | Shove | high displacement and interruption | make space |
| `whole_body` | Control | a wide sector locks several targets | occupy and stabilize a crowd |

These are four levels of one `contact_surface` axis, not four weapon classes.
The current longsword, spear, frying pan, and chair are replaceable visual and
affordance samples. Runtime switching asks the developer-only data index for a
sample by surface; the experiment scene and mechanism resolver contain no
sample asset IDs. Replacing the representative for a level therefore requires
an index entry change, not a new combat rule.

The collision overlay, status label, color, and actual enemy state all use the
same verb. `whole_body` receives a wider rendered/collision sector inside this
experiment so "control" is a real spatial property rather than a text claim.

## Run

From the repository root:

```powershell
.\scripts\run_perceptible_mechanism_experiment.ps1 -Surface Broad
```

`Edge`, `Point`, `Broad`, and `WholeBody` are valid starting levels. During play:

- `1`: edge / cleave; currently represented by a longsword
- `2`: point / pin; currently represented by a spear
- `3`: broad / shove; currently represented by a frying pan
- `4`: whole-body / control; currently represented by a chair
- `WASD` or arrows: move
- `Space` or `J`: attack; hold to charge
- `Shift` or `K`: dodge
- `F3`: debug readout

The three waves separately probe contact coverage, interrupting a telegraphed
Ram, and mixed pressure. Switching the object restarts the experiment so each
mechanic is judged against the same setup.

## Acceptance question

Do not ask only whether the weapons "feel different". Ask whether a player can
predict and exploit these facts without reading implementation values:

- the spear stops one chosen threat rather than sweeping a group;
- the longsword cleaves a line or arc of targets;
- the frying pan shoves targets far enough to create space;
- the chair controls a visibly wider group;
- switching surface levels changes the best tactical choice;
- replacing a sample with another object of the same surface preserves the
  base verb while its other affordance axes change timing, reach, and force.

A future blind retest must confirm those readings before this design can be
considered for the default flow.

## Automated evidence

- Perceptible mechanism properties: `6/6` passing.
- Existing Combat Feel Slice 0 regression: `43/43` passing.
- Experiment scene and all four representative assets parse and capture successfully.
- Captures are generated under `output/perceptible-mechanism-capture/`.

Focused test:

```powershell
$Godot = & .\scripts\find_godot.ps1
& $Godot --headless --path . --script res://tests/test_perceptible_mechanism_experiment.gd
```

The repository's larger combat-feel test script currently reaches the older
generalization suite and then fails on stale hashes in the historical frozen
asset index. The referenced files are tracked and unmodified by this
experiment. This branch deliberately does not rewrite those frozen hashes or
reinterpret the old evidence.

## Boundary

The default `CombatFeelSlice0` returns `false` from the experiment hook, so its
existing hit behavior is unchanged. The separate scene opts in explicitly and
loads assets through a developer-only index marked:

- `developer_experiment_only: true`
- `normal_player_flow: false`
- `frozen_evidence_claim: false`
