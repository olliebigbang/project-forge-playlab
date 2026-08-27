# Ranged identity and mechanism v1

This slice accepts a firearm model name without asking the player how it should attack. The first acceptance set is:

- 中国95式步枪 / QBZ-95
- M4A1
- 81杠 / 81式自动步枪
- 92式手枪 / QSZ-92

## Authority boundary

The identity profile supplies a canonical identity, aliases, required visible parts and a complete AI-owned declaration. Runtime code never branches on a firearm model name.

The declaration is split into two groups:

- Structural axes: platform, layout, stock, feed position, magazine shape, barrel length, upper profile and support mode.
- Mechanism axes: fire control, cadence, recoil, accuracy, reload, effective range, handling and magazine capacity.

The same declaration drives the 96 px structural scaffold, anchor placement, visual-generation brief and compiled runtime matrix. The player confirms only whether the generated picture still represents the named object.

## Runtime behavior

The compiler converts categorical axes into clamped game parameters: automatic versus semi-automatic input, shot interval, recoil displacement, projectile spread and travel, movement multiplier, magazine size and automatic reload time. Muzzle flash, weapon recoil and reload lowering are visible; projectile origin follows the declared muzzle anchor.

## Vehicle boundary

`weapon_domain` is the routing boundary for future identities such as tanks. Version 1 accepts only `handheld_firearm`. An armored vehicle must use a separate actor compiler with chassis movement, turret rotation and mounted-weapon axes; it must not enter the hand-held weapon renderer or arena path.
