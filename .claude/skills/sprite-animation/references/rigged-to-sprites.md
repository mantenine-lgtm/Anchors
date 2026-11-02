# Rigged Sources to Sprite Sheets

This is a self-contained production recipe for the accepted method. It requires a suitable licensed skinned model, authored animation clips, and a 3D rendering/animation tool such as Three.js or Blender. Those are software and asset inputs, not a dependency on the original Zombie code or another skill. This repository bundles final example sheets, not the source models or a universal retargeting application.

## 1. Freeze Inputs and Rest State

Inspect the model, bone hierarchy, weights, axes, limb proportions, materials, and authored clips before changing them. Record licenses and exact dependency versions. Clone skinned scenes with a skeleton-aware clone, not a shallow shared skeleton. Before running any clip, save immutable local positions/quaternions and required world matrices for both source and target. Keep appearance/gear configuration separate from motion.

For compatible named bone frames, a tested quaternion offset is:

```text
offset = targetRestLocalRotation * inverse(sourceRestLocalRotation)
targetPoseLocalRotation = normalize(offset * sourcePoseLocalRotation)
```

This is not a universal correction for arbitrary bone axes or different hierarchies. Incompatible frames require explicitly authored basis conversions or a proven retargeter. Do not calculate the offset from a pose left over by the mixer. For translated roots, apply displacement relative to the source rest root to the target rest root, with a deliberate proportion scale; do not copy absolute positions of every bone.

## 2. Evaluate Samples Independently

For each clip/view/sample: stop/reset active actions, restore target rest transforms, reset whole-object rotation/scale, evaluate the authored clip at the chosen time, and update world matrices. Only then apply local corrections, attachments, and contact constraints. Apply final viewing rotation after subject-local motion constraints so facing cannot change the meaning of up, left, or forward.

Loop sample times normally use `t = i / N` for `i = 0..N-1`; do not duplicate the endpoint. One-shot motion may use `t = i / (N-1)` when its authored final recovery is needed. Keep source-clip duration, baked sample count, playback FPS, and runtime motion phase explicit. If frame count changes, deliberately preserve or revise duration rather than accidentally speeding the action up.

Choose appropriate source clips before adding lean or arm constraints. An already crouched clip should not inherit another subject's upright correction. If the brief requires planted legs, preserve a reviewed lower-body pose while applying the upper-body motion; still inspect weight transfer and all views.

## 3. Moving Props and Real Palm Contacts

For a prop configured in the subject's reference body frame, use:

```text
bodyDelta = currentBodyWorldMatrix * inverse(restBodyWorldMatrix)
propWorldMatrix = bodyDelta * propReferenceWorldMatrix
```

Keep scale inheritance intentional. Transform prop-local grip positions through the resulting prop matrix. Choose a desired hand orientation relative to the prop, and derive wrist targets from a hand-local palm offset:

```text
palmWorld = transformPoint(propWorldMatrix, gripLocal)
handWorldRotation = propWorldRotation * gripToHandRotation
wristTarget = palmWorld - rotate(handWorldRotation, palmLocalOffset)
handLocalRotation = inverse(parentWorldRotation) * handWorldRotation
```

Solve the arm to the wrist target, then assign the intended hand orientation and update matrices. Verify the resulting mesh palm contact, not just the wrist coordinate. If the target is unreachable through part of a cycle, adjust the prop/contact envelope; do not hide an error behind clamping. A prop-only render checks that its motion actually follows the body.

During hands-free work, retain equipment on a reviewed storage frame such as the back, using the same animated-parent principle. Do not constrain freed working hands to a stored prop. Storage poses and equip/stow transitions are different deliverables.

## 4. Two-Bone Contact Geometry

Let `S` be the shoulder, `T` the wrist target, and `a`, `b` the upper/lower segment lengths. Let `u` be the normalized direction from `S` to `T`; choose a stable bend-plane pole in subject-local space and transform it to the solve space. Clamp reach away from singular full extension, but record any resulting target error. With reach `d`:

```text
along = (a*a - b*b + d*d) / (2*d)
bendDirection = normalize(pole - u * dot(pole, u))
bendHeight = sqrt(max(0, a*a - along*along))
elbow = S + u*along + bendDirection*bendHeight
```

If the pole is nearly parallel to `u`, use a stable alternate pole; never normalize a zero vector or allow it to flip arbitrarily between frames. Rotate each bone from its current child direction toward the solved point, convert world rotation through the inverse parent rotation, and update the chain after each change. Smooth a reach boundary where needed. Matching lengths and endpoints still does not prove credible joint roll or skin clearance.

Inspect posed sleeves/forearms against the actual torso and gear. A source-skin vertex/hull audit can expose penetration missed by joint tests; define exclusions, fingerprint inputs, and disclose that it is not full triangle collision or aesthetic approval. Preserve accepted contacts, opposite-limb motion, and unrelated clips while repairing a local clearance issue.

## 5. Camera, Light, and Stable Packing

Use a fixed orthographic camera and world lighting. Define the projected contact pivot and useful body/object density before rendering. Render all views with consistent materials, exposure, tone mapping, and alpha. A tested illustrated pipeline renders at 4x source size and reduces once with high-quality filtering; deliberate pixel styles need a different sampling decision.

Measure the union of all emitted silhouettes across every action/view for one subject, add motion-safe padding, and crop every cell identically. Adjust the pivot by the same crop offset. Do not recenter individual poses. Bone-height density, atlas padding, and runtime presentation scale are separate parameters.

Map directional labels against the destination engine's actual projection and motion. A reversed turn order is not necessarily a 180-degree error. Preserve already-correct views and make any correction explicit/idempotent. For long objects, validate wheel/foot plane, shadow, and selection together; the lowest opaque pixel is not necessarily the correct world pivot.

## 6. Package and Judge the Result

Emit transparent PNG atlases plus explicit per-clip/per-direction rectangles, frame cadence, looping policy, pivot, and presentation scale. Keep source/license provenance and accepted baseline hashes. The destination can remain a 2D renderer.

Review every delivered sequence/view at normal and slow speed, native and enlarged scale, and through loop transitions. Check pose progression, part ownership, contact/clearance, identity markers, and lighting. Separately audit decoded alpha, clipping, timing, and coverage. Exercise actual served movement, sampling, occlusion, scale, and state transitions. Same-agent review and passing geometry tests do not establish independent or automatic aesthetic approval.
