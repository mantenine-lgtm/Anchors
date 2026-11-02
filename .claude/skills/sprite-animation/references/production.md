# Sprite Production Methodology

This reference is general-purpose. Asset-specific motions, role names, thresholds, camera constants, and rebuild commands belong in project profiles.

Detailed, self-contained method guides: [raster sources](raster-sources.md) and [rigged sources](rigged-to-sprites.md). [Delivered examples](dead-zone.md) are optional visual evidence, not a dependency on another repository.

## The Method Must Fit the Motion

Before choosing tools, identify the sequence's hardest requirements: perspective changes, occluded surfaces, attachment relationships, articulation, shape changes, and identity consistency. A rig that works for a quiet cycle may fail when the silhouette changes substantially. A beautiful one-shot sheet may fail as a sequential animation.

Use separately authored frames for substantial shape/perspective changes when consistent painting can be controlled. Use segmented 2D articulation for planar motion with complete overlapping parts. Use properly rigged 3D and sprite baking when stable depth, many facings, and repeatable constraints justify modeling effort. Hybrid methods must prove appearance and motion together. Preserve approved work during comparisons; change one meaningful variable per experiment.

## Source Preparation

- Reference the actual approved appearance, not only a verbal style label. Describe camera, lighting, broad readable material/color groups, and intended display size.
- Assign distinct roles to references: identity/style versus pose/motion. Inspect generated outputs before trusting grids, source order, or repeated-part identity.
- For sequences, keep palette, scale, proportions, lighting and equipment stable. Preserve raw output before any one-time calibration. Material-specific calibration can reduce drift but cannot fix bad poses.
- For segmented art, include hidden joint surfaces and identify each part, pivot, attachment and depth order explicitly. Do not cut invisible anatomy out of a flattened painting or infer a hand joint from a prop's bounding box.
- For models, inspect topology, weights, joint limits, attachments and silhouettes in several directions. Fix the orthographic camera, world light and render scale. A crudely shaped or shaded model does not demonstrate the quality ceiling of 3D sprite production.

## Motion Design

Specify meaningful key poses and their timing before adding intermediate frames. Identify contact, emphasis, holds, transitions, and recovery where appropriate to the subject. A sequence's readability depends on pose progression and timing, not its number of unique images.

Use subject-local coordinates for articulation and spatial constraints, then project into each facing. Screen-left/right heuristics and horizontal motion components do not reliably represent anatomical ownership, elevation or depth. Preserve part identity when moving between states. Avoid copying one asymmetrical component to both sides merely to remove an attached object.

For rigs, validate actual emitted part selection and transformed geometry. Appropriate joint ranges, smooth reach limits and attachment constraints reduce discontinuities. Fixed lengths do not prove correct anatomy. Different camera views may require projected foreshortening, alternate paintings or actual 3D geometry rather than forcing the same picture-plane solver everywhere.

For retargeted animation, capture immutable source/target rest transforms before playback. Compute offsets from those records, never from the last evaluated pose. Preserve intended target proportions and distinguish root travel from pivot motion. Review wrist orientation and contact surfaces as well as endpoint distance: a hand can reach the correct coordinate while visibly failing to hold an attached object.

For held props, choose the animated parent frame before solving limb contacts. Fixed world-space targets can make limbs cancel the body's motion and leave the prop visibly suspended. Define grip/contact landmarks in prop space and the matching palm/contact offsets in limb space; derive joint targets from those offsets and orientations, not by snapping the wrist origin onto the grip. Check the full cycle's reachable envelope. An isolated prop render can verify actual attachment motion and loop continuity without confusing it with movement elsewhere in the subject.

When a sequence frees the hands, attach retained equipment to its intended storage frame instead of leaving it parented to a working limb or hiding it. Inspect both visible and naturally occluded views throughout the motion. Verify that the attachment follows the parent while the accepted working motion remains unchanged; a stowed pose does not itself supply a transition into or out of storage.

Correct endpoint contact does not establish clearance along the rest of a limb. Inspect intermediate joints and skinned surfaces against the body and attachments in multiple views. Adjusting a bend plane can improve separation without moving an approved contact point or changing the opposite limb; verify those invariants in the emitted poses and images. Constrained limbs can still inherit inappropriate roll/twist from an unconstrained source clip. When that causes overlap, inspect the proximal joint and contact orientation, and author a suitable rest-relative limb orientation rather than only moving the elbow. Protect accepted sequences with decoded-frame comparisons. A posed-source vertex/envelope audit can catch penetration that joint tests miss; record its exclusions and limitations, fingerprint its inputs, and still review rendered silhouettes.

For painted sequences, compare complete key-pose progression before generating more frames. Reject identity drift, repeated incorrect shapes, wrong camera angles or inconsistent structure. More FPS, filtering and registration cannot make a wrong sequence correct.

## Expanding an Accepted Rig

Use this route when the brief and an inspected pilot support rigged-source production; it is not a mandate for every visual style.

1. Freeze the accepted source, clips, attachments and rendered frames with fingerprints. Start from the working baker, not a new approximation of the accepted appearance. Retain source/license provenance and exact dependency versions.
2. Build a subject matrix of silhouette/material changes, equipment, required sequences and views. Separate identity configuration from motion. Choose an authored clip appropriate to each subject; inspect its existing posture and weight before adding lean, constraints or proportions. Extra template corrections can compound a crouch or reverse an otherwise good pose.
3. Reset from immutable rest records for each evaluated pose. Attach props to an animated parent, then solve local palm/contact orientation and reach. Bind tools to the limb that actually performs the source motion. Inspect skinned clearance, not only joint endpoints; keep unconstrained motion intact when equipment is stowed.
4. Bake one new representative subject at a time and stop on a failed visual gate. Review complete complementary phase grids and normal/slow playback in every delivered view. Inspect foot lanes, limb ownership, proportions, weight/contact, overlap, prop continuity and identity markers in front/rear views. Fix the affected subject/sequence, then prove accepted neighbors are unchanged before expanding further.
5. Keep camera, world lighting, material groups and body density deterministic. Measure one full-sequence envelope per subject with padding and a stable projected pivot; never independently crop/recenter poses. Render sufficient source detail and test filtered reduction at actual display sizes when the style warrants it.
6. Package through the existing renderer and test the served workflow, not only the source rig. Retain old assets and simulation during comparisons. Record visual outcomes separately from decoded bounds, frame coverage, attachment/skin regressions and runtime checks. Do not mark an uninspected combination as passed or call same-agent inspection independent review.

For a display-size-only request, change presentation metadata around the existing anchor instead of modifying model proportions, source density, motion or timing. Make repeated/partial builds idempotent so enlargement cannot compound. Verify rendered destination dimensions, hit regions and overlays as well as unchanged source frames. These are separate concerns from gameplay collision size.

## Alignment and Timing

Register frames using a meaningful object pivot, contact point or stable anatomical landmark. Alpha bounds change as limbs or props move; centering each bounding box creates false motion. Normalize scale once and translate for registration without erasing intentional bob, lean or travel.

Calibrate directional labels against actual engine movement in every delivered direction. Camera handedness, model forward axes and bake rotation order can disagree even when a metadata-only test passes. Preserve already-correct views; distinguish a reversed turn order from a half-turn. Make any label permutation explicit and idempotent across fresh and partial builds, without mirroring accepted artwork. Test real movement commands against independently defined expected views.

A ground-plane pivot for a long object is not necessarily its lowest opaque pixel. Inspect its contact footprint, wheels/feet, shadow and selection outline together in each facing. Correct presentation anchors without silently moving gameplay collision bounds.

Loop samples normally exclude a duplicate end frame; non-looping actions may require a final recovery endpoint. Adjust FPS deliberately when changing frame count so cycle duration remains intentional. Inspect adjacent frames and last-to-first transitions. For rigged cycles, check continuity around constraint limits as well as at the seam.

## Resolution and Sampling

Record source-body pixels, atlas-body pixels and displayed CSS body pixels separately; cell size includes padding. Estimate useful source detail against display size, supported zoom and device-pixel ratio. Enlarging an already reduced texture or preview cannot restore detail.

Minimize reductions between source, intermediate raster, atlas and runtime. Preserve logical scale and proportional anchors when changing source density. Measure the full motion envelope before trimming padding. Use per-asset cell sizes when the engine supports them; large unused cells increase decode memory without increasing useful detail.

Test sampling on actual displayed frames. Deliberate pixel art may require nearest sampling; shaded illustrated art may benefit from filtered reduction. Compare identical frames at native size and supported zoom/DPR, with a physical-pixel backing canvas. Avoid accidental CSS resampling, ghosted frame crossfades, or blurring as a substitute for coherent edges and motion.

For static assets with larger original artwork, copy native source pixels instead of upscaling a reduced export; preserve logical dimensions and proportional pivots. A denser terrain silhouette need not add texture detail or colors. Validate decoded alpha, palette and hit masks through the actual renderer.

## Runtime and Review Performance

Measure the actual served scene before reducing animation quality. Distinguish source-clip FPS, displayed frame cadence, JavaScript work and Canvas/compositor cost. Repeated static-layer drawing, offscreen scenery and canvas reallocation can dominate even when sprite selection is cheap. Reuse stable backing canvases, draw only visible panels/actors with complete sprite bounds, and stop preview updates while paused or hidden. Static contact strips do not need an animation loop.

If caching static terrain or scenery, invalidate for every state that affects it: camera, zoom, viewport pixel density, active assets, tile data and fog/visibility. Verify cached and direct pixels, not just cache-hit counters. Keep simulation updates independent of visual culling. Wait for the selected complete decoded pack before first review playback to avoid fallback-art flashes; load legacy pilot assets only when explicitly requested. Delayed-network startup and offscreen/paused checks belong in runtime QA.

Report benchmark conditions and limits: crowded content, viewport/DPR, cold versus warmed uploads and paused-render versus active-simulation samples. Do not run competing browsers during a measurement or generalize a short local result into a guaranteed frame rate on every device.

## A Real Acceptance Gate

Define observable visual requirements for the intended sequence before production. Review each delivered action/view against those requirements; leave unknown or failing combinations visible in the evidence record. Require the correct structure and pose progression, not merely a nonblank frame.

Separate four kinds of evidence:

1. **Source quality:** structure, identity, palette, camera, materials, alpha and complete surfaces.
2. **Motion quality:** readable progression, timing, articulation, attachment continuity and stable intended pivots.
3. **Packaging correctness:** decoded bounds, clipping, anchors, resolution, frame order and durations.
4. **Runtime correctness:** actual renderer behavior, sampling, scale, state transitions, supported viewports and integration regressions.

Review full native/enlarged playback, normal/slow speed, stepping, important transitions and loop seams. A contact sheet is useful evidence, not a completed judgment. Use a separate critical pass on raw rendered images; do not feed it the creator's assurance that the result passed. Only claim independent review when it was genuinely independent and available. Aesthetic approval cannot be automated by pixel counts or by comparing generated metadata to itself.

Prototype the hardest representative sequence before expanding the roster. Repeated structural rejection should trigger a method change or a better source, rather than larger parameter changes across all assets. Keep known failures out of the installed result. Internal iterations should catch defects before asking the user to judge artistic choices; first-pass perfection is not a guarantee.

## Evidence Record

Keep a compact record with the produced asset:

```text
Brief and approved appearance:
Method/tool/model and exact references/prompts:
Source size, display size, camera and palette:
Frame rectangles, pivot, timing and direction order:
Visual requirements and observed outcomes:
Technical/runtime verification:
Rejected candidates, gaps and approval scope:
Next decision:
```

Promote only supported, reusable conclusions into the skill. Keep game-specific contracts and numerical settings in project references, and keep untested ideas labeled as proposals.
