# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

"Marea Negra" is a 3D pirate game built in Godot 4.7 (Forward+ renderer), combining ship
navigation with on-foot exploration/combat (Pirates of the Caribbean-style). 3D models are
authored in Blender and imported into Godot as glTF.

The project is currently a functional placeholder: every mesh is a Godot primitive (capsule,
box, plane) standing in for future Blender assets. Gameplay scripts are written to be
mesh-agnostic so primitives can be swapped for real models without touching script logic.

## Commands

There is no build step, package manager, linter, or test suite in this project — it's a Godot
project opened directly in the editor.

- Open/run the project: open `project.godot` in the Godot 4.7 editor, or from the CLI:
  `godot --path .` (opens the editor) / `godot --path . scenes/world/main_world.tscn` (runs a
  specific scene directly).
- The main scene (`run/main_scene` in `project.godot`) is `scenes/world/main_world.tscn`.

## Architecture

**Input handling is hardcoded, not using the Input Map.** Scripts check physical keys directly
via `Input.is_key_pressed(KEY_*)` (movement, throttle, turning) and via `_unhandled_input` for
one-off key presses (jump handled in `_physics_process`, interact/escape/mouse-capture in
`_unhandled_input`). There are no entries in `project.godot`'s `[input]` section. If adding new
controls, follow this same direct-key-check pattern for consistency, or migrate everything to
the Input Map at once (see "Próximos pasos" in `README.md`) — don't mix the two approaches
partially.

**Interaction is duck-typed via `on_interact`.** `player_controller.gd` casts a `RayCast3D`
(`CameraPivot/Camera3D/InteractRay`) forward and, on E, calls `on_interact(self)` on whatever
it hits if that node defines the method (checked with `has_method`). `ship_controller.gd`
implements `on_interact` as the hook for boarding. Any new interactable (chest, NPC, cannon,
ladder) should follow this same convention rather than introducing a separate interaction
system.

**Placeholder-primitive design.** Every `.tscn` builds its mesh/collision from inline
`sub_resource` primitives (`CapsuleMesh`/`CapsuleShape3D` for the player, `BoxMesh`/
`BoxShape3D` for the ship and island, `PlaneMesh` for water) rather than imported models. When
replacing a primitive with a Blender-exported `.glb`, keep the same node structure (collision
shape sized to match, same node names like `CameraPivot`, `HelmPosition`) since scripts
reference children by `$Path` (e.g. `$CameraPivot/Camera3D/InteractRay`, `$HelmPosition`).

**Ship movement is kinematic, not physics-driven.** `ship_controller.gd` is a
`CharacterBody3D` that derives velocity from an accelerating/decelerating `throttle` scalar
(`-transform.basis.z * throttle`) plus a manual `sin()`-based vertical bob as a stand-in for
wave motion — there's no `RigidBody3D`/buoyancy physics yet. Real water/buoyancy is planned
(see README) but not implemented; don't assume physics forces affect the ship.

## The fleet, and why the names moved

Four hulls, and the naming was corrected on 19 August 2026 because one of them was misnamed:

| Name | Rig | State |
|---|---|---|
| `lancha` | one square sail on a yard + boom | rigged: `raiz`, `vela`, `driza`, `timon`; parts marked |
| `barca` | one square sail, set athwartships | welded only. **Was called `balandra`** until the rename |
| `balandra` | gaff mainsail + jib, fore-and-aft | new Meshy model, 1,67 M verts, nothing done yet |
| `goleta` | schooner | untouched |

The old "balandra" is not one: its sail spans 87,6 cm of a 94 cm beam, i.e. it is set across the
ship — a square sail. A real balandra is a **gaff sloop**, fore-and-aft rigged, which is what the
new model is (its beam is only 44 cm on a 191 cm hull precisely because the sails lie along the
length). The two rigs are sailed differently — a square rig points ~65-70° off the wind and is
trimmed by braces; a gaff sloop points ~45° and is trimmed by sheets — so the distinction is
mechanical, not cosmetic.

`assets/models/barca.glb`, `scenes/barcos/barca.tscn` and `fuentes/blend/barca.blend` were
renamed together; the `.tscn` keeps the collision box, flotation height and model scale that were
measured for that hull, so **don't reuse them for the new balandra** — it has different dimensions.

## Rigging the ship models (Blender)

**Before touching a `.blend` or a `.glb`, read the rigging procedure.** It covers how to drive
Blender over MCP, how to weld photogrammetric meshes, the skinning rules, how to verify results
with measurements instead of by eye, and the known traps of `bpy`, glTF and the Godot CLI. It is
shared with `game-2d`, so it lives one level above this repo, next to both projects:

```
E:\Godot\Game3D\claude-skills\blender-godot-rigging\SKILL.md
```

Read that file directly — it is plain Markdown and needs no installation, so it works in any
session and on any machine that has the drive. Keep it updated: whenever we find a better way to
do something generic (welding, weights, verification, export), it goes there; whatever is
specific to this ship goes below.

**The models are photogrammetric: never guess what a piece is.** Every `.glb` comes from a
scan-like mesh with hundreds of disconnected fragments and no semantics. Deriving vertex
weights from heuristics (per island, per shape, per distance to the hull) works for most of the
mesh and *always* breaks at the joints — the symptom is a piece that twists or a rope that
tears when the sail trims or lowers. Don't do it. Ask the user to mark the part in Edit Mode,
read the selection, and derive the weights from that.

**One source of truth: the integer `parte` attribute** (one value per vertex, 0 =
unclassified), defined in `blender_src/partes_barco.py` along with each part's colour and
movement rule. It is the only thing edited by hand; everything else is generated from it:

    parte attribute  ─┬─►  `Partes` colour layer   (just to look at)
                      ├─►  `parte_*` vertex groups (for Blender's panel)
                      ├─►  `Col` colour layer      (read by the cloth shader)
                      └─►  skeleton weights       (raiz / vela / driza / timon)

An integer attribute holds exactly one value per vertex, so **a vertex cannot belong to two
parts** — overlaps are impossible by construction rather than something to hunt down (there
used to be a `solapes()` check for exactly that; it is gone because it cannot happen). The
colour layer and the vertex groups are *projections*: `refrescar_color()` and
`sincronizar_grupos()` rebuild them, and editing them by hand achieves nothing.

Call `marcar_parte(nombre)` to assign the current selection, `seleccionar_parte(nombre)` to
review one, `limpiar_parte(nombre)` to start it over, and `informe()` to see what is still
unclassified. The marking lives in each ship's `.blend` and **cannot be reused between ships**
(they are vertex indices of one specific mesh) — the script and the rules are what carry over.
Neither the attribute nor the `parte_*` groups are exported to `.glb` (glTF only exports
colour, UV, joints and weights), so they don't pollute the game model.

**Mark exactly what the user selected, and only after they confirm it.** They adjust the
limits on screen after seeing a proposal, and those limits are the valid data. Never
substitute a geometric criterion of your own for their selection, and never judge a marking
from the orange selection view — the active-object outline covers thin pieces (2-3 mm ropes)
entirely and makes them look classified when they aren't. To review, show the `Partes` colour
layer (`shading.color_type='VERTEX'`, `overlay.show_outline_selected=False`).

Two checks in the same file, meant to be run right after marking rather than discovering the
problem in Godot: `verificar(parte)` contrasts a part against the skeleton weights (a `fija`
part with weight in `vela` or `driza` will move when animated, however well it is marked), and
`guardar_marcado()` / `restaurar_marcado()` mirror the attribute to
`blender_src/marcado_<barco>.json` as index ranges plus a topology fingerprint. The attribute
survives ordinary mesh edits, but welding or decimating reindexes everything and voids the
marking — restore refuses to run when the fingerprint doesn't match, instead of silently
painting pieces at random. `migrar_desde_grupos()` exists for one-off recovery from the old
group-based marking.

**One procedure for every ship, and one manual step in it.** Marking the parts is the only
thing done by hand; the cloth colour layer and every skeleton weight are *derived* from it by
`procesar_barco()`. Before, the same mesh carried three independent markings (parts, `Col`,
weights) and each new ship meant repeating all three.

1. Weld the mesh (see below). Nothing downstream works unwelded.
2. Mark the parts — the manual step. Review with `ver()` and `seleccionar_por_color(parte)`.
3. `informe()` until nothing is unclassified.
4. `procesar_barco()` — rebuilds colour and groups, generates `Col`, generates the weights,
   saves the marking to `marcado_<barco>.json`, and verifies no `fija` part carries a moving
   bone's weight.
5. Export with `export_vertex_color='NAME'`, `export_vertex_color_name='Col'`.

The engine behind steps 4 is **geodesic distance** — distance along the mesh edges, not
straight-line. It is what makes gradients continuous (two touching vertices get near-identical
values whichever fragment they belong to) and why the ropes stopped tearing in segments.
Anchors need no marking either: an anchor is by definition where cloth touches wood, so
`_contacto()` finds them from the part adjacency. Calibrated against the hand-painted red on
the lancha, the generator reproduces the flag at `k=1.0` with 0.021 mean error and the sail at
`k=0.5` with 0.096.

`verga` and `botavara` are deliberately separate parts, not one `perchas`: both swing when
trimming but only the yard rises when hoisting, so a shared rule would break one of them.

**Hard rules, decided with the user:** the hull and the mast are wood and **never deform** —
`raiz = 1`, no exceptions, no gradients. Forestay and shrouds likewise. Only sheets and braces
(`parte_escotas`, `parte_brazas`) carry a gradient from sail to hull, because they genuinely
tension when trimming. Spars (yard and boom) follow the sail bone as a rigid whole; a spar with
mixed weights twists, and *setting weight 1 on one bone is not enough — you must remove the
weight from the other one*, since Godot normalises.

**Pieces that slide must be cut, not re-weighted.** Welding fused the yard's parrel with the
mast, so they share faces. When the yard drops 77 cm and the mast doesn't, those faces stretch
77 cm and show up as long threads down the mast. No distribution of weights or part labels
fixes it — moving the boundary only moves where it tears. `separar_costura()` cuts it with
`bmesh.ops.split` on the seam faces and pins the resulting sheet to the mast, keeping every
face (no holes). Measured: 770 mm → 0 on that frontier. It must be re-run after any label
change touching that boundary. Four approaches that do NOT work are documented inside the
function — don't retry them.

**The mast's lower stretch is a copy of the real mast, not a generated cylinder.** The scan left
the mast floating in mid-hull, ending at z = −68 cm. The first fix was a hand-made 16-segment
tube, and it never stopped reading as a different material: base colour, roughness, metallic and
emission all matched within a few per cent, yet the piece looked smooth and satin next to scanned
wood, because the relief of a photogrammetric mesh lives in the geometry (41–50 verts/cm) and not
in the texture. The fix was the user's idea — duplicate a band of the real mast, scale it and weld
it on — and it carries the density, the relief, the UVs, the `parte` label, `Col` and the weights
for free. It now spans z = −68,10 to −88,4 cm (the hull floor is at −87,9), welded to the collar
with a planar `bisect` cut plus `bridge_edge_loops` (0,5 mm of vertical play, 1,6 mm of radial),
and its free bottom evened out by extruding the boundary to a common plane and capping it. Only
the generic technique is in the shared skill file; what matters here is **don't rebuild it as a
primitive**. Two pre-existing open loops in the mast (z ≈ −65 and ≈ −55) are from the scan — leave
them alone.

**Gradients on cloth go by geodesic distance between its two seams**, not by height. With
height, the vertices sewn to a spar sit slightly below its axis and come out at `t ≈ 0.95`
instead of 1, which stretched the seam 38 mm against the yard and 23 mm against the boom.
Geodesic distance from seam to seam gives exactly 0 and 1 where it matters. One guard is
essential: **belonging to a seam overrides everything** — a vertex touching both spars has
both distances at 0, and without the guard it fell through to the height fallback.

**Welding threshold can never exceed the thinnest piece.** The ropes here are 2-3 mm thick, so
1 mm is safe and 4 mm destroys them: it fuses one side of the tube with the other and the rope
collapses into a sheet. Measured on the forestay: 176 vertices fused at 1 mm, **6 894 at 4 mm**
(77 % of the piece). The bounding box does not reveal it — it changed 1,6 mm — because the
collapse is inward; the valid indicator is how many vertices get fused. And it is not needed
for rigging: separate islands inside one part share the same weight and no edges, so nothing
can stretch between them. It only matters in the parts carrying geodesic gradients.

**Two colour layers, don't mix them up.** `Col` is the cloth shader's (red = how much a vertex
moves, green = flag); `Partes` is only the part classification, for looking at it. When
exporting, pass `export_vertex_color='NAME'` with `export_vertex_color_name='Col'`, or the
active layer gets exported instead and the sail stops waving. They stay separate on purpose, and merging them is not an option: `Col` is production data — continuous, read by the shader every frame, exported; `Partes` is authoring metadata — discrete, Blender-only. One channel cannot hold both a flat "I am sail" colour and the gradient that makes it wave. Switch what the viewport shows with `ver()` / `ver("Col")` / `ver(texturas=True)`; without it, it is easy to conclude a layer was lost when you are looking at the other one — or at the textures.

**Weld before rigging, but leave sliding joints unwelded.** Merging by distance at 1 mm turns
370 islands into 6, which is what makes coherent weights possible at all. Exclude the vertices
where two pieces slide over each other (in the lancha: the yard's parrel over the mast, 581
vertices found by looking for near-coincident pairs with very different `driza` weights) or
they'll tear by the full travel of the bone.

## Building a ship from pieces, and the baked library

Marking parts by hand on one huge Meshy mesh was the bottleneck: the balandra still had 234 584
unclassified vertices when we stopped. **Generating each piece as its own Meshy job makes the
classification implicit** — the object name is the part — and hands each piece the full 4096²
atlas instead of a slice of a shared one. It also kills two of the hardest problems by
construction: `separar_costura()` becomes unnecessary (pieces that slide cannot be welded if they
arrive as separate objects) and there is no interior geometry hidden under a deck to hunt down.

The generation prompts live in `fuentes/prompts_meshy.md`, grouped so that the atlas is split
where it matters — the sails are ~104 m² and the spars ~12 m², so putting them together starves
the spars. That file also carries the lessons of six image rolls, and they are worth reading
before writing a new prompt: **absolute numbers get ignored and comparatives are obeyed** (`12.5 m
long, 26 cm across` produced a spar four times too thick; `fifty times longer than it is thick` is
the fix), **camera angles must be described by what is visible** rather than in degrees, and the
interior must be described *positively* — `no interior structures` was ignored while `one smooth
fair surface of continuous planking from rail to rail` was obeyed first time.

**The balandra is assembled in `fuentes/blend/balandra_piezas.blend`**, at real metres: hull
12 × 3,95 × 2,36 m with the keel at z = 0, bow at −X, rail at 1,766 m amidships, rudder raked
14,35° to match the sternpost. Note that the hull arrived with its own fore and aft decks at
1,766 and 1,658 m, so the deck panel only covers the middle 9 m and the ends are the hull's own.

**Fitting a deck to a hull is measured, not eyeballed.** Ray-cast from the centreline outwards at
the deck's own height to find the inner face, and trim in **two dimensions, x and z** — not one.
The hull narrows downward, so a trim computed at a single height leaves the deck's underside
poking out through the planking; 12 593 vertices did exactly that. The rigorous inboard test is
that the lateral ray hits with a **normal pointing back at the origin**: a ray that exits through
the outer skin means the origin is inside solid wood, which is what happens near the bow and
stern where the hull is filled below its own decks.

**The library** is `fuentes/blend/biblioteca/<pieza>.blend`, one file per baked prop, with the
high-poly deliberately left out — it is reproducible from `fuentes/crudo/` in a second and a half
and keeping it multiplies the file size by seven. First piece in: `cubierta`, 2 324 vertices
against the raw model's 553 027.

What is reusable about a deck is **the planking, not the outline** — the outline gets re-cut for
each hull. And extracting a prop out of an already-generated model is the harder path: pulling the
gratings out of the detailed deck took four attempts because they are welded to the planking
across 117 fragments, and neither connectivity nor a bounding box separates them (their own frame
does). So generate new props as their own Meshy job, and carve only what cannot be regenerated.

The full baking procedure — contour by bisection, quad grid cut by Knife Project, UV layout in two
bands, bake before thickness, and the approaches that do *not* work — is in the shared skill:
`claude-skills/blender-godot-rigging/protocolos/pieza-de-biblioteca.md`.

**Folder conventions** (see `README.md` for the full Blender→Godot export workflow):
`scenes/{world,ship,character,ui}` group scenes by role; loose `scripts/*.gd` are attached to
scenes rather than being colocated with `.tscn` files; `assets/{models,textures,audio}` holds
Blender exports (`.glb`) and other art. Everything upstream of the game lives under `fuentes/`,
which carries a `.gdignore` so Godot never scans it:

- `fuentes/crudo/` — the untouched Meshy downloads, **never renamed**, with their NTFS
  `Zone.Identifier` stream intact (`props/` for the CC0 ones, `referencias/` for the 2D images).
  That stream is the provenance evidence and it holds the Meshy UUID — see
  `assets/models/PROCEDENCIA.md`. Move these only with PowerShell; `cp`/`mv` in Git Bash drop
  alternate data streams silently.
- `fuentes/blend/` — the working `.blend` per ship, with `respaldos/` for session snapshots.
  Textures are packed inside each `.blend`, so they are self-contained and safe to move.
- `fuentes/blend/biblioteca/` — one `.blend` per **baked prop**, ready to place on any hull:
  origin at (0,0,0) on the face you see, no pending rotation or scale. `tex/` holds the loose
  maps the `.blend` packs (colour as JPEG, normal as 8-bit PNG — never a float buffer, which
  packs as OPEN_EXR and takes the file from 14 to 137 MB).
- `fuentes/prompts_meshy.md` — the generation prompts, one per group of pieces, each with the
  ≤ 2 000-character version the image generator actually accepts.
- `blender_src/` — the pipeline scripts (`partes_barco.py`) and the `marcado_<barco>.json`
  files. `exportar_glb()` derives the `.glb` name from the `.blend` basename, so **renaming a
  `.blend` renames the asset Godot consumes**.
