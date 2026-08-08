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
recovers it. It is currently a hard-coded four-object table in `process_sprite.py` as a
proof of concept; sourcing it from the semantic contract is a separate task, deliberately
not done here.

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
