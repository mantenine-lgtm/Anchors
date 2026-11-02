# Dead Zone: Delivered Examples

This optional profile describes the accepted Rigged Tactics outcome, not instructions that require a separate game checkout. Five exact delivered atlases, their directional/action metadata, animated GIFs, and provenance are bundled under [examples/dead-zone](../examples/dead-zone/manifest.json).

## Included Characters

| Subject | README example | Source coverage |
| --- | --- | --- |
| Soldier | Southeast walk | Idle, walk, shoot, gather; eight views |
| Builder | Southeast walk | Idle, walk, attack, gather, repair; eight views |
| Walker | Southeast walk | Idle, walk, attack; eight views |
| Exploder | Southeast run, 17 FPS | Idle, locomotion, attack; eight views |
| White SUV | Eight-view turnaround | One static pose per direction; no wheel-animation clip |

The GIFs use the existing frames and recorded locomotion cadence, not a newly generated animation. The Exploder's source is `Jog_Fwd_Loop`; the game stores that running sequence under the `walk` clip name. The vehicle GIF steps through directional poses; it does not imply continuous physical turning. The examples are enlarged for inspection, not shown at the game's native pixel size.

## Production Method

The humanoids use a CC0 Quaternius skinned character and authored animation library, rendered to PNG sprites. The white SUV is a reference-guided, image-generated painted directional sheet retained from the preceding art pack. The image tool did not expose its model identity. Source/license notices and the SUV production prompt are retained in [provenance](../examples/dead-zone/PROVENANCE.md).

The accepted rig uses immutable-rest retargeting, torso-relative equipment, palm/grip contacts, and inspected sleeve clearance. Guns remain on the back during gathering. Gear follows the actual working hand; role posture and cadence are selected before adding corrections. Ordinary zombies use grey skin and lighter grey lower clothing; the Exploder has stable bright orange markers and a faster jogging gait.

The game consumes raster atlases through Canvas 2D. Three-dimensional models are production sources, not a runtime migration to a 3D game. The reusable workflow and algorithms are included in [rigged-to-sprites.md](rigged-to-sprites.md); no game source code is required to understand them.

## Example-Specific Settings

- Eight genuine model rotations; direction labels calibrated against actual screen-space travel.
- Sixteen authored samples per humanoid locomotion cycle. The included manifest is authoritative for each clip's cadence, dimensions, and pivot.
- Orthographic camera elevation 30 degrees; fixed lighting and 4x supersampling before filtered reduction.
- Humanoid atlas body density 96 pixels. One padded envelope per actor; no per-frame recentering.
- Native humanoid body presentation approximately 25.5 CSS pixels at game zoom 1. The SUV has separately approved larger presentation.
- Selection, shadow, and collision bounds are separate concerns; source images and motion are unaffected by later display/shadow tweaks.

These are demonstrated settings for this outcome, not defaults for every style. Artwork, motion, and user approval remain distinct. The delivered roster received positive user feedback; this does not approve future changes or guarantee an exact match to every earlier concept. Review was performed by the same agent, not an independent model. Equip/stow transition clips were not authored.

## Reproduce the Bundled Previews

From the skill checkout, run `npm ci`, then `npm run examples:render`. This uses only the bundled sheets and metadata, a Chromium browser, and FFmpeg. See the root README for browser-path overrides. It does not rebuild models, regenerate artwork, run the game, or change any game save.

For manual frame inspection, run the bundled inspection helper against `examples/dead-zone/sheets/soldier.png` with `--frames examples/dead-zone/soldier-walk.json`. This works without access to the original project.
