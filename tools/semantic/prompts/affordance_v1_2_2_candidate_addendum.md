# Forge semantic v1.2.2 candidate — grip invariance correction

Continue to follow the frozen v1.1 prompt and the v1.2 and v1.2.1 affordance
addenda.

- Classify the preserved object's physical grip before classifying combat
  behavior. Combat verbs, effects, damage, and player intent must not change
  the object's physical grip topology or handle length.
- The only legal handleless pairs are `handle_length=none` with `body_grip` or
  `clamp_grip`.
- The only legal handled pairs use `handle_length=short|medium|long` with
  `one_hand_handle`, `two_hand_handle`, or `clamp_grip`.
- Never combine `body_grip` with a non-`none` handle length.

These rules classify semantic data only. Do not emit motion primitives, combo
recipes, tuning values, object-specific code, or runtime mappings.
