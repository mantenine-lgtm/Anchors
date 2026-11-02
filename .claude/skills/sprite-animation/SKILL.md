---
name: sprite-animation
description: Create and refine high-quality animated 2D assets and sprite sheets from visual references, authored frames, or rigged sources. Use for sprite production, motion design, frame alignment, animation repair, directional consistency, and engine integration; ChatGPT Pets use their own skills.
---

# Sprite Animation

> **MAZ 프로젝트:** 작업 전에 `../pixel-art-studio/references/maz.md`를 먼저 읽는다. 프로젝트 프로필은 그 문서이며 `references/dead-zone.md`는 다른 프로젝트 예시일 뿐이다.

Deliver assets that look coherent in motion at their actual display size. Appearance, motion, packaging, and integration are separate acceptance gates; passing one does not establish the others.

## Establish the Brief

- Inspect the destination renderer and frame format. Establish visual references, style, camera, palette, display size, direction conventions, timing, required sequences, transparency, and pivot/contact behavior.
- Define what makes the motion readable: its important poses, silhouette changes, timing, spatial relationships, and transitions. Express requirements in the subject's local coordinates before translating them into screen-space motion.
- Prototype one representative asset and the most demanding sequence before expanding. Preserve specifically accepted results; later feedback can narrow an earlier approval.
- When expanding an accepted rig, reuse its validated source, attachments and bake path; follow the expansion checklist in [references/production.md](references/production.md). Do not restart from a rejected method or assume one good cycle approves every role/view.
- Read [references/production.md](references/production.md) for methodology. Consult [references/lessons.md](references/lessons.md) only for relevant prior evidence. Project-specific requirements and commands belong in project profiles, such as [references/dead-zone.md](references/dead-zone.md), not in the general recipe.
- For reference-guided raster sources, use [references/raster-sources.md](references/raster-sources.md). For rigged-source production, use [references/rigged-to-sprites.md](references/rigged-to-sprites.md). Both contain the essential instructions; no other installed skill or original game checkout is required.

## Choose the Production Method

Choose based on the required motion, not merely the attractiveness of a still:

- **Authored frame sequence:** useful when shapes, perspective, or topology change substantially. Control identity, scale, palette, lighting, and pose progression across paintings.
- **Segmented 2D rig:** useful for predominantly planar articulation when the source supplies complete hidden surfaces and valid joints. It cannot invent missing surfaces or reliable depth changes.
- **Rigged 3D rendered to sprites:** useful for repeatable articulation, many directions, attachment constraints, and consistent depth. Model, materials, lighting, and rendered style must match the brief; primitive geometry is not an equivalent substitute for approved illustrated artwork.
- **Hybrid:** use a tested rig or pose reference to control motion while retaining authored appearance. Validate that the combination actually improves consistency before scaling it up.

Use an available image-generation/editing tool for raster artwork, following the included raster-source guide and the tool's actual interface. If no image tool is available, work from supplied/licensed source art or request it; do not claim to have generated it. Prefer included tools and do not silently switch to a separately billed API or service. Record the actual tool/model when exposed, prompts, references, dimensions, alpha, and cleanup. State capability gaps and untested claims plainly.

Repeated structural rejection after technical checks is a reason to test another production method, not to repeat a whole-roster parameter sweep. Keep the current working assets available during a pilot.

## Build and Package

1. Establish a source master that reads at native size and fits the surrounding art. Inspect structure, proportions, part ownership, materials, and real transparency before animation.
2. Author the motion's key poses, transitions, timing, and recovery or loop seam. Use genuine shape or articulated changes; translating an unchanged image is not a substitute for the requested motion.
3. Produce a controlled pilot. For rigs, use appropriate landmarks, joint ranges, attachment constraints, and complete overlap surfaces. For painted sequences, use stable identity references and explicit pose guides. Reject inconsistent sources before packaging.
4. Register frames to a meaningful pivot or stable landmark, not each frame's changing alpha bounds. Preserve intended motion rather than aligning it away. Use actual frame rectangles and common anatomical/object scale; pad for the full motion envelope.
5. Bake deterministically into the engine's format. Preserve frame order, anchors, durations, directions, tags, and sampling. Keep source resolution, atlas-body resolution, and displayed pixel size distinct. Minimize resampling, maintain appropriate backing-canvas density, and measure unused padding before trimming it.

## Validate Before Integration

**Visual gate:** inspect the source and the complete sequence, not just a sampled peak. Review native and enlarged playback, normal and slow speed, stepping, loop seams, direction changes, and relevant backgrounds. Compare accepted baselines synchronously. Judge structure, readable action, part/attachment continuity, proportions, shading, palette, and unintended jitter. Record observed failures and unreviewed combinations; generating a contact sheet is not completing a review.

**Technical gate:** independently inspect decoded frames for alpha, clipping, anchors, resolution, frame order, coverage, and timing. Test structural requirements through the actual render path, not only the baker's metadata. Use narrow measured regressions without pretending they are a general anatomy or aesthetic judge. Fixed parts, distinct pixels, and successful playback can all occur in a visibly bad animation.

**Critical pass:** judge raw rendered evidence against the brief separately from the creator's technical report. A second pass by the same agent is not independent-model review. Use a genuinely independent reviewer when available and authorized; otherwise disclose that limitation. Do not install known-failing sequences or describe technical success as visual approval.

**Integration gate:** exercise the actual served renderer at supported sizes, zooms, and pixel densities, including transitions and crowded scenes when relevant. Confirm scale, alignment, sampling, selection/occlusion, asset switching, and unaffected behavior. User feedback remains the authority on aesthetic acceptance.

## Inspection Helper

[scripts/inspect-sheet.mjs](scripts/inspect-sheet.mjs) checks frame bounds, alpha and exact duplicates, and builds a standalone playback/stepping review. It preserves source cells and does not repair poses or approve visual quality.

```sh
node /path/to/sprite-animation/scripts/inspect-sheet.mjs sheet.png \
  --columns 4 --rows 1 --module-root /path/to/project \
  --report sheet-audit.json --preview sheet-review.html
```

For irregular frames, use `--frames frames.json`: an array or `{ "frames": [...] }` of `id`, `rect: {x,y,w,h}`, optional `anchor: {x,y}` and `durationMs`. Adapt this inspection format to the destination engine rather than replacing its schema.

## Maintain and Deliver

When maintenance is requested or explicitly authorized, record specific methods, outcomes, feedback, evidence, scope, and next decisions in the relevant references. Promote only demonstrated conclusions into the general methodology; keep project requirements local, recommendations separate from observations, and failed attempts clearly labeled. Using this skill does not itself authorize publication, purchases, unrelated skill changes, or separate memory-registry updates.

Deliver saved asset paths, a working review link, the production method actually used, validation results, and remaining limitations. Do not promise first-pass perfection or imply a model/service was used when it was not.

## MAZ 사용 예

Playwright가 설치된 환경에서 v5 idle 시트(4행 × 96열) 검수:

```sh
node .claude/skills/sprite-animation/scripts/inspect-sheet.mjs \
  /mnt/project-files/art/claude-sprites/classes-v5-idle/out/military/warrior_idle_sheet.png \
  --columns 96 --rows 4 --report audit.json --preview review.html
```
