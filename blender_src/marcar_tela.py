# marcar_tela.py — Marca como TELA los vértices SELECCIONADOS de una malla, sin cortarla.
#
# IDEA: un único modelo. Tú seleccionas en Modo Edición los vértices de la vela (o la
# bandera). Este script les pinta un "peso de movimiento" en el canal ROJO:
#     rojo = 0  en el borde AMARRADO  (no se mueve)
#     rojo = 1  en el borde LIBRE     (ondea al máximo)
# TODO lo que NO seleccionas se queda en rojo = 0 → estático (casco, mástil, etc.).
#
# El shader de Godot hace:  desplazamiento *= COLOR.r   → solo la tela marcada ondea.
#
# USO:
#   1) Modo Edición (Tab). Selecciona los vértices de UNA vela (o la bandera).
#   2) Ajusta EJE_LIBRE: dirección (local) del borde AMARRADO hacia el borde LIBRE
#      de ESA vela (p. ej. amarrada al mástil a la izq. y libre a la der. -> (1,0,0)).
#   3) Ejecuta el script (pestaña Scripting -> Run).
#   4) Repite por cada vela / la bandera (es ACUMULATIVO: no borra lo ya marcado).
#   5) Exporta a .glb con "Vertex Colors" activado.
#
# Comprueba en Vertex Paint: la tela debe verse en degradado (amarre negro -> libre rojo),
# y el resto del barco, negro.

import bpy
from mathutils import Vector

# ─────────────────────────── CONFIG ───────────────────────────
# Dirección LOCAL que va del borde AMARRADO al borde LIBRE de la vela seleccionada.
#   Vela amarrada por la izquierda, libre a la derecha ......... ( 1, 0, 0)
#   Bandera amarrada al asta (-X), ondeando hacia +X .......... ( 1, 0, 0)
#   Vela colgada de una verga (arriba), libre abajo ........... ( 0,-1, 0)
EJE_LIBRE = Vector((1.0, 0.0, 0.0))

NOMBRE_CAPA = "Col"          # Color Attribute donde se guarda el peso (canal rojo)
GAMMA = 1.0                  # >1 = solo ondea cerca del borde libre ; <1 = ondea más superficie
BORRAR_OTRAS_CAPAS = True    # deja SOLO la capa 'Col' (evita que Godot lea la capa blanca de Meshy)
REINICIAR = True             # True = pone TODA la capa a 0 antes de marcar (empezar limpio, sin
                             # restos de marcados anteriores). Ponlo en False SOLO si vas a añadir
                             # más velas de forma acumulativa sobre un marcado ya bueno.
# ───────────────────────────────────────────────────────────────


def _asegurar_capa(mesh):
    # Borra otras capas de color (Meshy suele añadir una blanca que confunde a Godot).
    if BORRAR_OTRAS_CAPAS:
        for ca in list(mesh.color_attributes):
            if ca.name != NOMBRE_CAPA:
                print(f"    (borrada capa de color sobrante: '{ca.name}')")
                mesh.color_attributes.remove(ca)

    ca = mesh.color_attributes.get(NOMBRE_CAPA)
    recien_creada = False
    if ca is None or ca.domain != 'POINT':
        if ca is not None:
            mesh.color_attributes.remove(ca)
        mesh.color_attributes.new(name=NOMBRE_CAPA, type='FLOAT_COLOR', domain='POINT')
        recien_creada = True
    ca = mesh.color_attributes[NOMBRE_CAPA]

    # Poner todo a 0 (estático) antes de pintar: al crearla, o si REINICIAR (empezar limpio).
    if recien_creada or REINICIAR:
        for d in ca.data:
            d.color = (0.0, 0.0, 0.0, 1.0)
        print(f"    (capa '{NOMBRE_CAPA}' reiniciada a 0)")

    # Que Godot lea ESTA capa como color de vértice.
    mesh.color_attributes.active_color = ca
    try:
        for i, c in enumerate(mesh.color_attributes):
            if c.name == NOMBRE_CAPA:
                mesh.color_attributes.render_color_index = i
                break
    except Exception:
        pass
    return ca


def marcar(obj):
    if obj.type != 'MESH':
        print(f"  [saltado] {obj.name}: no es malla")
        return
    mesh = obj.data

    sel = [i for i, v in enumerate(mesh.vertices) if v.select]
    if not sel:
        print(f"  [saltado] {obj.name}: no hay vértices seleccionados. "
              f"Selecciona la vela en Modo Edición y vuelve a ejecutar.")
        return
    if len(sel) > 0.9 * len(mesh.vertices):
        print(f"  [aviso] {obj.name}: has seleccionado casi toda la malla "
              f"({len(sel)}/{len(mesh.vertices)}). ¿Seguro que es solo la vela?")

    ca = _asegurar_capa(mesh)
    if len(ca.data) != len(mesh.vertices):
        print(f"  [saltado] {obj.name}: capa de color no poblada "
              f"({len(ca.data)} vs {len(mesh.vertices)}). ¿Sigues en modo Edición?")
        return

    eje = EJE_LIBRE.normalized()
    proys = [mesh.vertices[i].co.dot(eje) for i in sel]  # proyección SOLO de la selección
    pmin, pmax = min(proys), max(proys)
    rango = max(1e-6, pmax - pmin)

    # Solo se escribe la selección; el resto de la malla conserva su valor (0 = estático).
    for k, i in enumerate(sel):
        t = (proys[k] - pmin) / rango          # 0 en amarre, 1 en libre
        peso = t ** GAMMA
        ca.data[i].color = (peso, 0.0, 0.0, 1.0)

    mesh.update()
    print(f"  [ok] {obj.name}: {len(sel)} vértices marcados como tela "
          f"(peso 0→1 a lo largo de {tuple(EJE_LIBRE)}).")


def main():
    # Los datos por vértice solo se escriben en MODO OBJETO. Al salir de Edición se
    # "vuelca" la selección a mesh.vertices[i].select, que es lo que leemos aquí.
    if bpy.context.mode != 'OBJECT':
        try:
            bpy.ops.object.mode_set(mode='OBJECT')
        except RuntimeError:
            print("marcar_tela: ponte en MODO OBJETO (Tab) tras seleccionar y reejecuta.")
            return

    seleccion = [o for o in bpy.context.selected_objects if o.type == 'MESH']
    if not seleccion and bpy.context.active_object:
        seleccion = [bpy.context.active_object]
    if not seleccion:
        print("marcar_tela: no hay malla activa.")
        return

    print(f"marcar_tela: procesando {len(seleccion)} objeto(s)…")
    for obj in seleccion:
        marcar(obj)
    print("Listo. Repite por cada vela/bandera (acumulativo) y exporta a .glb con Vertex Colors.")


main()
