"""Proyecta las cuatro referencias de Tripo sobre la malla y hornea el color.

QUE HACE  Toma el encaje que mide `registrar_referencias`, monta una proyeccion por vista
y las mezcla pesando cada una por lo de frente que ve a cada punto. El resultado se hornea
a la capa UV de Tripo y queda como textura de color del torso.

COMO SE PROYECTA, Y POR QUE ASI  No hace falta rasterizar a mano: una camara ortografica
es un mapeo lineal desde SU espacio local, asi que `Texture Coordinate > Object` apuntando
a un vacio colocado como la camara ya da las coordenadas, y un nodo `Mapping` las lleva al
cuadro de la imagen. Los coeficientes salen del ajuste medido:

    u = (s/O) * x_local + (0,5*s + c + tx) / RES
    v = (s/O) * y_local + 1 - (0,5*s + c + ty) / RES

con O la `ortho_scale` del render de registro, c = (RES-1)/2 y tx, ty el desplazamiento
ajustado, ya en pixeles del render. Cada vista lleva su propia s porque las imagenes de
Tripo no son consistentes entre si: van de 1,1659 a 1,2362, un 6 % de dispersion sobre una
figura rigida.

EL PESO DE CADA VISTA es max(0, N . d)^DUREZA, con d la direccion hacia la camara. Asi
cada punto lo pinta sobre todo la vista que lo ve mas de frente y las costuras se funden en
vez de cortarse. Se multiplica ademas por la mascara del sujeto -- el fondo de las
referencias es blanco, y sin la mascara ese blanco se proyecta sobre la silueta.

LO QUE ESTO NO HACE, y conviene saberlo antes de mirar el resultado:

- **No resuelve la oclusion.** El peso solo mira la normal, no si hay algo delante. Las
  trenzas caen sobre los hombros, asi que el hombro recibe pelo proyectado. Se arregla
  comparando profundidades por vista, y es el siguiente paso si molesta.
- **No arregla la cara.** El registro global da IoU 0,90-0,93 en el cuerpo pero la
  mandibula no casa: la referencia lleva barba pintada y la malla sale afeitada. La cabeza
  necesita su propio registro por rasgos.
- **La luz viene pintada** en las referencias (sombras bajo los pectorales, contraluz en
  los hombros) y se hornea con ella.
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import registrar_referencias as reg          # noqa: E402

ATLAS = 4096
DUREZA = 3.0        # exponente del peso; mas alto = cada vista manda mas en lo suyo
MARGEN = 16         # pixeles de sangrado fuera de cada isla UV


def _vaciar(nt):
    for n in list(nt.nodes):
        nt.nodes.remove(n)


def _rama_vista(nt, vacio, imagen, direccion, coef):
    """Una vista: color proyectado y su peso."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    tc.object = vacio
    map_ = nt.nodes.new("ShaderNodeMapping")
    map_.vector_type = "POINT"
    map_.inputs["Location"].default_value = (coef["bu"], coef["bv"], 0.0)
    map_.inputs["Scale"].default_value = (coef["ax"], coef["ay"], 1.0)
    nt.links.new(tc.outputs["Object"], map_.inputs["Vector"])

    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = imagen
    tex.extension = "CLIP"            # fuera del cuadro no hay imagen, y el alfa lo dice
    tex.interpolation = "Cubic"
    nt.links.new(map_.outputs["Vector"], tex.inputs["Vector"])

    # mascara del sujeto: el fondo de las referencias es blanco
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex.outputs["Color"], sep.inputs["Color"])
    m1 = nt.nodes.new("ShaderNodeMath")
    m1.operation = "MINIMUM"
    nt.links.new(sep.outputs[0], m1.inputs[0])
    nt.links.new(sep.outputs[1], m1.inputs[1])
    m2 = nt.nodes.new("ShaderNodeMath")
    m2.operation = "MINIMUM"
    nt.links.new(m1.outputs[0], m2.inputs[0])
    nt.links.new(sep.outputs[2], m2.inputs[1])
    fondo = nt.nodes.new("ShaderNodeMath")
    fondo.operation = "LESS_THAN"
    fondo.inputs[1].default_value = reg.FONDO
    nt.links.new(m2.outputs[0], fondo.inputs[0])

    dentro = nt.nodes.new("ShaderNodeMath")
    dentro.operation = "MULTIPLY"
    nt.links.new(fondo.outputs[0], dentro.inputs[0])
    nt.links.new(tex.outputs["Alpha"], dentro.inputs[1])

    # cuanto de frente ve esta camara a este punto
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = tuple(direccion)
    nt.links.new(geo.outputs["Normal"], dot.inputs[0])
    cara = nt.nodes.new("ShaderNodeMath")
    cara.operation = "MAXIMUM"
    cara.inputs[1].default_value = 0.0
    nt.links.new(dot.outputs["Value"], cara.inputs[0])
    dur = nt.nodes.new("ShaderNodeMath")
    dur.operation = "POWER"
    dur.inputs[1].default_value = DUREZA
    nt.links.new(cara.outputs[0], dur.inputs[0])

    peso = nt.nodes.new("ShaderNodeMath")
    peso.operation = "MULTIPLY"
    nt.links.new(dur.outputs[0], peso.inputs[0])
    nt.links.new(dentro.outputs[0], peso.inputs[1])

    pesado = nt.nodes.new("ShaderNodeVectorMath")
    pesado.operation = "SCALE"
    nt.links.new(tex.outputs["Color"], pesado.inputs[0])
    nt.links.new(peso.outputs[0], pesado.inputs["Scale"])
    return pesado.outputs["Vector"], peso.outputs["Value"]


def _suma(nt, salidas, vectorial):
    """Encadena sumas; ni Math ni Vector Math aceptan mas de dos entradas."""
    acc = salidas[0]
    for otra in salidas[1:]:
        n = nt.nodes.new("ShaderNodeVectorMath" if vectorial else "ShaderNodeMath")
        n.operation = "ADD"
        nt.links.new(acc, n.inputs[0])
        nt.links.new(otra, n.inputs[1])
        acc = n.outputs[0]
    return acc


def main(destino):
    encaje = reg.main(destino, solapados=False)
    print("")
    print("=== proyeccion ===")

    # la escena queda montada por el registro: misma malla, mismos ejes
    ob = [o for o in bpy.data.objects if o.type == "MESH"][0]
    ob.data.uv_layers.active = ob.data.uv_layers[0]
    centro = Vector(encaje["centro"])
    tam = encaje["tam"]
    O = encaje["ortho_scale"]
    RES = encaje["res"]
    c = (RES - 1) / 2.0
    factor = RES / encaje["busqueda"]

    mat = bpy.data.materials.new("proyectado")
    mat.use_nodes = True
    nt = mat.node_tree
    _vaciar(nt)
    ob.data.materials.clear()
    ob.data.materials.append(mat)

    colores, pesos = [], []
    for vista in sorted(encaje["vistas"]):
        v = encaje["vistas"][vista]
        direccion = reg.CAMARAS[v["camara"]]
        sx, sy = v["sx"], v["sy"]
        tx, ty = v["tx"] * factor, v["ty"] * factor
        coef = {
            "ax": sx / O,
            "ay": sy / O,
            "bu": (0.5 * sx + c + tx) / RES,
            "bv": 1.0 - (0.5 * sy + c + ty) / RES,
        }
        vacio = bpy.data.objects.new("proy_" + v["camara"], None)
        bpy.context.scene.collection.objects.link(vacio)
        vacio.location = centro + direccion * (tam * 3.0)
        vacio.rotation_euler = (-direccion).to_track_quat("-Z", "Y").to_euler()
        bpy.context.view_layer.update()

        ruta = os.path.join(reg.DESCARGAS, "multiview_%d_%s.jpeg" % (vista, reg.JUEGO))
        img = bpy.data.images.load(ruta)
        col, pes = _rama_vista(nt, vacio, img, direccion, coef)
        colores.append(col)
        pesos.append(pes)
        print(
            "  vista %d -> %-11s IoU %.3f   u = %.5f x %+.5f   v = %.5f y %+.5f"
            % (vista, v["camara"], v["iou"], coef["ax"], coef["bu"], coef["ay"], coef["bv"])
        )

    suma_c = _suma(nt, colores, True)
    suma_p = _suma(nt, pesos, False)
    seguro = nt.nodes.new("ShaderNodeMath")
    seguro.operation = "MAXIMUM"
    seguro.inputs[1].default_value = 1e-4          # sin esto, los huecos dividen por cero
    nt.links.new(suma_p, seguro.inputs[0])
    div = nt.nodes.new("ShaderNodeVectorMath")
    div.operation = "DIVIDE"
    nt.links.new(suma_c, div.inputs[0])
    for i in range(3):
        nt.links.new(seguro.outputs[0], div.inputs[1])

    emi = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(div.outputs["Vector"], emi.inputs["Color"])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(emi.outputs["Emission"], out.inputs["Surface"])

    atlas = bpy.data.images.new("capitan_torso_C", ATLAS, ATLAS)
    destino_nodo = nt.nodes.new("ShaderNodeTexImage")
    destino_nodo.image = atlas
    nt.nodes.active = destino_nodo
    destino_nodo.select = True

    esc = bpy.context.scene
    esc.render.engine = "CYCLES"
    esc.cycles.device = "CPU"
    esc.cycles.samples = 1                         # EMIT no tiene ruido que promediar
    esc.render.bake.margin = MARGEN
    esc.render.bake.use_clear = True
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    print("  horneando %d x %d ..." % (ATLAS, ATLAS))
    bpy.ops.object.bake(type="EMIT")

    px = np.array(atlas.pixels[:], dtype=np.float32).reshape(ATLAS, ATLAS, 4)
    pintado = px[:, :, :3].max(axis=2) > 1e-3
    print("  atlas con color: %.2f %% de los texeles" % (100.0 * pintado.mean()))

    os.makedirs(destino, exist_ok=True)
    ruta_png = os.path.join(destino, "capitan_torso_C.png")
    atlas.filepath_raw = ruta_png
    atlas.file_format = "PNG"
    atlas.save()
    print("  textura -> %s" % ruta_png)

    # material de mirar: la textura como color base, no como emision
    _vaciar(nt)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = atlas
    pri = nt.nodes.new("ShaderNodeBsdfPrincipled")
    pri.inputs["Roughness"].default_value = 0.65
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tex.outputs["Color"], pri.inputs["Base Color"])
    nt.links.new(pri.outputs["BSDF"], out.inputs["Surface"])
    atlas.pack()

    ruta_blend = os.path.join(destino, "torso_proyectado.blend")
    bpy.ops.wm.save_as_mainfile(filepath=ruta_blend)
    print("  blend -> %s" % ruta_blend)
    return ruta_blend


if __name__ == "__main__":
    main(sys.argv[-1])
