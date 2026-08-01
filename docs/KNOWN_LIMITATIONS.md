# Known Limitations

- `CONFIRMED`: All interpretation and imagery are offline Mock implementations. No real semantic or image model is configured.
- `CONFIRMED`: Free descriptions map through a small multilingual keyword heuristic into exactly three supported families. Nuanced fantasy composition is not understood.
- `CONFIRMED`: Procedural sprites vary with family, palette, aspect ratio, and a small subset of sketch geometry; they do not trace the player drawing literally.
- `CONFIRMED`: Anchor resolution is profile-guided and local. Highly unusual silhouettes may need the included manual JSON override.
- `CONFIRMED`: The two-hand pose is a readable approximation, not full IK.
- `CONFIRMED`: Enemy behavior and room layouts are intentionally small and deterministic enough for a gameplay hypothesis, not production combat content.
- `CONFIRMED`: Touch is a basic Web-capable control layer, not a completed mobile release acceptance pass.
- `CONFIRMED`: Logs remain local and omit raw free text and sketch data, so qualitative analysis requires the moderator's separate notes.
- `ASSUMPTION`: System fallback fonts include Chinese glyphs on the playtest machine.
- `TO VALIDATE`: Players perceive the weapon visual and behavior as the same fantasy rather than two loosely related outputs.
- `TO VALIDATE`: Automatic anchors are believable across genuinely poor sketches.
- `TO VALIDATE`: A single modification is both understandable and materially noticeable in room two.

Manual anchor override is most likely for vertical sketches, extremely thin handles, or silhouettes whose visible mass is intentionally disconnected. The three fixed fixtures are designed to resolve without overrides.

