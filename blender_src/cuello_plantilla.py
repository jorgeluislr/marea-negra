"""Trae el cuerpo de la plantilla CC0 de Blender Studio y lo deja colocado sobre el
capitan, como REFERENCIA para retopologizar el cuello. No une ni modifica nada.

Por que hace falta: la cabeza del capitan no tiene cuello -- por debajo de z ~ 1,56 lo
unico que baja son las trenzas, hasta 1,28 -- y el busto de Tripo llega hasta z = 1,6133
con el borde abierto. El tubo que va de uno a otro hay que construirlo, y la plantilla
trae ese cuello en quads con sus bucles ya puestos.

COMO SE DIMENSIONA, y las dos trampas:

1. La ALTURA sale sola. Se lleva la plantilla a 1,80 m con los pies en z = 0 y encaja,
   porque la cabeza del capitan ya esta en su altura antropometrica. Comprobado, no
   supuesto:

       menton       capitan 1,5582   plantilla 1,5501   ->  8 mm
       punta nariz          1,6391             1,6453   ->  6 mm
       coronilla            1,8001             1,8000   ->  0 mm

2. La PROFUNDIDAD no. La plantilla nace con el eje del cuerpo en y ~ 0 y el capitan vive
   con el suyo en y ~ -0,14: cabeza y busto estan adelantados en bloque, y sin corregirlo
   la cabeza queda 13 cm por delante del pecho. El desfase se mide franja a franja del
   torso contra el busto de Tripo, que es el que esta colocado bajo la cabeza, y sale
   constante: 140,3 mm en z = 1,44 y 135,1 en z = 1,48.

   NO se alinea por la nariz, que pedia 87 mm: esa cara se descarta al cortar y el capitan
   la tiene mas prominente. La prueba de que 135 es el bueno es el contorno del CUELLO,
   que es lo que se va a soldar -- el borde del busto de Tripo (z = 1,6133) va de
   y = -0,2030 a -0,0867 y el de la plantilla, ya movida, de -0,2206 a -0,0856.

Deja UN objeto, `cuerpo_plantilla`, entero y sin unir a nada. Llego a recortarse a la
franja del cuello (z 1,30 - 1,56) y no sirve: el corte cae justo donde hay que
retopologizar, asi que el cuerpo se entrega completo y se oculta lo que estorbe.
"""

import bpy
from mathutils import Vector

PLANTILLA = (r"E:\Godot\Game3D\marea_negra\fuentes\plantillas"
             r"\human-base-meshes-bundle-v1.4.1\human_base_meshes_bundle.blend")
OBJETO = "GEO-body_male_realistic"

ESTATURA = 1.80
AJUSTE = Vector((-0.0023, -0.1350, 0.0))   # medido (ver cabecera), no estimado


def _quitar(nombre):
    o = bpy.data.objects.get(nombre)
    if o:
        m = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if m and m.users == 0:
            bpy.data.meshes.remove(m)


def traer_cuerpo():
    """Cuerpo masculino realista, a 1,80 m, pies en z=0, centrado y en profundidad."""
    _quitar("cuerpo_plantilla")
    with bpy.data.libraries.load(PLANTILLA, link=False) as (src, dst):
        dst.objects = [OBJETO]
    o = dst.objects[0]
    bpy.context.scene.collection.objects.link(o)
    o.name = o.data.name = "cuerpo_plantilla"

    # el Multires a nivel 0 es la malla base; se retira sin aplicar nada
    for m in list(o.modifiers):
        o.modifiers.remove(m)

    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    vs = [v.co for v in o.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    f = ESTATURA / (mx.z - mn.z)
    cx = (mn.x + mx.x) / 2.0
    for v in o.data.vertices:
        v.co = Vector(((v.co.x - cx) * f + AJUSTE.x,
                       v.co.y * f + AJUSTE.y,
                       (v.co.z - mn.z) * f + AJUSTE.z))
    o.data.update()
    for p in o.data.polygons:
        p.use_smooth = True
    return o


if __name__ == "__main__":
    cuerpo = traer_cuerpo()
    print("cuerpo_plantilla: %d verts, %d caras"
          % (len(cuerpo.data.vertices), len(cuerpo.data.polygons)))
