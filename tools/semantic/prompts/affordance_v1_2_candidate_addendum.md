# Forge semantic v1.2 candidate — affordance addendum

The `submit_forge_semantic_blueprint` tool in this bounded retest extends the
frozen v1.1 blueprint with one required `affordance` object. Fill it from the
physical structure of the preserved canonical object. Do not select motion
primitives, combo recipes, damage, or numerical combat tuning.

## Physical affordance fields

- `handle_length`: use `none` when the object is held by its body or clamped
  structure; otherwise classify the usable handle as `short`, `medium`, or
  `long` relative to the whole object.
- `body_length`: classify the main rigid or flexible body as `short`, `medium`,
  or `long` relative to a person holding it.
- `grip_topology`: use `one_hand_handle`, `two_hand_handle`, `body_grip`, or
  `clamp_grip` according to how the described whole object can actually be held.
- `rigidity`: classify the attack-bearing structure as `rigid`, `semi_rigid`,
  or `flexible`.
- `mass_distribution`: classify perceived mass relative to the primary grip as
  `rear`, `balanced`, or `front`.
- `contact_surface`: describe the primary physical contact mechanism as
  `point`, `edge`, `broad`, or `whole_body`.
- `secondary_contact_surface`: use `none` unless a distinct secondary end or
  surface can physically make contact; otherwise use the matching surface type.
- `has_point`, `has_edge`, and `has_broad_face` describe usable physical
  geometry, not visual decoration. The flag matching `contact_surface` must be
  true for point, edge, or broad contact.
- `has_barrel` and `has_stock` describe those literal structures only. Do not
  infer either merely because the object attacks.
- `confidence` rates only the physical-affordance classification. It must be
  between 0.65 and 1.0 for a compiled result.
- `evidence_parts` lists one to five concise English structural parts that
  justify the affordance classification. It must not contain a recipe,
  primitive name, gameplay number, object-specific code path, or provider data.

Affordance fields are independent axes, not a lookup table keyed by object
name. Objects with comparable physical structure should receive comparable
affordances even when their names differ. Preserve the v1.1 identity and combat
rules exactly; the added affordance must not rename the object or replace it
with a conventional weapon.
