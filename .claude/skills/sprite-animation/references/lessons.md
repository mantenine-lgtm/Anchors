# Lessons From Sprite Production

These observations came from producing and refining the Dead Zone sprites. They inform the general method; they are not universal numerical settings. The delivered outcome is included in [the example profile](dead-zone.md). Earlier chronological logs remain in Git history, not required reading.

## Appearance Is Not Animation Approval

Reference-guided image generation produced richer shading and material definition than code-authored imitations of the same illustrated style. However, generated sheets repeatedly supplied the same leading leg, incorrect directions, uneven spacing, changing identity, and inconsistent color. Equal-cell cropping clipped equipment. Inspect actual separated silhouettes, source poses, and alpha before assigning cells. A good-looking still does not establish a coherent cycle.

## Correct Sources Before Binding Them

Flat-image deformation stretched knees and pulled unrelated pixels into arms. Cutout rigs also failed when sources lacked hidden joint surfaces, painted front legs were actually side views, or near/far arms were assigned to the wrong shoulders. More frames, smooth IK, and filtering could not repair those source/ownership mistakes. Use complete components or an appropriate skinned model when the motion needs surfaces the source does not contain.

## Alignment and Color Are Separate Repairs

Stable landmark registration greatly reduced frame jumping; per-material palette calibration reduced brightness shifts. Neither fixed a repeated crouch or an incorrect gait. Register against a meaningful pivot, not changing alpha bounds. Keep raw sources and an A/B comparison; do not normalize away intentional lighting or motion.

## A Promising Cycle Does Not Validate a Roster

A layered walk with rigid segments, periodic contact paths, restrained bob, and explicit filtering was well received in a limited pilot. Expanding generic bindings to every role produced crossed legs, wrong proportions, and disjointed arms. Inspect new source anatomy, equipment, actions, and every facing individually. Preserve still-approved clips exactly while repairing affected combinations.

## The Accepted Rigged Method

The eventual accepted roster reused a licensed artist-made skinned model and authored clips, with immutable-rest retargeting and transparent PNG baking. Role colors, gear, posture, proportions, and cadence were separate from the motion implementation. This improved repeatable articulation and depth; it did not exactly reproduce every earlier painted concept or guarantee that another model/style will succeed.

## Reset Before Every Pose

Retarget offsets derived from an already animated pose contaminated subsequent sequences. Capture rest transforms before playing clips, stop/reset the mixer, restore those transforms, then evaluate each sample independently. Keep root travel separate from in-place sprite motion. The algorithm is included in [rigged-to-sprites.md](rigged-to-sprites.md).

## Attach Props to Moving Frames

Fixed world-space wrist targets made a carried gun appear suspended while the body moved. Moving the prop with the torso, then deriving wrist position and orientation from prop-local grips and hand-local palm offsets, fixed the relationship. Hands-free sequences used a torso-relative back attachment without constraining the working hands. A stored pose is not an authored equip/stow transition.

## Contacts Do Not Prove Clearance

Correct palm endpoints still allowed the support sleeve to intersect the torso. Walking-specific wrist/upper-arm orientation and a better bend plane improved clearance while preserving the opposite arm and prop. Replaying emitted poses onto actual skinned vertices caught an intermediate failure that joint tests missed. Hull/vertex tests have exclusions and are not a universal collision or aesthetic judge; still inspect rendered silhouettes.

## Inspect Authored Motion Before Adding Corrections

A crouched source already had the intended posture; additional template lean compounded it. A work tool initially followed the wrong hand. A broad upper-body strike also lifted legs that were meant to remain planted. Retain appropriate authored articulation, bind equipment to the actual working limb, and apply local corrections only where the intended motion requires them. Identity markers must remain exposed from front and rear.

## Preserve Useful Pixels and Stable Pivots

One measured full-sequence envelope with padding reduced excess atlas area without changing alignment. Per-frame trimming would have introduced false motion. Higher-resolution buildings and props were recovered from native originals rather than upscaled reduced exports. Display-only resizing changed metadata around the existing pivot, not source geometry or motion; repeat builds must not compound scale factors.

## Test the Actual Engine

The baker and game used opposite turn orders even though north/south looked correct. Actual movement orders, not metadata self-comparison, exposed the mismatch. Vehicle wheel contact required a ground-plane anchor, not the lowest opaque pixel. Runtime drawing cost came largely from repeated terrain and offscreen panels, so caching/culling improved playback without reducing animation quality. Delayed and warm-cache loading must be checked as well as clean-browser startup.

## QA Must Judge Emitted Motion

Nonblank frames, fixed bones, unique poses, and passing tests all coexisted with visibly bad animations. Review complete sequences in every view, at normal/slow speeds and native/enlarged sizes, including loop seams. Keep packaging, anatomy/motion, and served behavior as separate evidence. Same-agent inspection is not independent-model review. Record missing or rejected combinations instead of claiming first-pass perfection.
