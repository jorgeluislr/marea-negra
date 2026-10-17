"""Hornea el color y las normales de la cabeza del capitan a un atlas propio.

DESTINO  `cabeza_union` (la cabeza y el busto ya soldados, 7.939 verts / 8.470 caras)
ORIGEN   `cabeza` (967 k verts, textura 8192 de Meshy) y `Mesh_0` (el busto de Tripo)
SALIDA   fuentes/blend/capitan/tex/capitan_cabeza_C.png y _N.png, 4096, empaquetadas

El resultado medido: 0,23 % de pixeles negros dentro de la mascara UV, repartidos en
huecos sueltos -- ninguna cara queda mayoritariamente sin color.

SIETE COSAS QUE COSTARON, y ninguna se ve hasta que se mide:

1. **Las texturas fuente estaban perdidas.** Apuntaban a las carpetas `.fbm` que Blender
   genera al importar un FBX, dentro de Downloads, y ya no existian: las imagenes
   declaraban su tamano pero `has_data` era False. Se recuperan del `.glb` y del `.zip`
   originales a `fuentes/blend/capitan/tex` y se EMPAQUETAN, o se vuelven a perder.

2. **Ninguna capa UV heredada sirve para hornear.** Medido rasterizando las islas:
   `UVMap` cubre el 8,1 % del cuadro con el 73,5 % de lo usado solapado, y `Atributo`
   el 70 % con el 21,3 %. Hace falta una capa nueva. `smart_project` mas
   `average_islands_scale` y `pack_islands` dan 34,3 % de cobertura y 0,46 % de solape
   -- que suena poco, pero sobre 0,624 m2 de superficie a 4096 son **3,03 px/mm**.

3. **El objeto ORIGEN no puede compartir material con el DESTINO.** El nodo de imagen
   al que se hornea queda activo tambien en el origen y lo que sale es negro. Se le da
   al origen una copia del material sin los nodos `BAKE_*`.

4. **Origen y destino coincidentes**: la geometria del busto es la MISMA en los dos, y
   Cycles descarta ese impacto. 2 mm hacia dentro por la normal lo resuelven.

5. **El UV del busto se corrompio al unirlo a `cabeza_union`.** Esta es la que costo la
   sesion: el busto salia 98,3 % negro mientras el rostro y el pelo salian al 1,8 %. Con
   EL MISMO material, horneado sobre si mismo, `Mesh_0` da color de piel (media RGB
   0,52 / 0,33 / 0,21, 0 % negro) y la misma isla sacada de `cabeza_union` da 100 %
   negro. Al unir mallas, las capas UV se emparejan por nombre y el busto se quedo con
   coordenadas que no son las suyas. **Se hornea siempre desde los objetos ORIGINALES,
   nunca desde una isla recortada del destino.**

6. **La verificacion es por MATERIAL, no global.** El 26 % de negros del primer intento
   no decia nada; separado por ranura salio 2,3 / 1,8 / 98,3 y el culpable era evidente.

7. **Esta escena no tiene luces**, asi que un render de Cycles sale negro entero y no
   prueba nada sobre un material. Para comprobar si un material devuelve color, se
   hornea sobre si mismo con `use_selected_to_active = False`.

Y una que no es trampa sino convenio: las normales van en **OpenGL** (+X +Y +Z), que es
lo que lee Godot.
"""

import bpy
import bmesh
import numpy as np
from mathutils.bvhtree import BVHTree

TEX = r"E:\Godot\Game3D\marea_negra\fuentes\blend\capitan\tex"
DESTINO = "cabeza_union"
ALTA = "cabeza"          # 967 k verts: la cara, el pelo y las trenzas
BUSTO = "Mesh_0"         # el busto de Tripo, con SU UV -- el bueno
RES = 4096
EXTRUSION = 0.006        # p95 de separacion destino-origen: 2,87 mm
MAX_RAYO = 0.012


def uv_para_hornear(o, nombre="bake"):
    me = o.data
    if nombre in me.uv_layers:
        me.uv_layers.remove(me.uv_layers[nombre])
    me.uv_layers.active = me.uv_layers.new(name=nombre)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.1519, island_margin=0.003,
                             area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.context.scene.tool_settings.use_uv_select_sync = True
    bpy.ops.uv.average_islands_scale()
    bpy.ops.uv.pack_islands(rotate=True, margin=0.0025, shape_method='CONCAVE', scale=True)
    bpy.ops.object.mode_set(mode='OBJECT')
    me.uv_layers[nombre].active_render = True
    return me.uv_layers[nombre]


def origen_del_busto():
    """Copia de `Mesh_0` -- con su UV, que es el unico bueno -- 2 mm hacia dentro."""
    dest = bpy.data.objects[DESTINO]
    v = bpy.data.objects.get("busto_origen")
    if v:
        m = v.data
        bpy.data.objects.remove(v, do_unlink=True)
        if m and m.users == 0:
            bpy.data.meshes.remove(m)

    src = bpy.data.objects[BUSTO]
    malla = src.data.copy()
    malla.name = "busto_origen"
    o = bpy.data.objects.new("busto_origen", malla)
    o.matrix_world = src.matrix_world
    bpy.context.scene.collection.objects.link(o)

    # orientar sus caras como las de la MISMA zona en el destino
    ref = bmesh.new()
    ref.from_mesh(dest.data)
    bmesh.ops.delete(ref, geom=[f for f in ref.faces if f.material_index != 2], context='FACES')
    ref.transform(dest.matrix_world)
    ref.faces.ensure_lookup_table()
    bvh = BVHTree.FromBMesh(ref)
    normales = [f.normal.copy() for f in ref.faces]

    bm = bmesh.new()
    bm.from_mesh(malla)
    bm.transform(o.matrix_world)
    bm.normal_update()
    malas = []
    for f in bm.faces:
        loc, nor, idx, d = bvh.find_nearest(f.calc_center_median())
        if idx is not None and f.normal.dot(normales[idx]) < 0:
            malas.append(f)
    bmesh.ops.reverse_faces(bm, faces=malas)
    bm.normal_update()
    for v in bm.verts:
        v.co -= v.normal * 0.002      # ver punto 4 de la cabecera
    bm.transform(o.matrix_world.inverted())
    bm.to_mesh(malla)
    bm.free()
    ref.free()
    malla.update()
    malla.uv_layers.active = malla.uv_layers["Atributo"]

    # material propio: el origen no puede compartirlo con el destino (punto 3)
    for i, m in enumerate(malla.materials):
        if m and m in list(dest.data.materials):
            c = bpy.data.materials.get(m.name + "_src") or m.copy()
            c.name = m.name + "_src"
            for n in list(c.node_tree.nodes):
                if n.name in ("BAKE_C", "BAKE_N"):
                    c.node_tree.nodes.remove(n)
            malla.materials[i] = c
    return o


def negros_por_material(o, imagen):
    """Pixeles sin color DENTRO de la mascara UV, separados por ranura (punto 6)."""
    me = o.data
    N = imagen.size[0]
    px = np.empty(N * N * 4, dtype=np.float32)
    imagen.pixels.foreach_get(px)
    px = px.reshape(N, N, 4)
    negro = (px[:, :, 3] > 0.5) & (px[:, :, :3].max(axis=2) < 0.02)
    del px

    uv = np.empty(len(me.loops) * 2, dtype=np.float32)
    me.uv_layers["bake"].data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    mi = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("material_index", mi)

    por = {}
    for i, p in enumerate(me.polygons):
        li = list(p.loop_indices)
        pts = uv[li]
        tot = neg = 0
        for k in range(1, len(li) - 1):
            tri = pts[[0, k, k + 1]]
            x0 = max(0, int(np.floor(tri[:, 0].min() * N)))
            x1 = min(N - 1, int(np.ceil(tri[:, 0].max() * N)))
            y0 = max(0, int(np.floor(tri[:, 1].min() * N)))
            y1 = min(N - 1, int(np.ceil(tri[:, 1].max() * N)))
            if x1 < x0 or y1 < y0:
                continue
            X, Y = np.meshgrid((np.arange(x0, x1 + 1) + 0.5) / N,
                               (np.arange(y0, y1 + 1) + 0.5) / N)
            ax, ay = tri[0]
            bx, by = tri[1]
            cx, cy = tri[2]
            d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(d) < 1e-12:
                continue
            l1 = ((by - cy) * (X - cx) + (cx - bx) * (Y - cy)) / d
            l2 = ((cy - ay) * (X - cx) + (ax - cx) * (Y - cy)) / d
            m = (l1 >= 0) & (l2 >= 0) & (l1 + l2 <= 1)
            tot += int(m.sum())
            neg += int(negro[y0:y1 + 1, x0:x1 + 1][m].sum())
        a = por.setdefault(int(mi[i]), [0, 0])
        a[0] += tot
        a[1] += neg
    return {me.materials[k].name: {"px": v[0], "negros": v[1],
                                   "pct": round(100.0 * v[1] / max(1, v[0]), 2)}
            for k, v in sorted(por.items())}
