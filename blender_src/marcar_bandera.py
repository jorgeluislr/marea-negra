# marcar_bandera.py — Marca los vértices SELECCIONADOS como BANDERA (canal VERDE=1)
# y les pone el gradiente de peso en el canal ROJO (0 en el amarre/izada -> 1 en el
# vuelo libre). NO toca el resto de la malla (la vela conserva su rojo y su verde=0).
#
# La bandera está amarrada por UN solo lado (a la driza/mástil) y ondea libre; por eso
# el shader la trata distinto que la vela: gira entera a sotavento y latiguea.
#
# USO:
#   1) Modo Edición (Tab). Selecciona SOLO los vértices de la bandera.
#   2) Ajusta EJE_LIBRE: dirección (local) del borde AMARRADO (izada, junto al mástil)
#      hacia el borde LIBRE (vuelo) de la bandera.
#   3) Ejecuta (pestaña Scripting -> Run).
#   4) Exporta el .glb con "Vertex Colors" activado (una sola capa 'Col').
#
# Requiere que ya exista la capa 'Col' (la de la vela). Solo escribe la SELECCIÓN.

import bpy
from mathutils import Vector

# ─────────────────────────── CONFIG ───────────────────────────
# Dirección LOCAL del amarre (izada, junto al mástil) hacia el vuelo libre de la bandera.
EJE_LIBRE = Vector((1.0, 0.0, 0.0))
NOMBRE_CAPA = "Col"
GAMMA = 1.0   # >1 = solo ondea cerca del vuelo ; <1 = ondea más superficie
# ───────────────────────────────────────────────────────────────


def main():
    obj = bpy.context.active_object
    if obj is None or obj.type != 'MESH':
        print("marcar_bandera: selecciona la malla y reejecuta.")
        return

    # La selección por vértice solo se lee bien en MODO OBJETO.
    if bpy.context.mode != 'OBJECT':
        try:
            bpy.ops.object.mode_set(mode='OBJECT')
        except RuntimeError:
            print("marcar_bandera: ponte en MODO OBJETO (Tab) tras seleccionar y reejecuta.")
            return

    mesh = obj.data
    ca = mesh.color_attributes.get(NOMBRE_CAPA)
    if ca is None:
        print("marcar_bandera: no existe la capa '%s'. Marca antes la vela "
              "(marcar_tela.py) para crearla y reejecuta." % NOMBRE_CAPA)
        return
    if ca.domain != 'POINT':
        print("marcar_bandera: la capa '%s' no es por VÉRTICE (POINT). "
              "Rehaz el marcado de tela." % NOMBRE_CAPA)
        return
    if len(ca.data) != len(mesh.vertices):
        print("marcar_bandera: capa de color no poblada (%d vs %d)."
              % (len(ca.data), len(mesh.vertices)))
        return

    sel = [i for i, v in enumerate(mesh.vertices) if v.select]
    if not sel:
        print("marcar_bandera: no hay vértices seleccionados. Selecciona la bandera "
              "en Modo Edición y reejecuta.")
        return
    if len(sel) > 0.9 * len(mesh.vertices):
        print("marcar_bandera: [aviso] seleccionaste casi toda la malla (%d/%d). "
              "¿Seguro que es solo la bandera?" % (len(sel), len(mesh.vertices)))

    eje = EJE_LIBRE.normalized()
    proys = [mesh.vertices[i].co.dot(eje) for i in sel]
    pmin, pmax = min(proys), max(proys)
    rango = max(1e-6, pmax - pmin)

    for k, i in enumerate(sel):
        t = (proys[k] - pmin) / rango       # 0 en la izada, 1 en el vuelo
        peso = t ** GAMMA
        c = ca.data[i].color
        # rojo = peso de movimiento ; verde = 1 (marca de bandera). Conserva B y A.
        ca.data[i].color = (peso, 1.0, c[2], c[3] if len(c) > 3 else 1.0)

    mesh.update()
    # Dejar 'Col' como activa/render para que Godot la lea.
    try:
        mesh.color_attributes.active_color = ca
    except Exception:
        pass
    print("marcar_bandera: [ok] %d vértices marcados como BANDERA (verde=1, rojo 0->1 "
          "a lo largo de %s). Exporta el .glb con Vertex Colors." % (len(sel), tuple(EJE_LIBRE)))


main()
