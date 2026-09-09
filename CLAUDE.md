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

There is no build step, package manager, or linter — it's a Godot project opened directly in
the editor. There **is** a test suite; see below.

- Open/run the project: open `project.godot` in the Godot 4.7 editor, or from the CLI:
  `godot --path .` (opens the editor) / `godot --path . scenes/world/main_world.tscn` (runs a
  specific scene directly).
- The main scene (`run/main_scene` in `project.godot`) is `scenes/world/main_world.tscn`.
- **Run the tests:** `godot --path . tests/pruebas.tscn` — exits 1 if anything fails, and prints
  one line per check. One test file per package (`tests/barco_test.gd`, `tela_test.gd`,
  `mundo_test.gd`) driven by `tests/pruebas.gd`.

  **The failing test comes first, then the fix — this is mandatory here.** The protocol is
  "Pruebas en Godot y cómo trabajar con TDD" in the shared skill
  (`claude-skills/blender-godot-rigging/SKILL.md`): reproduce the symptom as a NUMBER with a
  tool in `tools/`, write the assertion, **run it and watch it fail**, fix, run the whole suite,
  and repeat the run three times if the failure was intermittent. Never raise a threshold to go
  green, and never treat a zero from a partial check as having ruled anything out.

  They run **with a window and as a scene**, and that is not negotiable: `--headless` does NOT
  simulate `SoftBody3D` (the points stay frozen and every cloth measures "perfect"), and with
  `-s` the autoloads are never instantiated, so anything touching `Viento` fails to compile.
  After adding a script with `class_name`, run `--headless --import` first or the CLI reports
  `Could not find base class`.

- **Measuring tools** in `tools/`, each one a SCENE (with `-s` there are no autoloads and
  `barco.gd` will not compile, because it uses `Viento`), and several need a WINDOW because
  `--headless` does not simulate `SoftBody3D`:
  `donde_esta_la_proa.tscn` (where the bow falls in the ship's own axes — measure it, never read
  the basis off the `.tscn`), `anclas_en_perchas.tscn` (cloth points trapped inside the spar
  colliders, and which capsule traps which), `perfil_mastil.tscn` (the mast's radius along its
  axis, which is how the number of capsule sections gets dimensioned), `area_que_gana.tscn`
  (which wind area actually governs which cloth), `eje_bandera.tscn` (which axis the shader turns
  the flag about versus the mast's real one — it is what caught the 9,4°), `col_bandera.tscn` (what
  a cloth's `Col` layer actually carries, which decides whether the shader can drive it),
  `foto_viraje.tscn` (the flag through a 90° turn to starboard, from a camera fixed to the SHIP —
  in world axes the shot drifts off as soon as she turns and the frames are not comparable),
  `coste_fisica.tscn` (what raising the physics rate really costs, with the fps cap OFF — with
  vsync on the scene sits at 120 fps and the cost is invisible), `densidad_velas.tscn` (mesh
  density per cloth, vertices per m²), `golpe_vela.tscn` (the sail's throb as a TIME
  SERIES — peak over median, which is what tells a heartbeat from flutter, and it logs
  `factor_viento()` beside it so you know whether the sail was drawing or luffing),
  `latido_velas.tscn` (what makes a sail throb, and it must be measured in the SHIP's space or
  all you see is the hull bobbing) and
  `probar_acabado.tscn` (before/after captures plus local contrast, the only way to tell whether
  a material detail is actually being applied).

  They drive the game through its own keys (`Input.parse_input_event`) rather than calling
  methods, and measure cloth in the **physics** clock (`await physics_frame`) — read from
  `_process`, anchor points and free points come from different instants and the numbers
  alternate between two values. See "Depurar en Godot sin engañarte" in the shared skill.

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

## How the game code is organised (Godot)

**Functionality that belongs to an object lives IN that object.** There are no loose
node-scripts orchestrating other nodes through `get_parent()` and `find_children()`; that was
the previous shape and it made a single feature — who moves the flag — take a whole session to
locate, because it was split across three files.

    Barco (CharacterBody3D, class_name Barco)   scripts/barco/barco.gd
     ├─ navigation, flotation, RUDDER, deck COLLIDERS, MODE SWITCH (helm ↔ on foot)
     ├─ commands its sails by method name (izar/arriar), never by type
     ├─ instantiates its CARGO and applies the wood FINISH
     └─ Balandra extends Barco                  scripts/barco/balandra.gd

    TelaFisica (SoftBody3D cloth)               scripts/tela/tela_fisica.gd
     ├─ VelaFisica   — izar()/arriar()/trimar(), and furls the cloth
     └─ BanderaFisica — orientar(): weather-vanes to leeward

    TelaShader (shader cloth)                   scripts/tela/tela_shader.gd
     ├─ VelaShader   — same izar()/arriar()/trimar()
     └─ (the FLAG needs no subclass: TelaShader already weather-vanes it, off Col)

    Aparejo (Resource)                          scripts/tela/aparejo.gd
        the halyards and the trim of ONE sail — bones, travel, speed

    Carga (Resource)                            scripts/barco/carga.gd
        one stowed item: which .glb, where, how turned, how big

    AcabadoMadera (Resource)                    scripts/mundo/acabado_madera.gd
        the fine wood relief that the .glb cannot carry

`Aparejo` is a resource and not a node because both cloth branches need it and GDScript has no
multiple inheritance: a physical sail and a shader sail are hoisted and trimmed identically
(moving skeleton bones) and differ only in how the cloth is drawn. Each sail owns its own
instance — it holds state. `Carga` and `AcabadoMadera` follow the same rule for the same reason:
they are DATA, and the ship is what acts on them.

**What does not fit in the `.glb` is put back in Godot, in code, not baked.** Two cases so far,
both from 7-8 September 2026:

- **Cargo.** The three barrels and three crates were welded inside `balandra.glb`: impossible to
  move, remove or reuse. Now each is its own `.glb` in `assets/models/` and `Balandra` declares
  where they go. The figures are measured from the old model, not eyeballed — see the docstring
  of `_carga_de_salida()`, which also records the trap: the basis of the `Modelo` node has to be
  **measured in the running game** (`tools/donde_esta_la_proa.tscn`), because reading it off the
  `.tscn` text gives its transpose and the cargo lands turned 180° at the wrong end of the ship.
- **Wood relief.** In Blender it is the node group `RELIEVE_MADERA`, a procedural triplanar; glTF
  carries nothing of it and baking it is not viable (the hull would need a 32768² atlas for
  1 px/mm — it currently gets **0,059 px/mm**, one pixel every 17 mm). Godot does triplanar
  natively, so `AcabadoMadera` reproduces it: colour still comes from the baked atlas, unique per
  piece, and only the relief repeats. `Barco.acabado_madera` is a LIST because the deck planking
  and the hull need the grain turned a quarter turn against the masts and spars.

**Cloth colliders: capsules per SECTION, and never over an anchor.** `perchas_solidas.gd` gives
the spars a body so the cloth rests on them instead of going through. It builds **eight capsules
along each spar**, each with the maximum radius of ITS section, and a **negative** margin
(−2 mm). One capsule of constant radius cannot describe a tapered mast — this one runs from
130 mm of radius at the heel to 46 mm at the truck, so a single capsule has to use the maximum
and swallows 84 mm of air at the top, exactly where the flag is stitched. An anchored point
inside a collider is an unsolvable conflict: the solver pushes it out every physics step and the
bone puts it back, and that shows up as a repeated blow travelling out from the spar.

**The chain is spread over the mesh's REAL axial extent (`t_min`..`t_max`), never symmetrically
about its centroid.** Those coincide only when the vertices are evenly spread, and on this mast
they are not: 134 of its 201 vertices are the cluster at the truck. With `max(|t|)` the chain
measured 14,03 m for an 8,75 m spar — 5,26 m of it solid air above the truck — and, worse, it
put the collar (109 mm of radius) and the flag in the SAME section, so that capsule took the
109 mm and swallowed the flag's whole anchor column, 53,8 mm deep, 100 % of the frames. Real
extent plus eight sections cuts at t = +0,66 and gives the flag its own 46 mm capsule: zero.

`tools/anclas_en_perchas.tscn` counts them — and note **it only read `get_child(0)` of each
spar until 8 September 2026**, that is, the section at the heel. With that measurement the flag
always came out clean, and it is what made us rule the colliders out when they were the cause.
A check that does not cover every body rules nothing out.

**Wind is a uniform field, so cloth cannot flutter on its own — the cloth adds that itself.**
Godot 4 exposes no forces on `SoftBody3D`, so the wind arrives as directional gravity in an
`Area3D`. `Viento` gusts at 0,1-0,5 Hz and wobbles its direction at 0,08 Hz: slow, and identical
at every point of the cloth. A field like that has no feedback loop — real flutter is
aeroelastic, the cloth deflects the air and the air pushes the cloth — so the cloth settles into
its equilibrium and stops. The flag measured 42-45 mm of movement and 14° of fly: correctly
pointed downwind and stiff as cardboard. `TelaFisica.flameo` puts back a transverse component
that oscillates (two incommensurable harmonics, frequency scaled by wind force as Strouhal
would). At 0,6 and 1,4 Hz the flag goes to 88 mm and 48° with the stretch untouched. **It is not
a flag hack** — any cloth taking the wind edge-on has the same problem, a luffing sail included,
which is why it lives in `TelaFisica` and defaults to zero: the sail that should luff will ask
for it, and the day flutter depends on angle of attack it is computed in that same place.

**Anything that weather-vanes on a moving ship goes by the APPARENT wind.** `Viento.aparente(v)`
returns the true wind minus the object's own velocity, using `Viento.velocidad_m_s` to put both
in the same units. **That constant must exceed the ship's top speed** — it is 16 m/s against the
balandra's 9 — because a vessel cannot outrun the true wind dead downwind: if it does, `aparente`
changes sign and everything that weather-vanes turns 180° while the cloth keeps flying to leeward.
It was 8 m/s at first, fitted on a beam reach, and running downwind that put **160,6°** between the
flag's bone and its own cloth — the "flag that gets stuck and never comes round the mast", which
went away as soon as the ship anchored and its speed dropped to zero. At 16 m/s it is 21,6°. With the balandra at 8-10 m/s and the wind on
the beam there are up to 50° between true and apparent. The CLOTH finds the apparent wind on its
own — a `SoftBody3D` lives in world space, the ship drags it and its own drag aligns it — so
before the fix the flag's cloth flew at the apparent wind (1-8° off) while `BanderaFisica` aimed
the BONE at the true one (58° off): the halyard pointed one way and the sailcloth another, and it
read as a flag that never finished swinging round. **Measure the bone, not the cloth**, when
checking this — `BanderaFisica.direccion_de_vuelo()` exists for that. A test on the cloth passes
either way; I wrote one and it read 10,3° with the bug in and 10,3° with it out.

**A cloth's `empuje_viento` must be well above the ship's speed, or it goes slack downwind.**
The wind field is an acceleration and the cloth is dragged bodily through world space by its
pins, so the ship's own speed subtracts from what the cloth feels — the apparent wind, emerging
for free. Turn 90° to starboard from a beam reach and the ship ends up running: it chases the
wind at 9 m/s and the flag is left with almost nothing. Measured with `empuje_viento` at 10, the
flag's fly collapsed from 0,59 m to **0,28** (of the 0,96 m it measures) and stayed there until
the ship anchored — which is exactly the "flag winds itself round the mast and never finishes
turning" the user reported, and why anchoring cured it. At 35 it holds 0,42 m, 69 % of its
beam-reach flight.

Three things it is NOT, all ruled out by measuring: the bone's slew rate (`suavizado` 1,2 and 6
give the same numbers to three decimals — so no, turning the flag faster does not help), the mast
capsule, and the flutter. And **measure the LENGTH of the flight, not its angle**: a slack cloth
can be pointing perfectly well. More wind then needs a firmer solve — `precision` 5 → 10 on the
flag, or the extra pull puts 4 edges past 25 % stretch against a limit of 3. More iterations,
never a looser threshold.

**A luffing sail must flutter, or it gives a "heartbeat".** Head to wind (`factor_viento()` = 0)
the mainsail used to throw one whole snap every ~6,4 s — half the period of the wind's direction
wobble, right where the spar swings fastest — with the peak at 4,0× the median movement (16,6× in
the test's own scenario). It is the same missing physics as the flag, not a trim problem: ruled
out by measuring were the trim (it sweeps a smooth 5° at 1,2 °/s while the tug is 9× faster than
the spar), the hull bob (removing it changed 0,041 to 0,034) and the forestay capsule (removing
it gave numbers identical to five decimals). `flameo_por_desventa`, scaled by `1 - factor_viento()`
— the very number the hull propels itself with and the audio fires its canvas cracks from, so the
three cannot contradict each other — takes the peak to 1,8× with the stretch untouched.

**Each cloth's wind area must govern only ITS cloth.** Every `TelaFisica` builds its own 30 m
`Area3D` with `SPACE_OVERRIDE_REPLACE` and priority 10, so on one ship three of them cover all
three cloths — and with REPLACE at equal priority exactly one wins, whichever the engine
processes last. Measured by giving one area at a time a gravity of 30 toward +X: the flag flew
0,56 m under the JIB's area and 0,22 m under its own. Its `empuje_viento`, its `peso_propio` and
its `flameo` were reaching nothing. Each cloth now takes a private layer bit (25-32, round
robin) **on top of** the one it had, and its area masks that bit alone.

**The orbital camera pivots at the ship's MID-HEIGHT, measured.** With the pivot at deck level,
zooming in framed the hull and cut the rig off at the top — the mast came out clipped and the flag
was off screen. `camara_orbital.mira_media_altura` unions the AABBs of the ship's own meshes
(skipping `SoftBody3D`, whose cloth lives in world space and says nothing about the ship's height)
and puts the pivot halfway up: 5,13 m of a measured 10,24 on the balandra. Measured, not a
constant, so the lancha and the goleta get their own.

**Cloth mesh density is matched to the jib, not chosen.** The mainsail carried **36,4 vertices
per m²** against the jib's 16,9 — twice as fine for no reason, and it is the cloth that costs, so
on 9 September 2026 it went from **1.217 to 613** points (18,3 per m², 25,1 cm of edge against the
jib's 31).

**The method matters: it is a regular quad grid, so `Decimate` is the wrong tool.** It would
triangulate and destroy the grid, and a `SoftBody` builds its links from that grid. `unsubdivide`
drops every other line and keeps it, and — because the surviving vertices are a SUBSET of the
originals — it keeps all four UV layers, `Col` and the skin weights untouched: measured, 0
incoherent corners, the R gradient still spanning 0-1 with its mean at 0,423 against 0,426, no
vertex left without weight, and **nothing had to be re-baked**. The anchors fall from 98 to 51,
proportionally, so the seams stay complete.

**What it does break is the curved leech**, and no distance measure of the interior shows it: the
alunamiento gets cut straight and loses **167 mm** of silhouette. Fixed by re-inserting only the
border vertices that stray more than 20 mm, placed exactly on the original point — **4 vertices**
take the maximum deviation from 167 to **13,5 mm** (mean 1,56, p95 7,61) with the area unchanged
(−0,06 %). The interior never strayed more than 13,5 mm even before that.

Measured gain, with the fps cap OFF: physics goes from 331-439 to **237 ms per second of game**,
and uncapped fps from 673-1.001 to **1.291**. Worth noting: at 60 Hz with the old mesh it cost
163-220 ms/s, so **the reduction very nearly paid for doubling the physics rate**. Stretch is
unchanged (0,002 mean, 0 edges past 25 %), so `rigidez` stays at the jib's 0,5 — the rule of
thumb that it should scale with edge length did not need applying.

**And never sample a cloth with a fixed step.** `relieve_del_pico` took 200 samples every 5 points,
reaching index 995: fine with 1.217 points, out of range with 613. `get_point_transform` past the
end does not abort — it returns zero and writes an error per sample per frame, so the suite went
from 75 s to over 280 with no failing assertion to point at it. Derive the step from the real
point count.

**The `Col` vertex-colour contract** (one RGBA layer; glTF exports no more):

| Channel | Meaning | Read by |
|---|---|---|
| R | how much the vertex moves (0 lashed, 1 free edge) | `TelaShader` (the shader) |
| G | this is a FLAG (> 0.5) | `TelaShader` |
| B | ANCHOR: sewn to the skeleton, does not fall | `TelaFisica` |

**Which sail is which is NOT the colour layer** — each cloth is its own node. And moving parts
(rudder, mast, spars) are identified by their BONE, not by colour: skin weights do export, and a
single colour layer cannot carry both a flat "I am sail" tag and the gradient the shader needs.

**Physical cloth must not be born during a stutter.** `TelaFisica` waits for a few consecutive
normal frames before building its `SoftBody3D`. At scene start there are frames of 0.12-0.14 s
(model load, shader compilation), and in one of those the engine runs ~7 physics steps back to
back while the anchors are only repositioned ONCE per frame, in `_process`: the cloth falls seven
steps with its anchor points frozen, tears away from the spar, and the solver never closes those
edges again. Measured on the balandra: one 0.122 s frame took the mainsail from 0 to 63 edges
stretched over 25 %, and there it stayed. This is why a ship respawned with TAB — born with the
game already running — used to come out clean while the one at startup did not.

**Watch the frame order:** cloth moves its own bones FIRST, then reads the resulting pose, then
places its anchors. Reversed, the anchors lag a frame behind the spar. `TelaFisica` enforces it
with the `_antes_de_pose` / `_tras_pose` hooks instead of relying on node order in the scene.

**Not every sail is a separate mesh.** In the lancha, barca and goleta the hull and the sail are
ONE mesh (`Mesh_0`, 444,835 verts in the lancha) and the red channel of `Col` decides what waves.
The balandra does bring each cloth as its own mesh. So a "sail" is defined by its rig, not by
being a separate piece of geometry.

**The flag is SHADER cloth, not a `SoftBody3D`** (9 September 2026). Its luff is stitched 54,8 mm
from the mast axis and the mast is 46 mm of radius there — **nine millimetres of clearance for a
960 mm sheet**. Bear away and the bone carries the luff round the pole, the free cloth lags and
ends up on the other side; once wrapped it does not come out until the ship stops. Measured on a
turn to leeward: from 0 points within 100 mm of the axis to 19, the deepest at 4 mm — inside the
timber — and 10-11 still stuck 5 s later. Ruled out by measuring, and not worth repeating: the
bone's slew rate, the mast capsule with and without it, the flutter, `empuje_viento` from 10 to
70, the whole solver (stiffness 0,3-0,95, precision 10-30, mass, drag: 104-108 mm flat) and the
physics rate (60/120/240/480 — which fixes the seam but not the wrap). A hard constraint pushing
the points out of the pole every step did run, pushed 7-9 per step, and the solver put them
straight back: the wrap is **topological**, there is cloth on the far side pulling them through.

With the shader it cannot happen by construction: the turn to leeward is **rigid and whole**, so
no cloth can be left on the far side. `TelaShader` already carried the flag branch — anchor and
rest direction come from the green channel of `Col`, which this mesh has at 1,000 on all 187
vertices — so no subclass was needed. `BanderaFisica` stays in the tree with a warning on it: its
own axis and pivot are correct, and it would serve a flag flown with CLEARANCE, on a staff or a
halyard 15-25 cm off the mast. Stitched to the pole, no.

**And it took two goes, because the shader had its OWN bug with the same symptom.** Both were
values calibrated for the lancha:

- the **axis** was the world vertical, and this mast rakes **9,4°**, so the flag coned instead of
  turning about the pole;
- the **pivot** was the anchor set back `0,15 × largo` — 10 cm on a sheet whose luff is 5,5 cm
  from the axis, so the centre of rotation fell on the **far side of the mast** and the flag swept
  a wide circle through the timber.

Both now come from the bone named by `TelaShader.bandera_hueso`: its origin gives the pivot (it
sits on the axis, 3 mm off) and its Y gives the axis, with nothing estimated. Watch one thing:
moving the pivot took `bandera_largo` from 0,69 to 1,155 m and inflated the whip 1,7x — for a
Rodrigues rotation any point on the axis serves as the pivot, but that same number scales the whip
amplitude, so the pivot and the sheet's fly are computed separately. The lancha has no flag bone
and keeps the vertical, unchanged.

**And with shader cloth you cannot measure the sheet from code**: the displacement happens in the
vertex shader and GDScript cannot read where a vertex ended up. The tests check the ORDER, not the
result — less coverage than the physical cloth had, and worth remembering. Of the flag's checks
only the apparent-wind one discriminates (28,6° with the true wind, fails; 0,0° with the
apparent); "points to leeward" with the ship stopped is near tautological, because
`direccion_de_vuelo()` turns the rest direction by the very angle computed to point at the wind.
The seam check moved to the MAINSAIL, which is still physical and had carried that defect
uncovered since September.

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

**The library is moving to glTF** (decided 6 September 2026): it now lives in
`fuentes/biblioteca/<pieza>.glb`, 20 pieces, and no longer as `.blend`. The reasoning is the
user's: these are finished prefabs, and modifying one is import/export — no reason to depend on
Blender files. **Still to settle:** self-contained `.glb` costs 168 MB because every piece embeds
its own copy of the shared tileable textures (`Rope001`, `madera_percha_h`), while `.gltf` + `.bin`
+ a common `tex/` is 17 MB for the same 0.63 MB of geometry. Two trial folders
(`fuentes/biblioteca_separado/`, `fuentes/biblioteca_jpeg/`) exist for comparison; delete them once
the format is chosen.

What glTF loses is **the quads, and only those** — dimensions come back identical. `Tris-to-Quads`
on reimport rebuilds the topology exactly on the barrel and ~97 % on mast and hatch, but not on
`cubierta` (236 ngons) or `cabo` (tubular). Keep those two `.blend` if their meshes may be re-edited.

**When authoring a piece, check `o.users_collection`.** Five of the eight original library
`.blend` files (`cabo`, `caja`, `escotilla`, `mastil`, `timon_balandra`) had their object saved
linked to no collection at all: nothing showed on opening them and any export came out empty. The
move to glTF rescued them.

The former layout was `fuentes/blend/biblioteca/<pieza>.blend`, one file per baked prop, with the
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
`scenes/{world,ship,character,ui}` group scenes by role; scripts are attached to scenes rather
than being colocated with `.tscn` files, and live in **one package per concern** —
`scripts/{barco,tela,camara,jugador,mundo}` — never loose in `scripts/`.
`assets/{models,textures,audio}` holds
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
  **origin at the centre of the bounding box**, no pending rotation or scale. `tex/` holds the
  loose maps the `.blend` packs (colour as JPEG, normal as 8-bit PNG — never a float buffer,
  which packs as OPEN_EXR and takes the file from 14 to 137 MB).

  The origin rule was "on the face you see" until 6 September 2026, and it produced two
  incompatible halves: the props baked one at a time sat on their base (barrel, crate, hatch,
  mast) or hung from their top (rudder, deck), while the twelve sets extracted from the
  balandra came out centred. **Centre of the box is now the single rule** — it is derived from
  the geometry with no per-piece judgement, so a script can enforce and verify it, which "the
  face you see" cannot (a rope loop or a set of shrouds has no such face). The seven pieces
  that were off were recentred in their `.blend` and re-exported; placing a barrel on deck now
  costs adding half its height.
- `fuentes/prompts_meshy.md` — the generation prompts, one per group of pieces, each with the
  ≤ 2 000-character version the image generator actually accepts.
- `blender_src/` — the pipeline scripts (`partes_barco.py`) and the `marcado_<barco>.json`
  files. `exportar_glb()` derives the `.glb` name from the `.blend` basename, so **renaming a
  `.blend` renames the asset Godot consumes**.
