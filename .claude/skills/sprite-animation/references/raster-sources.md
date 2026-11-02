# Reference-Guided Raster Sources

This guide contains the image-production guidance used by the skill. A separate image-generation skill is not required. Use the actual available tool interface; if none exists, request source artwork or use supplied/licensed assets instead of pretending generation occurred.

## Brief and Tool Use

1. Inspect the approved reference and record the intended camera, identity, medium, palette, light direction, anatomical proportions, and displayed size. Assign each reference a role: appearance, pose, or layout. Avoid asking a style reference to supply unverified motion.
2. For edits, inspect the input first and include that exact image through the tool's supported reference mechanism. Preserve transparency unless the brief changes it. For a new source, request real alpha explicitly when the engine needs it. A painted checkerboard or faint studio matte is not transparency.
3. State the practical resolution target in useful body/object pixels, separately from cell dimensions and runtime size. Include full motion/equipment extents and generous gutters. Do not use tiny generated preview art as the high-resolution production master.
4. Prefer the already available/included tool. Do not silently buy credits, use a separately billed API, or claim a model identity that the tool did not expose. Save prompts, references, original output, actual dimensions, and cleanup decisions.

## Prompt Template

```text
Use reference 1 for identity and visual medium; use reference 2 only for pose/camera.
Subject: [literal character/object and recognizable identity features].
Medium/palette/light: [specific visible material families and lighting].
Camera: [projection, elevation, facing, front/back landmarks].
Pose: [anatomical ownership, contact, equipment, visible action phase].
Resolution: [useful body/object pixels and intended display size].
Output: [single isolated source or explicit spacious layout], real transparent alpha,
complete silhouette and equipment, no labels, ground scenery, or neighboring fragments.
Preserve [approved proportions, identity, materials and unchanged parts].
```

For many directions, request a small number of identifiable views and verify each before expansion. Front/rear equipment landmarks must prove the view. A requested grid is a layout hypothesis, not a validated atlas. Do not assume a pose guide will reliably produce opposite leg contacts or a seamless sequence.

## Source Acceptance

Inspect full-resolution sources before rigging or packing. Check alpha, separated silhouettes, direction, complete limbs/hidden overlap surfaces, hand/equipment ownership, correct proportions, and consistent lighting. Reject materially wrong views or anatomy. Prefer targeted replacement sources over increasingly extreme deformation of an inadequate flat painting.

For segmented rigs, request complete torso/pelvis and separate near/far limb components with overlap surfaces. Record actual joints and contact landmarks per view; do not infer a hand from the end of a long weapon or reuse the same sleeve on both shoulders. Broad perspective changes need alternate paintings or a 3D source, not one picture-plane solver forced into every view.

## Extraction and Registration

Use inspected alpha-connected silhouettes or explicit verified rectangles. Equal-column cuts can include a neighboring figure or clip equipment. Preserve raw output; make alpha cleanup source-specific, especially when effects intentionally contain translucency. Normalize anatomical/object scale once, then register to a stable pivot or landmark. Never center each frame's changing bounds.

Palette matching can be restricted to one material while preserving skin, equipment, alpha, and shade planes. Keep raw-versus-calibrated comparison. Registration and color consistency do not repair an incorrect gait or changing anatomy.

Before full production, inspect a representative cycle in motion at native size. If separate generated poses repeat phases or jitter structurally, change the motion method rather than generating more nominal frames. The rigged alternative is described in [rigged-to-sprites.md](rigged-to-sprites.md).
