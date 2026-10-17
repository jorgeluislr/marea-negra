"""Hornea el color de la alta de Meshy sobre la baja de Tripo, con sus propias UVs.

POR QUE ESTO PUEDE FUNCIONAR DONDE LA PROYECCION NO  Proyectar las cuatro referencias 2D
estiraba 194 px de cara para llenar unos 520 texeles -- 2,7x de ampliacion, y de ahi el
desenfoque. Aqui el origen es una malla con textura de 8192 sobre la misma superficie, asi
que hay detalle de sobra y el limite deja de ser la fuente.

LO QUE HAY QUE VIGILAR  Son generaciones DISTINTAS del mismo personaje, no una alta y su
retopologia. Medido con `comparar_alta_baja`, tras alinear: mediana 5,9 mm y p90 21,8 mm
sobre un busto de 1 m. La cabeza es donde mejor coinciden (mediana 3,6-4,3 mm) y el torso
donde peor (hasta 18,5). Eso obliga a una jaula generosa, y una jaula generosa es
exactamente lo que hace que un rayo cruce un hueco y traiga el color de otra parte -- axila,
entrecejo, entre trenzas. Por eso el rayo se limita: `cage_extrusion` para salir y
`max_ray_distance` para no ir mas lejos de lo que la medicion dice que hace falta.

El origen se pasa a EMISION, no a Principled: horneando EMIT lo que se recoge es el color
tal cual, sin que Cycles le sume iluminacion ni sombras propias.
"""

import os
import sys

import bpy
import numpy as np

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import comparar_alta_baja as cab             # noqa: E402

ATLAS = 4096
# La jaula tiene que sacar el origen del rayo FUERA de la alta, no solo separarlo de la
# baja: con 30 mm el pecho salia negro porque el rayo arrancaba dentro de la alta y se iba
# por la cara de atras. 60 mm pasa del p99 medido (36,5 mm) con holgura.
JAULA = 0.060
RAYO = 0.0             # 0 = sin tope; lo que acota es la jaula
MARGEN = 16


def _origen_a_emision(alta):
    """Deja la alta emitiendo su color base, que es lo que se quiere recoger."""
    mat = alta.data.materials[0]
    mat.use_nodes = True
    nt = mat.node_tree
    tex = None
    for n in nt.nodes:
        if n.type == "TEX_IMAGE" and n.image and n.image.size[0] >= 2048:
            if tex is None or n.image.size[0] > tex.image.size[0]:
                tex = n
    if tex is None:
        raise RuntimeError("la alta no trae textura de color")
    for n in list(nt.nodes):
        if n.type in {"BSDF_PRINCIPLED", "OUTPUT_MATERIAL", "EMISSION"}:
            nt.nodes.remove(n)
    emi = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tex.outputs["Color"], emi.inputs["Color"])
    nt.links.new(emi.outputs["Emission"], out.inputs["Surface"])
    return tex.image


def main(destino):
    os.makedirs(destino, exist_ok=True)
    baja, alta, alto, eje, puntos = cab.alinear()
    color = _origen_a_emision(alta)
    print("  textura de origen: %s  %d x %d" % (color.name, color.size[0], color.size[1]))

    baja.data.uv_layers.active = baja.data.uv_layers[0]
    col = bpy.data.images.new("capitan_torso_alta_C", ATLAS, ATLAS)
    nor = bpy.data.images.new("capitan_torso_alta_N", ATLAS, ATLAS, float_buffer=False,
                              is_data=True)
    nor.colorspace_settings.name = "Non-Color"

    mat = bpy.data.materials.new("horneado")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    n_col = nt.nodes.new("ShaderNodeTexImage")
    n_col.image = col
    n_nor = nt.nodes.new("ShaderNodeTexImage")
    n_nor.image = nor
    n_nor.interpolation = "Cubic"
    mapa = nt.nodes.new("ShaderNodeNormalMap")
    pri = nt.nodes.new("ShaderNodeBsdfPrincipled")
    pri.inputs["Roughness"].default_value = 0.65
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(n_col.outputs["Color"], pri.inputs["Base Color"])
    nt.links.new(n_nor.outputs["Color"], mapa.inputs["Color"])
    nt.links.new(mapa.outputs["Normal"], pri.inputs["Normal"])
    nt.links.new(pri.outputs["BSDF"], out.inputs["Surface"])
    baja.data.materials.clear()
    baja.data.materials.append(mat)

    esc = bpy.context.scene
    esc.render.engine = "CYCLES"
    esc.cycles.device = "CPU"
    esc.cycles.samples = 1
    b = esc.render.bake
    b.use_selected_to_active = True
    b.cage_extrusion = JAULA
    b.max_ray_distance = RAYO
    b.margin = MARGEN
    b.use_clear = True

    for o in bpy.data.objects:
        o.select_set(o in (alta, baja))
    bpy.context.view_layer.objects.active = baja

    # el nodo ACTIVO es el destino de cada horneado, asi que se cambia entre pasadas
    salidas = []
    for etiqueta, nodo, imagen, tipo in (
        ("color", n_col, col, "EMIT"),
        ("normales", n_nor, nor, "NORMAL"),
    ):
        nt.nodes.active = nodo
        for n in nt.nodes:
            n.select = n is nodo
        print("  horneando %s %d x %d desde %d caras ..."
              % (etiqueta, ATLAS, ATLAS, len(alta.data.polygons)))
        bpy.ops.object.bake(type=tipo)
        px = np.array(imagen.pixels[:], dtype=np.float32).reshape(ATLAS, ATLAS, 4)
        if tipo == "EMIT":
            util = px[:, :, :3].max(axis=2) > 1e-3
        else:
            # en tangente, lo no horneado se queda en el azul plano (0,5, 0,5, 1)
            util = np.abs(px[:, :, 0] - 0.5) + np.abs(px[:, :, 1] - 0.5) > 2e-3
        print("    texeles utiles: %.2f %%" % (100.0 * util.mean()))
        ruta = os.path.join(destino, imagen.name + ".png")
        imagen.filepath_raw = ruta
        imagen.file_format = "PNG"
        imagen.save()
        imagen.pack()
        salidas.append(ruta)
        print("    -> %s" % ruta)

    bpy.data.objects.remove(alta, do_unlink=True)      # el .blend pesaria 1,2 M de verts
    baja.name = "torso_capitan"
    ruta_blend = os.path.join(destino, "torso_horneado.blend")
    bpy.ops.wm.save_as_mainfile(filepath=ruta_blend)
    print("  blend -> %s" % ruta_blend)


if __name__ == "__main__":
    main(sys.argv[-1])
