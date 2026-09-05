# GothicVania Church source

- Artist: Luis Zuno / Ansimuz.
- Pack: GothicVania Church Pack, https://ansimuz.itch.io/gothicvania-church-pack
- Input: user-supplied `gothicvania church files.zip`, received 2026-08-30.
- ZIP SHA-256: `EFC6CE035F57158055DFF8C0E37A893A61290C9BAF72B40B825D4D0D130313A4`.
- License: included `public-license.pdf`, page 1 explicitly states CC0, personal/commercial use, modification and redistribution permitted. The original PDF is preserved here.
- No purchase or online AI generation was performed for this integration.

PNG files are byte-for-byte copies, renamed only:

| Local file | Path inside `gothicvania church files` |
|---|---|
| church_backgrounds.png | Assets/ENVIRONMENT/backgrounds.png |
| church_column.png | Assets/ENVIRONMENT/column.png |
| church_tileset.png | Assets/ENVIRONMENT/tileset.png |
| player_idle.png | Assets/SPRITES/player/Idle/spritesheet.png |
| player_walk.png | Assets/SPRITES/player/Walk/spritesheet.png |
| player_hurt.png | Assets/SPRITES/player/Hurt/spritesheet.png |
| wizard_idle.png | Assets/SPRITES/wizard/Idle/spritesheet.png |
| wizard_fire.png | Assets/SPRITES/wizard/Fire/spritesheet.png |
| ghoul_run.png | Assets/SPRITES/burning-ghoul/run 1/spritesheet.png |
| ghoul_rush.png | Assets/SPRITES/burning-ghoul/run 2/spritesheet.png |

The presentation adapter composes the modules, draws a quiet stone floor using
the pack palette, and samples spritesheet regions at integer 2x with nearest
filtering. The hero uses a stable upper-body walk frame and animated lower-body
regions so the production weapon anchors remain connected. Dynamic bare arms
use the source palette. Enemy casting frames follow the actual attack phases.
This is not a new asset pack or a claim that every original animation is used.

Weapon art remains the user's previously generated offline cache: it is not
authored by Ansimuz. This separation must remain visible in project documentation.
