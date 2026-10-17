"""Subdivide el torso de Tripo conservando sus UVs, y lo exporta para volver a Meshy.

Catmull-Clark vale aqui porque la malla es 86 % quads: interpola, no triangula, y las UVs
y los bordes marcados sobreviven -- se comprueba midiendolas antes y despues en vez de
suponerlo.

Lo que esto NO cambia, y conviene tenerlo claro antes de gastar creditos: la densidad de
textura. El atlas sigue siendo el mismo cuadro sobre la misma superficie, asi que los
2,59 px/mm de antes son los 2,59 px/mm de despues. Mas vertices dan una silueta mas
redonda, no mas detalle pintado.
"""

import math
import os
import sys

import bpy
import numpy as np

DESCARGAS = r"C:\Users\ASUS TUF\Downloads"
MALLA = os.path.join(DESCARGAS, "muscular man 3d model.fbx")
NIVELES = (1, 2)


def _medir(ob, etiqueta):
    me = ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    me.calc_loop_triangles()
    capa = me.uv_layers[0] if me.uv_layers else None
    if capa is None:
        print("  %-14s verts %7d  caras %7d  SIN UV" % (etiqueta, len(me.vertices), len(me.polygons)))
        return
    n = len(me.loop_triangles)
    uv = np.empty((n, 3, 2))
    wp = np.empty((n, 3, 3))
    co = np.array([v.co for v in me.vertices])
    for i, t in enumerate(me.loop_triangles):
        for j in range(3):
            uv[i, j] = capa.data[t.loops[j]].uv
            wp[i, j] = co[t.vertices[j]]
    a_uv = 0.5 * np.abs(np.cross(uv[:, 1] - uv[:, 0], uv[:, 2] - uv[:, 0]))
    a_w = 0.5 * np.linalg.norm(np.cross(wp[:, 1] - wp[:, 0], wp[:, 2] - wp[:, 0]), axis=1)
    ok = (a_w > 1e-12) & (a_uv > 1e-14)
    dens = np.sqrt((a_uv[ok] * 4096 * 4096) / (a_w[ok] * 1e6))
    quads = sum(1 for p in me.polygons if len(p.vertices) == 4)
    print(
        "  %-14s verts %7d  caras %7d (%4.1f %% quads)  UV %-10s  area UV %5.2f %%  "
        "superficie %.4f m2  %.2f px/mm"
        % (
            etiqueta,
            len(me.vertices),
            len(me.polygons),
            100.0 * quads / max(len(me.polygons), 1),
            capa.name,
            a_uv.sum() * 100,
            a_w.sum(),
            np.average(dens, weights=a_w[ok]),
        )
    )


def main(destino):
    os.makedirs(destino, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=MALLA)
    ob = [o for o in bpy.data.objects if o.type == "MESH"][0]
    ob.name = "torso_capitan"
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)

    print("")
    print("=== densidad y UVs, antes y despues ===")
    _medir(ob, "original")

    mod = ob.modifiers.new("subdividir", "SUBSURF")
    mod.subdivision_type = "CATMULL_CLARK"
    mod.use_creases = True
    mod.uv_smooth = "PRESERVE_BOUNDARIES"     # sin esto las islas se encogen por el borde

    salidas = []
    for nivel in NIVELES:
        mod.levels = nivel
        mod.render_levels = nivel
        bpy.context.view_layer.update()
        _medir(ob, "subdiv %d" % nivel)
        ruta = os.path.join(destino, "torso_capitan_subdiv%d.glb" % nivel)
        bpy.ops.export_scene.gltf(
            filepath=ruta,
            export_format="GLB",
            use_selection=True,
            export_apply=True,                # aplica el modificador al exportar
            export_normals=True,
            export_texcoords=True,
            export_materials="NONE",          # va sin textura: Meshy la pone
            export_yup=True,
        )
        salidas.append((nivel, ruta, os.path.getsize(ruta)))

    print("")
    for nivel, ruta, tam in salidas:
        print("  nivel %d -> %s  (%.1f MB)" % (nivel, ruta, tam / 1e6))


if __name__ == "__main__":
    main(sys.argv[-1])
