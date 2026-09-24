# Never scale a physics body unevenly - squash the mesh instead

This project uses Jolt Physics (set in project.godot). Jolt cannot represent a
capsule scaled differently on different axes. The enemy death animation squashed
the whole `CharacterBody3D` to `Vector3(1.4, 0.05, 1.4)`, and Jolt printed this
every single frame of the animation:

    Failed to correctly scale body ... A scale of (1.4, 0.05, 1.4) is not
    supported by Jolt Physics for this shape/body.

The fix was to tween the child `MeshInstance3D`'s scale instead of the body's.
The mesh is only ever drawn, never simulated, so it can be squashed freely and
the animation looks identical.

Why: On 2026-09-23 this filled the test output with hundreds of error lines and
buried the gameplay trace being read.

How to apply: animate scale on visual children, never on a `CharacterBody3D`,
`RigidBody3D` or `StaticBody3D`. If a body itself genuinely must change size,
change the shape's own `radius`/`height` rather than the node's scale.
