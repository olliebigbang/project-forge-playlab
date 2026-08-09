# Playlab decisions

Why things are the way they are. Not what the code currently does -- `git log` and the
code answer that, and a log that repeats them goes stale without anyone noticing.

Numbering: `T##` entries were inherited from `project-forge` and keep their original
numbers. `P##` entries are playlab's own; never reuse a number.

---

# Part 1 -- Inherited from project-forge

Copied from `project-forge-claude/tools/shape_metrics/INHERITED_DECISIONS.md`. These were
already CONFIRMED in `project-forge/docs/DECISIONS.md`. Playlab had no decision log, so
none of them travelled -- and two were independently re-learned at cost.

## T51 — stop enumerating weapon categories, use orthogonal mechanic axes

*2026-07-27.* Triggered by a playtester drawing a handgun and getting a sword.

> Expressive ceiling equals the number of categories implemented, and each category
> needs a whole attack shape, animation and hit resolution. That is an arms race you
> lose. Under axes, 5x3x3 = 45 combinations come from under 10 primitives, and the
> AI's question changes from "which box is this" (outside the boxes it must fail) to
> "how does this deliver damage" (**every** drawing has a reasonable answer).

**Relevance to playlab:** Motion Grammar Slice 1A shipped three exact-match rules
(short/front/broad, long/broad, barrel+stock) with `UNSUPPORTED_AFFORDANCE_FOR_SLICE_1A`
as the fallthrough. That is the category model, re-derived 8 days after it was retired
there. Every one of the twelve objects on the slice's own blind-test list — cleaver,
sword, axe, spear, hammer, bat, chair, stool, extinguisher, shield, chicken leg,
fishing rod — falls outside all three rules.

## T76 — the bucket model stops here

*2026-07-28.* `gun` is the last archetype bucket; extension goes through T51's axes.

> Buckets are **addition** (N buckets = N complete behaviours to implement), axes are
> **multiplication** (15 primitives -> 180 combinations). Worse is the degradation
> failure: `other` is not a bucket, it is surrender.

## T77 — the moat is mapping density, and the real risk is shallowness

*2026-07-28.*

> The real risk is not being beaten to it, it is that the mapping is not deep enough.
> If a player draws ten different weapons and gets three feels, "what you drew really
> matters" is an empty promise, and **that** is what kills this project.

**This one came true.** Playlab has exactly three rules, and the first thing its author
said after playing was "the attack pattern is the same, just reskinned."

## T58 — an acceptance matrix cannot validate feel

> A standard that passes while the thing is not fun is not a feel standard.
> Every real defect this round came from human playtesting. Not one was caught by the
> tests or the matrix.

**Relevance to playlab:** its slice reports 42/42, 19/19, 11/11 and 32/32 green while
the live path silently falls back to the legacy compiler. Several of those assertions
are `source.contains("...")` string greps against source text, which cannot observe
behaviour at all.

## T60 — derive from slenderness, not from mass

> Mass saturates above roughly 30px width: `280x30` and `280x60` both measure 1.000 and
> both score power 31.9 — it cannot tell a hammer from a shield. Slenderness separates
> them (8.48 vs 4.44) and is **scale invariant**, so what the weapon *is* depends on
> shape rather than on how big it was drawn.

**Caveat added 2026-08-08 by `tools/shape_metrics`:** the thresholds
(`BULKY_MAX=6.0`, `SLENDER_MIN=12.0`) are calibrated on strokes and **do not transfer
to generated sprites**. Measured on playlab's four real sprites, slenderness spans only
4.43–9.96, putting three of four in the same middle band; `old_mop` and `shotgun_melee`
land 1.02x apart. Re-derive bands per input source, and score on a combination of
metrics rather than on slenderness alone.

## T73 / T74 — offline playable, and the subject is the drawing

`T73`: the game must be fully playable offline; AI carries no mechanics.
`T74`: the sentence is "the **drawing** decides how it fights", not "the AI decides".

**Relevance to playlab:** its whole chain requires local Claude, FLUX and ComfyUI, so it
is not offline playable, and its structure fields are authored by hand rather than
derived. Deriving what geometry can measure and asking the model only for what geometry
cannot see (edge vs blunt, rigid vs flexible, functional parts) restores both.

---

# Part 2 -- Playlab's own decisions

## P01 — sprite scale encodes real-world length, not the size of the frame

*2026-08-09.*

The postprocessor cropped every object to its own bounding box and scaled it to fill a
96px frame. So a 40cm frying pan and a 150cm mop both came out about 90px long: measured
lengths spanned 81.2–99.7px, a 1.23x total spread, for objects whose real lengths span
3.75x.

The consequence was not cosmetic. `melee_motion_compiler.gd` could only clamp reach into
two hard-coded bands (`_short_reach` 72–80, `_long_reach` 126–148) because the measured
length carried no information to interpolate from. "Long things reach further" was
therefore a property of *which rule matched*, not a property of the object — which is
T77's shallowness failure arriving through the asset pipeline instead of through the
rules.

**Decided:** the frame is a shared ruler, not a bounding box. Scale so the object's
principal-axis extent equals `real_length_cm * PX_PER_CM`, with `PX_PER_CM = 0.56` chosen
so the longest known object (the 150cm mop) spans 84px inside the 96px frame. Objects
that are genuinely small are genuinely small on screen — the pan lands at ~22px.

**Why the length has to come from outside the image:** FLUX renders every object filling
its canvas, so the pixels cannot say how big the thing is. No amount of measuring
recovers it. It shipped here as a hard-coded four-object table in `process_sprite.py`,
with sourcing it from the semantic contract deliberately left to a separate task —
**done in P05; the table no longer exists.** The 150cm figure below was that table's
hand-authored guess; the model puts the mop at 140cm (P06), so `PX_PER_CM = 0.56` is now
a constant chosen at the time rather than one derived from a current measurement.

**Why principal axis and not bounding box:** the mop and spoon sit diagonally in frame.
The mop measures 99.7px along its axis inside a 96px box. Scaling by bounding box would
make diagonal objects systematically shorter than upright ones — an artifact of framing,
not of the object.

**Kept backward compatible:** with no length supplied the old fill-the-frame behaviour is
unchanged, because two live callers depend on it.

## P02 — shipped sprites have binary alpha

*2026-08-09.*

Between the soft-alpha ramp and the LANCZOS downscale, 29–57% of visible pixels were
partial alpha. Every silhouette measurement then depended on where you put the cutoff:
slenderness swung up to 21.8% across cutoffs of 0.10 to 0.75. Measurements that move when
an arbitrary constant moves cannot drive mechanics.

**Decided:** force alpha to 0 or 255 after quantisation. Swing goes to exactly 0.0%,
because all four cutoffs then select the same pixels. Measuring becomes counting.

## P03 — hardening alpha exposed two latent bugs in the chroma keyer

*2026-08-09.* Both were pre-existing; soft alpha had been hiding them.

**Enclosed chroma was keyed as solid object.** The background mask is a border flood
fill, so it cannot reach background that the object encloses — the gap inside a trigger
guard. That region was classified as foreground and forced opaque by the solidity floor,
which put a magenta blob in the middle of the shotgun once alpha went binary. Chroma the
flood fill cannot reach is still background; holes are now holes.

**Colour bled inward from transparent pixels.** PIL resamples each channel
independently, so fully transparent magenta still contributed its colour to neighbours.
Across an 8x downscale that painted a purple fringe along every edge. Colour is now
weighted by alpha before resizing.

**The general lesson:** soft edges were not neutral. They were concealing defects, and
every measurement taken through them was a guess. What looked like a free cleanup step
was the thing that made the defects visible at all.

## P04 — rebuilt sprites are evidence, not assets

*2026-08-09.*

Only `shotgun_melee` still has its raw render. The raws for `frying_pan`, `old_mop` and
`giant_wooden_spoon` were never committed, so those three cannot go back through the
postprocessor, which consumes a raw flat-chroma image.

**Decided:** fix the postprocessor for everything generated from here on, and rebuild the
other three from their finished 96px sprites with `rescale_to_real_length.py`, which
applies the same scale formula. Those three come from a lossy source and are labelled as
such. They are written to `artifacts/`, never over `data/` — the frozen assets are
SHA-256 pinned in `index.json` and overwriting them breaks the hash chain and the sample
loads.

## P05 — real length is a contract field, and it is a number

*2026-08-09.* Replaces the hard-coded four-object table P01 shipped as a stand-in.

`real_length_cm` is now required by affordance contract **v1.3**, and the postprocessor
reads it from the sidecar rather than a table in its own source.

**Why a number and not another bucket.** The profile already carries `body_length` as a
three-value ordinal, and it already collides: `old_mop` and `giant_wooden_spoon` are both
`"long"` while measuring 150cm and 60cm. A fourth bucket set would be T51 and T76's
mistake again, in the size dimension — buckets add, and the thing being modelled (reach)
is continuous. `tools/semantic/tests/test_affordance_contract_v1_3.py` pins that
collision as a test so the reasoning cannot quietly rot.

**Why the model has to supply it.** A generated image cannot. Generators fill the canvas
whatever the subject, so pixel length describes the framing, not the object. This is the
split T73/T74 asked for — measure what geometry can see, ask the model only for what it
cannot.

**Why a new version instead of editing v1.2.** v1.1, v1.2 and v1.2.1 are frozen, and the
four shipped sidecars are SHA-256 pinned. v1.3 is a new module alongside them, mirroring
how v1.2.1 was added; existing profiles stay valid under the version they were authored
against and nothing under `data/` is edited.

**Bounds describe the world, not the frame.** 5–400cm. The 96px frame at 0.56 px/cm can
only represent roughly 145–170cm — the exact ceiling depends on how the object sits, as a
diagonal object fits more length than an upright one. A legal length the pipeline cannot
draw fails closed at `REAL_LENGTH_EXCEEDS_SPRITE_FRAME` rather than having the contract
pretend long objects don't exist. Representing a pike means a bigger frame or a smaller
`PX_PER_CM`, not a narrower contract.

**Settled by P06:** the four values now come from the model, not from the hand-authored
placeholder table. `author_v1_3_sidecars.py` remains as the offline path for working
without an API key.

## P06 — the model can estimate length; the estimator must be told the display name

*2026-08-09.* Measured with `tools/semantic/bridge/length_probe.py`, 17 objects x 3
repeats on `claude-opus-5`. Report: `artifacts/length_probe_v1/REPORT.txt`.

**The model is repeatable enough to drive reach.** Worst spread across repeats was 5.6%
(axe 85-90cm, sword 110-115cm); 15 of 17 objects returned an identical number every time.
A field that moved run to run could not drive mechanics however good its median was, so
this was the check that had to pass first. It did.

**Ordering is sound.** Across the sixteen objects other than the giant spoon there were
no ordering violations at all: chicken leg 13 < cleaver 32 < pan 45 < bat 85 < chair 90 <
sword 115 < mop 140 < fishing rod 210 < spear 220.

**The real defect was ours, and the probe is what found it.** `estimate_real_length.py`
sent `canonical_name_en` and omitted `display_name_en`. But T51's canonical-name hygiene
(the whole reason contract v1.2.1 exists) deliberately strips modifiers from canonical
names — so `giant_wooden_spoon` has a `canonical_name_en` of plain `"wooden spoon"`, and
the word "Giant" survives only in `display_name_en`. Asked about a "wooden spoon" the
model answered a correct and useless 30cm. **A field that upstream deliberately
sanitises cannot be the only field a downstream consumer reads.** With the display name
included the same object returns 120cm, and the model's own stated basis contrasts it
against "a normal 30 cm kitchen spoon". The control pair went 1.0x -> 4.0x.

That failure was invisible in the synthetic probe until the probe case was rewritten to
mirror the frozen blueprint exactly. A probe built from hand-written descriptions tests
the estimator against data production never emits — decision T58's complaint, in the
shape of a test fixture.

**Open, and a human call:** the model puts the giant spoon at 120cm, longer than the
sword (115) and the shotgun (100). That is defensible for a weapon named "Giant Battle
Wooden Spoon" but it contradicts the 60cm reference this log's own P01 table used. The
reference has deliberately *not* been edited to match — tuning the expectation to the
answer would make the check worthless. Whoever adjudicates should look at the sprite, not
at either number.

**Frame ceiling is real, not hypothetical.** Spear (220cm) and fishing rod (210cm) both
exceed what a 96px frame at 0.56 px/cm can draw at any orientation. They come from the
slice's own blind-test list, so this is not a contrived case: supporting that list needs a
bigger frame or a smaller `PX_PER_CM`, and P05's `REAL_LENGTH_EXCEEDS_SPRITE_FRAME` is
what stops it failing silently in the meantime.

## P07 — real length drives reach and drawn size; the visible half was the missing half

*2026-08-09.* Closes the line opened by P01. Evidence:
`tools/combat_feel/verify_reach_ab.gd` (re-runnable), `artifacts/length_probe_v1/`.

**Reach was bucket-driven and collided.** `_general_reach` keyed off a three-value length
ordinal, so `old_mop` (140cm) and `giant_wooden_spoon` (120cm) compiled to 144.7 and
144.4 — 0.3px apart. Reach now follows `real_length_cm` and they sit 11.0px apart. The
formula does read sprite pixels, but at 0.067px of reach per px of sprite, so correctly
scaled sprites alone would have moved reach by 1–4px. That path was never going to work.

**The first playtest looked identical, and measuring said why.** Every source sprite is
86px in its own frame, and `render_scale` came from the *same* ordinal as reach, so the
spoon and the mop both drew at exactly 1.180. Same image, same multiplier, pixel-identical
output. The reach change was real and had nothing on screen to show for it. Worth
generalising: a value that only feeds an invisible hitbox cannot be validated by playing.

**Drawn size now follows length too, by its square root.** Straight proportionality was
physically honest and read badly — the 45cm pan drew at 33px against a ~90px character and
the playtester's verdict was "这也太小了". The root also settles a mismatch rather than
trading against it: reach is affine in cm, so a proportional drawing diverged at the short
end and the pan struck from 2.61x its visible tip. Under the root, reach/drawn sits within
1.34–1.48 — tighter than the 0.95–1.43 the code had *before* any of this, so the 72px reach
floor never needed revisiting.

**These two mechanisms are mutually exclusive — do not ship both.** The rescaled sprites in
`artifacts/real_scale_poc/` and `render_scale`-from-length solve the same problem twice.
The game currently draws the frozen 86px sprites and scales them; loading the rescaled ones
without setting `USE_REAL_LENGTH_RENDER_SCALE = false` compounds a linear scale with a root
one, giving pan:mop of 4.52x where 1.76x is intended. **This retires the anchor-rescaling
task P01 left open**: anchors are already multiplied by `render_scale` downstream, so
nothing needs re-deriving as long as the sprites stay as they are.

**Residual collisions, measured over the 17 probed objects** (13 distinct reach values):
`frying_pan = stool` (both 45cm), `baseball_bat = shield` (both 85cm),
`axe = wooden_chair` (both 90cm) — all three *correct*, since those objects genuinely are
the same length. Only `fishing_rod = spear` (210 vs 220cm) is a failure, and it is the
clamp, not the mapping: everything past ~160cm flattens onto 148, and everything under
~21cm onto 72. **Length is informative in the middle of the range and inert at both ends.**

**What this does not fix, and the direction that would.** Length feeds exactly two things,
reach and drawn size. Motion family, tempo, arc and hitbox thickness still come from the
same coarse axes, so "ten weapons, three feels" (T77) stands. The tempting next move —
have length drive more properties — is the wrong shape: it is one axis doing more work,
which is the addition T51 and T76 retired. The multiplication play is *more orthogonal
axes*, so that N primitives keep producing N-fold combinations. Recorded here as the
direction, not as a decision to implement.

## P08 — real quantities pick which weapon you are, never whether you are viable

*2026-08-09.* Prompted by the obvious objection to adding mass as an axis: a real chicken
leg weighs 100g, a sledgehammer 5kg. Fifty times. Let that reach damage and the drawing
that made a chicken leg is punished for being accurate.

**The objection is right about physics and wrong about this codebase**, and the existing
code already shows why. Damage is `{"rapid": 22, "balanced": 27, "committed": 34}` keyed
off tempo — a 1.55x total spread, bound to a three-value class, touching no continuous
quantity. Physics cannot reach it. Measured over the timing each tempo configures:

  tempo        damage   swing    DPS    movement kept
  rapid            22   0.39s   56.4             0.82
  balanced         27   0.56s   48.2             0.62
  committed        34   0.78s   43.6             0.42

**Light is not weak — light has the highest DPS and nearly double the mobility.** It trades
per-hit size and reach for rate and freedom. A chicken leg is a fast, mobile, short weapon,
which is a weapon, not a punishment.

**The rule, stated so it can be enforced:** a real quantity may decide *which* weapon
something is; it may never decide *whether it is worth using*. This is T51's "every
drawing has a reasonable answer" made checkable — a chicken leg must get a **different**
answer, not a **worse** one. Concretely: anything that multiplies damage by a real
quantity violates it, because real quantities span 50x and the damage band spans 1.55x by
deliberate design.

**How a real quantity is allowed to enter, in three layers.** P01–P07 walked this without
naming it:

  1. the real quantity fixes **ordering and ratio** — who is longer, heavier, slower;
  2. game design fixes the **usable band** — 22–34 damage, 72–148 reach, chosen not derived;
  3. a **compression curve** maps 1 into 2 so both ends stay playable.

Length used exactly this: real cm for order, an 84–138 band the code already assumed, and
a square root once straight proportionality made the 45cm pan unplayably small (P07). The
answer to "surely full realism cannot work" is that it never was full realism — realism
sets the order, design sets the bounds.

**T60 does not forbid mass, and will be misread as if it does.** It says derive from
slenderness *rather than mass*, because ink area saturates: `280x30` and `280x60` both
measure 1.000. That is an indictment of **measuring mass off the drawing**, not of mass.
Real mass in kilograms is precisely what geometry cannot see, which is the case T73/T74
reserve for asking the model. Same argument that justified `real_length_cm` in P05.

**A concrete defect this exposes, worth fixing with the axis.** `_weight_class` returns
`heavy` when `mass_distribution == "front"`, and `_mass_axis` reads the same three-value
field — so nothing in the compiler knows how heavy anything is, only where its mass sits.
All four shipped objects come out `heavy`, and three of four share `mass_axis` 1.0. A
chicken leg is front-weighted, so it classifies `heavy` and would swing slower than a
sledgehammer. **The mass axis today is exactly where the length axis was before P01**: a
categorical standing in for a continuous quantity, colliding everywhere, unnoticed because
there was no magnitude to compare against. The bug to fix is tempo, not damage.

## P09 — real mass is a contract field, and it buys tempo, never damage

*2026-08-09.* Implements the axis P08 argued for. Evidence:
`tools/combat_feel/verify_mass_ab.gd` (re-runnable), `artifacts/mass_axis_poc/`.

`real_mass_kg` is now required by affordance contract **v1.4**, a new module alongside the
frozen v1.1/v1.2/v1.2.1/v1.3 — same shape P05 used, one axis further along.

**Why a number, and why this is not the same argument as P05.** For length the complaint
was resolution: `body_length` measured the right property too coarsely, and mop and spoon
collided inside one bucket. Mass is worse than coarse. `mass_distribution` measures a
*different property* — where the weight sits, not how much there is — and the compiler had
no third option, so it used the wrong field and called it mass. The two are independent:
a chicken leg and a sledgehammer are both `front`, 33x apart. Refining the ordinal could
never have fixed this, because the quantity was not in the profile at all.

**Measured before and after, same sidecar with the mass zeroed on one side.** All six probed
objects compiled to `heavy`, and five of six to a mass axis of exactly 1.000 — the axis was
not merely coarse, it was constant. Afterwards the axis spans 0.350–0.923 and all three
labels are in use. The chicken leg moves `balanced -> rapid` and the shotgun
`balanced -> committed`; the shotgun had been reading `rear` and inheriting 0.35 while
actually weighing 3.2kg.

**Why a logarithm, where length needed only a square root.** Both are P08's third layer, and
the curve has to match the span: length ran 3.75x across real objects, mass runs 33x across
these six and a thousandfold across legal contract values, into an axis band spanning 2.9x.
Straight proportionality is not merely ugly here, it inverts things — a 1.6kg cast iron pan
compiles to `rapid`, the same tempo as a 0.15kg chicken leg, while the 5kg sledgehammer
falls back to `balanced` beside the mop and the spoon. Five of six objects land in one
class, which is the constant axis again wearing a different hat. Under the log the five
objects between 0.15 and 1.6kg spread across 0.39 of the band instead of 0.12.

**The band was deliberately not widened.** `MASS_AXIS_MIN/MAX` are the 0.35–1.0 the ordinal
already produced, because the tempo thresholds, startup, recovery, knockback, stagger,
hitstop and camera kick are all tuned against that range. Real mass changes which object
lands where inside it and nothing else — P08's middle layer, kept honest by keeping the
number the same rather than by intending to.

**Damage was not touched, and the switch that proves it is arithmetic.** Mass reaches damage
only by selecting one of three tempo classes, so across a 33x mass span the base damage
takes exactly three values. `verify_mass_ab.gd` prints that ratio on every run: if anyone
ever multiplies damage by kilograms, the third section stops showing three values and
starts tracking the masses. What the chicken leg gets for being light is 0.39s swings, 0.82
movement and 56.4 DPS against the pan's 0.54s, 0.62 and 50.0 — faster, more mobile, and
better sustained damage in exchange for less per hit. Light is a different weapon, not a
worse one.

**Not measured yet, and it is the same check P06 was.** `estimate_real_mass.py` and
`mass_probe.py` are written and dry-run verified — 18 objects, 17 of them shared with the
length probe so both axes are asked about identical identities, plus an `iron_bar` control
that is the same length as the plain wooden spoon and an order of magnitude heavier. The
live run needs an API key that the authoring session did not have, so **every mass now in
`artifacts/mass_axis_poc/` is hand-authored and is not evidence.** P06 is the reason to
insist on the difference: the hand-authored guess for the giant spoon was 60cm and the
model said 120.

**The estimator deliberately does not receive `real_length_cm`,** even though the v1.3
sidecar beside it carries one. Feeding it in would make mass partly a density calculation
off the other axis, so a length error would propagate and the two fields would stop being
independent evidence. The probe's fifth section exists to check that the axes actually did
come out independent rather than one tracking the other.

## P10 — the frozen hash chain is line-ending sensitive outside `.gitattributes`

*2026-08-09.* Found while establishing a baseline in a fresh worktree, not while looking
for it.

A fresh clone on Windows with `core.autocrlf=true` fails
`tests/test_motion_grammar_generalization.gd` (3 of 4, and the suite runs one test fewer)
and 47 of the Python offline tests, for no reason connected to the code. `.gitattributes`
pins `-text` on `data/combat_feel/live_assets/**`, but several SHA-256-pinned files live
*outside* that tree — `motion_grammar_generalization_v1`'s affordance profiles resolve to
`tools/semantic/reports/...`, and `wooden_chair_generalization` pins
`tools/comfyui/reports/spike_scores.csv`. Those get CRLF on checkout, so their digests
stop matching and evidence verification fails closed exactly as designed, on a defect that
does not exist.

**The pins are not even consistent with each other.** The report JSONs under
`tools/semantic/reports/` were hashed as LF; `spike_scores.csv` was hashed as CRLF. So no
single global setting satisfies the whole chain — normalizing everything to LF fixes the
Python suite and breaks the CSV, which is how the split was found.

**Why this is worth a decision entry rather than a fix.** It is T58 in mirror image: there
the tests were green while the thing was broken, here they are red while the thing is
fine, and both cost the same thing — the tests stop being believed. Anyone establishing a
baseline in a new worktree will otherwise attribute these failures to whatever they were
about to change. The durable fix is to extend `.gitattributes` to every hash-pinned path
and re-pin the CSV as LF; that edits frozen evidence, so it wants its own task and its own
review rather than being smuggled into an unrelated branch.
