# Forge semantic v1.2.1 candidate — contract clarification

Continue to follow the frozen v1.1 prompt and the v1.2 affordance addendum.

- A canonical identity names the conventional base object, without added
  fantasy or combat effects.
- An effect-shaped English word is not an effect modifier when it is an
  inseparable part of the object's conventional base name. Do not remove or
  paraphrase such a word merely to satisfy the modifier rule.
- Do not add fields that are absent from the supplied closed tool Schema.
- `body_grip` means the hand directly holds the object's body and therefore
  requires `handle_length=none`. If the hand holds a real handle, use a handle
  topology and classify that handle's length.

These rules classify semantic data only. Do not emit motion primitives, combo
recipes, tuning values, object-specific code, or runtime mappings.
