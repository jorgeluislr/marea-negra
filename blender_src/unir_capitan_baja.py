"""Une las piezas del capitán en UNA malla y la exporta para rigar y animar en Meshy.

POR QUÉ UNA SOLA MALLA  El rigado automático de Meshy trabaja sobre un objeto: con siete
sueltos hay que subirlos uno a uno y cada uno sale con su propio esqueleto, que es
justamente lo que no se quiere.

LAS TRANSFORMACIONES SE APLICAN ANTES DE UNIR, y no es un detalle: la casaca y las piernas
llevan escala NO UNIFORME (0,689/0,779/0,689 y 0,481/0,545/0,476). `join` conserva la
transformación del objeto ACTIVO y recalcula las demás, así que uniendo sin aplicar, lo que
no es uniforme se deforma. Aplicando primero, cada vértice ya está donde debe.

LOS MATERIALES SE CONSERVAN, uno por pieza: cinco ranuras en la malla unida (botas y manos
comparten el suyo). Cada uno trae su color de 8192 y sus mapas de 4096, y eso pesa: por eso
se exporta con las imágenes en JPEG en vez de PNG, que es lo que decide si el archivo entra
en el límite de subida. Lo que se pierde es compresión sin pérdidas en mapas que ya vienen
de una foto; lo que se gana es poder subirlo.

NO se tocan las UVs. Cada pieza mantiene su propio despliegue y su propia textura, que es
lo correcto: son cinco atlas independientes, no uno compartido.
"""

import os
import sys

import bpy
import numpy as np

ORIGEN = r"E:\Godot\Game3D\marea_negra\fuentes\blend\capitan_baja.blend"
DESTINO = r"E:\Godot\Game3D\marea_negra\fuentes\blend\capitan_baja_unido"
NOMBRE = "capitan"


def main():
    os.makedirs(DESTINO, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=ORIGEN)

    piezas = [o for o in bpy.data.objects if o.type == "MESH"]
    piezas.sort(key=lambda o: -len(o.data.vertices))
    print("")
    print("=== piezas ===")
    for o in piezas:
        print("  %-10s verts %6d  escala %s" % (o.name, len(o.data.vertices),
                                                np.round(np.array(o.scale), 4)))

    # aplicar transformaciones: imprescindible con escalas no uniformes
    bpy.ops.object.select_all(action="DESELECT")
    for o in piezas:
        o.select_set(True)
    bpy.context.view_layer.objects.active = piezas[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    antes = sum(len(o.data.vertices) for o in piezas)
    bpy.ops.object.join()
    unido = bpy.context.active_object
    unido.name = NOMBRE
    unido.data.name = NOMBRE

    co = np.array([tuple(unido.matrix_world @ v.co) for v in unido.data.vertices])
    tri = sum(1 for p in unido.data.polygons if len(p.vertices) == 3)
    quad = sum(1 for p in unido.data.polygons if len(p.vertices) == 4)
    print("")
    print("=== unido ===")
    print("  verts %d (antes %d)  caras %d  tris %d quads %d"
          % (len(unido.data.vertices), antes, len(unido.data.polygons), tri, quad))
    print("  materiales: %s" % [ms.material.name for ms in unido.material_slots if ms.material])
    print("  capas UV: %s" % [u.name for u in unido.data.uv_layers])
    print("  caja: %s .. %s   estatura %.3f m"
          % (np.round(co.min(0), 3), np.round(co.max(0), 3), float(co[:, 2].max())))

    # el origen al centro de los pies, que es lo que espera un rig
    pies = co[co[:, 2] < co[:, 2].min() + 0.02]
    bpy.context.scene.cursor.location = (float(pies[:, 0].mean()),
                                         float(pies[:, 1].mean()), 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)

    for fmt, etq in (("JPEG", "jpg"), ("AUTO", "png")):
        ruta = os.path.join(DESTINO, "%s_%s.glb" % (NOMBRE, etq))
        bpy.ops.export_scene.gltf(
            filepath=ruta, export_format="GLB", use_selection=True,
            export_normals=True, export_texcoords=True, export_materials="EXPORT",
            export_image_format=fmt, export_yup=True,
        )
        print("  %-4s -> %s  (%.1f MB)" % (etq, ruta, os.path.getsize(ruta) / 1e6))

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(DESTINO, "capitan_unido.blend"))
    print("  blend -> %s" % os.path.join(DESTINO, "capitan_unido.blend"))


if __name__ == "__main__":
    main()
