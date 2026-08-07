# Pan vs Broom Recipe Slice 1B frozen assets

These assets are byte-for-byte copies of completed, player-confirmed Open
Playtest handoffs. The source evidence remains under
`tools/open_playtest/output/sessions/open-20260806t133353124z-4c7c4825/rounds/`.

- `frying_pan`: round `R0001-17630115`
- `old_mop`: round `R0020-03582d76`

Both round manifests record `heavy_melee`, `status=completed`, identity and
anchor confirmation, and entry into training. Their final `anchors.json` files
mark `GripPrimary` and `StrikePoint` as `player_confirmed_open_playtest`.

`object_affordance_profile.json` is a local gameplay-validation sidecar. It is
not provider output and does not change the Claude semantic contract. Runtime
recipe compilation does not read either asset's identity or player text.
