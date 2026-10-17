"""Recorta el torso dejando la cabeza y la cuna de pecho que la casaca deja ver.

PARA QUE  La textura se reparte por el area, no por lo que se mira: el torso entero son
1,96 m2 y a 4096 eso da 2,59 px/mm. Quitando lo que va debajo de la casaca, el mismo atlas
cae sobre mucha menos superficie. La ganancia va con la raiz del area que se quita, y el
script la imprime.

LA V  Vertice abajo, en el diafragma, y abierta hacia arriba hasta la base del cuello --
como cae una casaca abierta. Se define con fracciones de la altura del busto, para que
sirva en otro cuerpo sin volver a medir.

EL PELO NO SE TOCA, y lo que cuesta es reconocerlo. Las trenzas caen por debajo del cuello
y hacia atras, justo donde cae el corte. Dos maneras que NO valen, las dos probadas:

- **Por conectividad**: no son una isla. La malla principal se queda con 10.270 de los
  10.609 vertices, trenzas incluidas; las otras 12 islas son fragmentos de 24 a 46 verts.
- **Por grosor local** (rayo desde la cara hacia dentro, buscando el tubo fino de la
  trenza contra el macizo del cuerpo). La idea es buena y la medicion salio contaminada:
  con el origen del rayo pegado a su propia cara, el p25 daba 0,6 mm -- el rayo se golpeaba
  a si mismo -- y el corte resultante dejo el torso hecho jirones. Separando el origen 3 mm
  el reparto se arregla, pero sigue confundiendo pliegues y axilas con pelo.

Lo que SI vale es el COLOR: el pelo es negro y la piel es clara, y la textura ya esta
horneada sobre estas mismas UVs (`capitan_torso_alta_C.png`). Se mira la luminancia en el
centro UV de cada cara y el reparto sale en dos modas separadas. Es dato real de la pieza,
no una heuristica de forma.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np

ORIGEN = (
    r"E:\Godot\Game3D\marea_negra\fuentes\blend\capitan\proyeccion\torso_horneado.blend"
)

Z_DIAFRAGMA = 0.45      # vertice de la V, en fraccion de la altura del busto
ANCHO_CUELLO = 1.00     # semiancho de la V al llegar al escote, fraccion del semiancho
Z_ESCOTE = 0.76         # donde se abre la V del todo, fraccion de la altura
LUZ_PELO = 0.10         # por debajo de esta luminancia es pelo; sale del reparto medido

# Con ANCHO_CUELLO a 0,62 la V salia inservible: de las 2.765 caras que se borraban, solo
# 232 caian por la V -- las demas eran el dorso (1.385) y lo de debajo del diafragma
# (1.148) -- y aun asi el pecho desaparecia, porque la cuna quedaba como una tira estrecha
# bajo la barbilla. Contar POR REGLA es lo que lo desmonto; la superficie total no dice
# cual de las tres esta apretando.


def _luminancia_por_cara(ob, imagen):
    """Luminancia de la textura en el centro UV de cada cara."""
    w, h = imagen.size
    px = np.array(imagen.pixels[:], dtype=np.float32).reshape(h, w, 4)
    lum = 0.2126 * px[:, :, 0] + 0.7152 * px[:, :, 1] + 0.0722 * px[:, :, 2]
    capa = ob.data.uv_layers.active
    salida = np.empty(len(ob.data.polygons))
    for i, p in enumerate(ob.data.polygons):
        u = np.mean([capa.data[l].uv[0] for l in p.loop_indices])
        v = np.mean([capa.data[l].uv[1] for l in p.loop_indices])
        x = int(np.clip(u * (w - 1), 0, w - 1))
        y = int(np.clip(v * (h - 1), 0, h - 1))
        salida[i] = lum[y, x]
    return salida


def main(destino):
    os.makedirs(destino, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=ORIGEN)
    ob = [o for o in bpy.data.objects if o.type == "MESH"][0]
    ob.name = "torso_capitan_v"
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(rotation=True)      # a ejes de mundo, Z arriba

    imagen = next(i for i in bpy.data.images if i.size[0] >= 1024 and "_N" not in i.name)
    lum = _luminancia_por_cara(ob, imagen)

    print("")
    print("=== luminancia por cara (textura %s) ===" % imagen.name)
    bordes = [0.0, 0.03, 0.06, 0.10, 0.15, 0.25, 0.40, 0.60, 1.01]
    h_, _ = np.histogram(lum, bins=bordes)
    for i in range(len(h_)):
        print("  %.2f - %.2f : %6d caras" % (bordes[i], bordes[i + 1], h_[i]))
    pelo = lum < LUZ_PELO
    print("  -> pelo (< %.2f): %d caras de %d" % (LUZ_PELO, int(pelo.sum()), len(lum)))

    me = ob.data
    co = np.array([v.co for v in me.vertices])
    z0, z1 = float(co[:, 2].min()), float(co[:, 2].max())
    alto = z1 - z0
    semiancho = float(max(abs(co[:, 0].min()), abs(co[:, 0].max())))
    z_ap = z0 + Z_DIAFRAGMA * alto
    z_es = z0 + Z_ESCOTE * alto

    print("")
    print("  busto z %.4f..%.4f (alto %.4f, semiancho %.4f)" % (z0, z1, alto, semiancho))
    print("  V: vertice z %.4f, escote z %.4f, semiancho arriba %.4f"
          % (z_ap, z_es, ANCHO_CUELLO * semiancho))

    area_antes = sum(p.area for p in me.polygons)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    fuera = []
    for f in bm.faces:
        c = f.calc_center_median()
        if pelo[f.index]:                                  # trenza o barba: no se toca
            continue
        if c.z >= z_es:                                    # cabeza, cuello y hombros
            continue
        if f.normal.y >= 0.0:                              # dorso: lo tapa la casaca
            fuera.append(f)
            continue
        if c.z < z_ap:                                     # por debajo del diafragma
            fuera.append(f)
            continue
        t = (c.z - z_ap) / max(z_es - z_ap, 1e-9)          # 0 en el vertice, 1 en el escote
        if abs(c.x) > ANCHO_CUELLO * semiancho * t:
            fuera.append(f)
    bmesh.ops.delete(bm, geom=fuera, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")

    # fuera los pedazos sueltos: trozos que la textura dio por negros -- los huecos que el
    # horneado dejo sin pintar leen como pelo -- y que quedan flotando lejos de todo
    bm.faces.ensure_lookup_table()
    visto = set()
    sueltos = []
    for f0 in bm.faces:
        if f0.index in visto:
            continue
        pila, grupo = [f0], []
        visto.add(f0.index)
        while pila:
            f = pila.pop()
            grupo.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in visto:
                        visto.add(g.index)
                        pila.append(g)
        if len(grupo) < 40:
            sueltos.extend(grupo)
    if sueltos:
        print("  pedazos sueltos retirados: %d caras" % len(sueltos))
        bmesh.ops.delete(bm, geom=sueltos, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(me)
    bm.free()
    me.update()

    area_ahora = sum(p.area for p in me.polygons)
    k = math.sqrt(area_antes / max(area_ahora, 1e-9))
    print("")
    print("=== lo que se gana ===")
    print("  superficie %.4f -> %.4f m2  (%.1f %%)"
          % (area_antes, area_ahora, 100.0 * area_ahora / area_antes))
    print("  caras %d -> %d" % (len(fuera) + len(me.polygons), len(me.polygons)))
    print("  densidad a 4096: 2.59 -> %.2f px/mm  (x %.2f), REEMPAQUETANDO las UVs" % (2.59 * k, k))

    # sale limpio: el horneado solo hacia falta para reconocer el pelo
    me.materials.clear()
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)
    for i in list(bpy.data.images):
        if i.size[0]:
            bpy.data.images.remove(i)

    ruta = os.path.join(destino, "torso_capitan_v.glb")
    bpy.ops.export_scene.gltf(
        filepath=ruta, export_format="GLB", use_selection=True,
        export_normals=True, export_texcoords=True, export_materials="NONE",
        export_yup=True,
    )
    print("  -> %s (%.2f MB)" % (ruta, os.path.getsize(ruta) / 1e6))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(destino, "torso_capitan_v.blend"))


if __name__ == "__main__":
    main(sys.argv[-1])
