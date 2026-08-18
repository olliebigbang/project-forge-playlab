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
a chicken leg and a sledgehammer are both `front`, more than fortyfold apart. Refining the ordinal could
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
only by selecting one of three tempo classes, so across a 41.7x mass span the base damage
takes exactly three values. `verify_mass_ab.gd` prints that ratio on every run: if anyone
ever multiplies damage by kilograms, the third section stops showing three values and
starts tracking the masses. What the chicken leg gets for being light is 0.39s swings, 0.82
movement and 56.4 DPS against the pan's 0.54s, 0.62 and 50.0 — faster, more mobile, and
better sustained damage in exchange for less per hit. Light is a different weapon, not a
worse one.

**The estimator deliberately does not receive `real_length_cm`,** even though the v1.3
sidecar beside it carries one. Feeding it in would make mass partly a density calculation
off the other axis, so a length error would propagate and the two fields would stop being
independent evidence. Measured over the 17 objects asked on both axes, 41% of pairs rank
differently — the fishing rod is the longest object and the third lightest, the fire
extinguisher is mid-length and the heaviest. Mass is not a second reading of length.

**The control pair was wrong on the first run, and it failed in the direction that flatters.**
`iron_bar` was written to be the same length as the plain wooden spoon, but the estimator is
deliberately not given `real_length_cm`, and the case text never said how long the bar was.
The model priced a bar of its own choosing at 6kg and the pair reported 100x — a number that
would have been quoted as proving material sensitivity while actually comparing a 30cm spoon
to a metre of steel. With the size stated in `silhouette_hints`, where P06 established that
size language belongs, the bar comes back at 1.2kg and the pair reads a controlled 20x. **A
control that is not controlled still produces a number, and the number is more impressive
than the honest one.**

**The repeat-spread check fails, and loosening it would be the wrong move.** Measured over
18 objects x 3 repeats: ordering has no violations, both control pairs separate cleanly
(20x material, 25x modifier), every median lands inside its reference band. But two objects
exceed the 20% spread threshold inherited from P06 — the fishing rod at 40% (0.20–0.30kg)
and the chicken leg at 25% (0.12–0.15kg) — so the probe's verdict line reads NOT REPEATABLE.

Both failures are at the light end, and the cause is that the model answers round numbers:
at 0.25kg the neighbouring round answers are 20–40% apart, while the same absolute wobble at
3kg is a rounding error. **Relative spread is the wrong statistic for a quantity that is
consumed through a logarithm.** Measured on the axis that actually drives tempo, the worst
movement across repeats is +0.066 on a band of 0.65, no object's `weight_class` changes, and
the chicken leg's 25% compresses to exactly 0.000 because 0.12 and 0.15 both sit at or below
the axis floor. The curve is flattest precisely where the estimates are noisiest.

The threshold was deliberately **not** raised to make the line go green. P06's own warning
applies — tuning the expectation to the answer makes the check worthless — and a probe that
measures the raw field is still measuring the right thing about the model. What changed is
the interpretation, recorded here: this field is reliable enough to drive tempo despite
failing a criterion written for a linearly-consumed quantity. Anyone who later feeds
`real_mass_kg` into something *without* a compression curve inherits the 40% honestly, and
should re-read this paragraph before assuming the axis is stable for their use.

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

## P11 — mass and length stay two axes; do not multiply them into an inertia proxy

*2026-08-10.* Proposed in this repo's own review line and refuted by measuring it. A
parallel review of the 1B design asked for a `rotational_inertia_proxy`, and P09's real
kilograms appeared to make one free: `real_mass_kg * (real_length_cm/100)^2` needs no new
contract field. It is the worst of the four available options. Evidence:
`tools/combat_feel/compare_axis_separability.py`.

**The case for it was strong on every count except the one that decides.** It separates the
frying pan from the chicken leg 220x where the categorical fields separated them not at
all; it spans 4773x across the seventeen probed objects; it really is a new ordering
(Spearman 0.715 against mass, 0.750 against length); and squaring the length does not
amplify the noise, because length is the stable estimate — worst repeat spread 5.6% against
mass's 40%, so the product comes out no worse than mass alone.

**It loses on resolution, which is the only thing an axis is for.** Counting pairs closer
together than 0.065 — P09's measured worst repeat-driven axis movement, so anything closer
sits inside the estimator's own noise and cannot be a reliable distinction:

  scheme                              indistinguishable pairs
  inertia m*L^2 alone                      39/136    29%
  length alone                             25/136    18%
  mass alone                               21/136    15%
  mass and length kept separate             7/136     5%

**The product is a dimensionality reduction wearing multiplication's clothes.** Mass and
length already rank objects almost independently — Spearman 0.237 between them — and that
independence is the entire asset. Collapsing the pair into one scalar spends it: eight of
seventeen objects pile into the 0.85–0.95 stretch of the inertia axis (axe, extinguisher,
giant spoon, mop, shield, shotgun, sword, chair). Two axes became one. That is T51 and
T76's addition failure in a costume with the word "multiply" printed on it, and it fooled
the author of P09, who had been citing T51 all week.

**A wider raw span is not a better axis.** Compressed into a fixed band, a wider span buys
sharper ends and a flatter middle, because each unit of band then covers more ratio. m*L^2
is crisp at the extremes and mush exactly where nearly every hand weapon lives. P07 found
length informative in the middle and inert at the ends; this is the same trade run
backwards, and it is a property of compressing any wide span into a fixed range.

**The failing case never needed it.** Mass alone already separates pan from chicken leg
18.3x, and the compiler already converts that into a tempo class flip rather than a
percentage (P09). The search for a cleverer combination was solving a solved problem —
worth noticing as a habit, because the arithmetic looked impressive enough to skip asking
whether anything was still broken.

**What the residual collisions say about where to go next.** The seven pairs the two-axis
scheme cannot split are objects that genuinely are alike in both size and weight: cleaver
and hammer (0.007 apart on the axis), giant spoon and sword, shield and chair, giant spoon
and mop. No arrangement of kilograms and centimetres will separate those, because they do
not differ in kilograms or centimetres. They differ in what they are made of and how they
land — contact surface, compliance, impact sound. That is a different *kind* of axis, and
these numbers are the argument for building it next rather than refining this one.

**The geometric version of the same idea is worse, not better.** The parallel review
proposed deriving the inertia proxy from the sprite. That meets T60 head-on — ink area
saturates — and the review says so about this very case: pan and chicken leg are both 96px,
both front-weighted, both short, so a geometric proxy returns nearly the same number for
both. From pixels the quantity is not merely redundant, it is unavailable.

## P12 — the selection layer is a four-way choice, and that is not a tuning bug

*2026-08-10.* Measured after two separate lines of reasoning independently blamed
`contact_surface` for dominating primitive selection. It does dominate. Rebalancing it is
still the wrong move. Evidence: `tools/combat_feel/measure_selection_sensitivity.gd`.

**The measurement asks a narrower question than the existing audit.**
`export_affordance_axis_causality.gd` asks whether varying an axis changes anything in the
compiled profile, and nearly everything answers yes, because nearly every axis feeds some
multiplier. That is why twelve causality cases could pass while a pan and a chicken leg
compiled to the same three swings. The question T77 actually turns on is whether an axis
can change *which motions you swing*, so this sweeps one field at a time from three real
baselines and records the resulting family triple.

**Result: of 42 (baseline, axis) pairs, 9 can move the selection.** `contact_surface` is
the only axis that moves it from every baseline, and it reaches all four combos every time.
From the frying pan it is the only axis of fourteen that moves it at all. `has_point`,
`has_edge`, `has_broad_face` and `has_barrel` never move it from any baseline despite
carrying 0.75–0.90 in the scoring table, and neither do `real_mass_kg` or `real_length_cm`
— an honest bound on P09 and P05, which reach the parameter layer only.

**Why the A-B-A combo cannot be fixed by raising the de-duplication penalty.** Real scores
for the pan: `bash 5.80, slam 4.75, sweep 1.10, thrust 0.70, spin 0.00`. At hit_3 both used
families take −3.00, leaving `bash 3.70, slam 2.95, sweep 1.30, spin 1.00`. Bash wins its
own third appearance by 0.75 because its base is 1.05 higher, and the first unused option
trails by 2.40. The penalty would have to exceed −5.5 to surface a third motion, at which
point it outweighs the combined contribution of most axes.

**Decided: do not rebalance the contact weights.** The selection layer asks one question —
how does this object deliver damage — and `contact_surface` is literally the answer to it.
A point thrusts, a broad face bashes. Flattening its weight does not make selection richer,
it makes it arbitrary, and it would break the property that the same affordance always
compiles to the same recipe. The other axes are not being suppressed; they are answering a
different question and were never candidates to decide this one.

**What this costs, stated as arithmetic.** Selection has four reachable outcomes, one per
`contact_surface` value. Tempo has three. Everything else is a multiplier in a 12–16% band,
all pushing the same direction (P09). So the perceptible space is about 4 × 3, with several
combinations unreachable — which is "ten weapons, three feels" (T77) reduced to its
factors. The expressive ceiling was never limited by how many axes the contract carries; it
is limited by how many *categorical* outcomes exist downstream of them.

**So density has to come from a new categorical layer, not from more inputs to this one.**
Three separate findings now point at the same place: P11's seven residual collisions are
all objects alike in size and weight and different in material; `tempo` currently owns
timing, damage, hitstop, knockback, camera shake *and* sound profile, so every impact
channel is keyed to one three-valued enum; and the axes that fail to reach selection fail
because selection is already answered. Giving a material or contact-resolution axis its own
channels — sound and hitstop and rebound direction, taken from tempo rather than added
alongside it — multiplies where adding a fifth scalar does not.

## P13 — test an impact axis inside collision groups, not on its marginal distribution

*2026-08-18.* Measured while running the 1B spec's M1 gate, which requires theta to be
measured before anything is implemented and asks whether the three contact_resolution
classes are supportable. Theta measured fine: 0.538, the midpoint of the widest gap between
adjacent rigid objects on the mass axis, 0.188 of margin against P09's 0.065 noise floor.
The frying pan and the chicken leg land on different resolutions seven noise floors apart.
Evidence: `tools/combat_feel/measure_contact_resolution.py`,
`measure_rigidity_coverage.py`, `measure_within_collision_split.py`.

**This decision was drafted twice with the wrong test and is recorded so nobody repeats
it.** The first draft counted how often `rigidity` returns each value across every profile
in the repository — 28 rigid, 6 semi_rigid, 2 flexible, 78% one value, the same shape in
all three independent groups — and concluded the field was too constant to carry a
categorical impact layer, the way P09 found `mass_distribution` "not merely coarse, it was
constant".

**That is the marginal distribution, and an impact axis is never asked to do marginal
work.** It never has to tell apart two objects that already swing differently, because P12
showed `contact_surface` reaches selection from every baseline and those objects are
separated upstream. The only thing an impact axis must separate is objects that compile to
the same primitive sequence. That is a conditional question, and it gives a different
answer.

**Measured on the twelve v1.2.1 handoff cases, which carry identity, affordance axes and
compiled sequence in one row.** Twelve objects reach seven distinct sequences. Four
sequences are reached by one object and need nothing. Three groups collide:

  sequence                 members                                    rigidity splits
  bash -> slam -> bash     baseball bat, giant chicken leg, stool     yes
  sweep -> spin -> slam    wooden chair, fire extinguisher, rod       yes
  sweep -> thrust -> slam  longsword, fire axe                        no

Two of three groups, and four of the seven colliding pairs. The two it splits are exactly
the shapes the axis was proposed for: a giant chicken leg pulled out of a baseball bat and
a folding stool, and a flexible fishing rod pulled out of a rigid chair and a rigid
extinguisher. A field that is 83% constant still did that, because the objects it
distinguishes are the ones sharing a swing.

**What it does not resolve, stated plainly.** Three colliding pairs survive rigidity, all
of them same-value pairs: longsword and fire axe, bat and stool, chair and extinguisher.
Those need the mass split theta provides, or something not yet in the contract. So
`rigidity` is a sparse signal — it fires rarely and correctly — and cannot be the whole
input. The spec's derivation stands with its expectation corrected: `follow_through` being
a small class is not the defect the first draft called it, but neither is rigidity alone
enough, and the axis carries less than the spec assumed.

**One shipped fixture would break the motivating case.** `artifacts/mass_axis_poc/`'s
chicken leg records `rigidity: rigid`. That profile is hand-authored —
`author_v1_4_sidecars.py` says beside it that only the mass is model output and "the
profile around it is still hand-authored". Asked the same object, the model answered
`semi_rigid` and showed its work: "bulbous meat mass at striking end", "semi-rigid meat and
bone structure". Under the hand-authored value the chicken leg stays in the rigid branch
with the bat and the stool, which is precisely the collision 1B exists to break. The
fixture should be replaced with model output before it is used to judge anything.

**A premise correction that came out of the same run.** P11 closed by naming three residual
collisions as this axis's reason to exist — cleaver and hammer, giant spoon and sword,
shield and chair. The handoff matrix carries identities, so these can be checked rather
than inferred: cleaver compiles to `sweep -> bash -> slam` and hammer to
`bash -> slam -> sweep`; shield to `bash -> sweep -> slam` and chair to
`sweep -> spin -> slam`. They collide on the mass-length plane, which is what P11 was
measuring, and not in compiled output. P11's own sentence lists "contact surface" first
among what those pairs differ in, and that part was already built. The real collision list
is the three groups above, and it is not the same list.

**A second finding, about coverage rather than design.** Of the eighteen objects in the
mass probe, twelve have no drawing — no sprite, no blueprint, nothing under `data/`. Their
affordance profiles cannot be obtained by running the estimator, because T74's subject is
the drawing. Closing that gap means generating assets, which is a larger decision than 1B.

**Decided: the derivation is not refuted, its input is incomplete.** The channel-transfer
half of the spec — taking hitstop, knockback, camera shake and sound off tempo — is
untouched by any of this. 1B proceeds on rigidity plus the mass split, with three known
unresolved pairs recorded rather than papered over, and with the chicken leg fixture fixed
first.
