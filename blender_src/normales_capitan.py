"""Quita y vuelve a poner el mapa de normales del capitan en su material.

Por que hace falta: en Texture Paint el pincel escribe sobre la imagen del nodo ACTIVO,
y `capitan_horneado` tenia DOS nodos de imagen -- el color y las normales --, o sea dos
ranuras de pintura. Basta un horneado (que deja activo el ultimo nodo usado) o un clic
despistado para acabar pintando sobre `capitan_cabeza_N`, que no es un color sino una
direccion codificada en RGB: lo que se pinta ahi no se ve como pintura, se ve como
relieve torcido.

No se pueden fusionar en una sola imagen por lo mismo: son datos distintos. Lo que si se
puede es que mientras se pinta solo haya UNA ranura.

`quitar()` saca del material el nodo de la normal y el Normal Map; la imagen se queda en
el .blend (empaquetada y con fake user), no se pierde.
`poner()` los reconstruye tal cual, que es como tienen que estar para exportar a glTF --
Image Texture -> Normal Map -> Principled, sin grupos de nodos por medio, o el exportador
no reconoce el mapa.

**Hay que llamar a `poner()` antes de exportar a Godot.**
"""

import bpy

OBJETO = "cabeza_union"
IMAGEN_NORMAL = "capitan_cabeza_N"
UV = "bake"


def _material():
    return bpy.data.objects[OBJETO].data.materials[0]


def quitar():
    """Deja una sola ranura de pintura: el color."""
    mat = _material()
    nt = mat.node_tree
    for nom in ("Mapa de normales", "Normal Map", "BAKE_N"):
        n = nt.nodes.get(nom)
        if n:
            nt.nodes.remove(n)
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    c = nt.nodes["BAKE_C"]
    if not bsdf.inputs["Base Color"].links:
        nt.links.new(c.outputs["Color"], bsdf.inputs["Base Color"])
    for n in nt.nodes:
        n.select = False
    c.select = True
    nt.nodes.active = c
    mat.paint_active_slot = 0
    return [s.name for s in mat.texture_paint_images]


def poner():
    """Reconstruye el mapa de normales. Obligatorio antes de exportar."""
    mat = _material()
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')

    t = nt.nodes.get("BAKE_N")
    if t is None:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.name = t.label = "BAKE_N"
        t.location = (-900, -750)
    t.image = bpy.data.images[IMAGEN_NORMAL]
    t.image.colorspace_settings.name = 'Non-Color'   # una normal NO es un color

    nm = nt.nodes.get("Mapa de normales") or nt.nodes.get("Normal Map")
    if nm is None:
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.name = nm.label = "Mapa de normales"
        nm.location = (-500, -750)
    nm.uv_map = UV
    if not nm.inputs["Color"].links:
        nt.links.new(t.outputs["Color"], nm.inputs["Color"])
    if not bsdf.inputs["Normal"].links:
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])

    # al volver a haber dos nodos de imagen, dejar el COLOR como activo
    c = nt.nodes["BAKE_C"]
    for n in nt.nodes:
        n.select = False
    c.select = True
    nt.nodes.active = c
    mat.paint_active_slot = 0
    return [s.name for s in mat.texture_paint_images]
