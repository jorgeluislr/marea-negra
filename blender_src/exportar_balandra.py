"""Exporta `balandra_piezas.blend` a `assets/models/balandra.glb`.

`partes_barco.exportar_glb()` no sirve para este barco: está escrita para un modelo de UNA
malla (usa `_malla()`), y la balandra son 124 objetos con una armadura común. Este módulo hace
lo propio de la balandra y **verifica el resultado**, porque ninguna de las tres trampas de
abajo da error al fallar.

Uso, con el `.blend` abierto:

    import exportar_balandra
    exportar_balandra.exportar()          # a assets/models/balandra.glb
    exportar_balandra.exportar("X.glb")   # a otro sitio, para comparar antes de sustituir

Las tres trampas, todas silenciosas:

1) **La armadura está oculta.** `select_set()` no hace nada sobre un objeto oculto y
   `use_selection=True` lo ignora sin avisar: el `.glb` sale sin `JOINTS_0`, sin `WEIGHTS_0` y
   con `skins: []`. En Godot es un barco que no mueve nada. Aquí se muestra y se devuelve a su
   estado. Lo mismo vale para cualquier malla oculta.

2) **La capa de color activa.** Hay que exportar `Col` por NOMBRE; con la capa activa (que
   suele quedarse en `Partes` tras revisar el marcado) se exportaría la clasificación en vez
   del degradado y las velas dejarían de ondear.

3) **Hay mallas que NO van dentro del casco.** El barril y la caja se sacaron del `.glb` el
   7-8 de septiembre de 2026 para que el juego los instancie como `Carga` desde su propio
   `.glb`; si viajan dentro, la cubierta sale con la carga DUPLICADA. Están en `FUERA`.
   Verificado: sin excluirlas el `.glb` trae 124 mallas y 147 primitivas contra las 121 y 139
   de producción.

La armadura tiene 8 huesos en Blender y el `.glb` trae 9: el exportador de glTF añade uno
(`neutral_bone`). No es un fallo, es lo esperado — 9 es el número bueno. (Era 7→8 hasta que se
añadió `collar_pico`, el hueso que desliza el collar de la garganta sin bascular con el pico.)
"""

import os

import bpy

CAPA_TELA = "Col"

# Mallas con modificador de armadura que aun asi NO se exportan (ver la trampa 3).
FUERA = {"barril", "caja.009", "gaza_cabo.002"}

CARPETA_MODELOS = r"E:\Godot\Game3D\marea_negra\assets\models"


def _piezas():
    """La armadura y las mallas que se exportan."""
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm is None:
        raise RuntimeError("No hay armadura en la escena: el .glb saldría sin esqueleto.")
    mallas = [o for o in bpy.data.objects
              if o.type == "MESH"
              and any(m.type == "ARMATURE" and m.object for m in o.modifiers)
              and o.data.name not in FUERA]
    if not mallas:
        raise RuntimeError("Ninguna malla tiene modificador de armadura.")
    return arm, mallas


def exportar(ruta: str = "") -> dict:
    """Exporta y devuelve el recuento para comprobarlo. Verificar SIEMPRE con `comprobar()`."""
    arm, mallas = _piezas()
    if not ruta:
        ruta = os.path.join(CARPETA_MODELOS, "balandra.glb")

    estado_arm = (arm.hide_get(), arm.hide_viewport)
    arm.hide_set(False)
    arm.hide_viewport = False
    estado = {}
    for o in mallas:
        estado[o.name] = (o.hide_get(), o.hide_viewport)
        o.hide_set(False)
        o.hide_viewport = False

    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in mallas:
        o.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = mallas[0]

    for o in mallas:                                  # trampa 2
        me = o.data
        if CAPA_TELA in me.color_attributes:
            me.color_attributes.active_color_index = \
                list(me.color_attributes.keys()).index(CAPA_TELA)

    try:
        bpy.ops.export_scene.gltf(
            filepath=ruta, export_format="GLB", use_selection=True,
            export_apply=False,                       # NO aplicar la armadura
            export_skins=True, export_rest_position_armature=True, export_normals=True,
            export_vertex_color="NAME", export_vertex_color_name=CAPA_TELA,
            export_all_vertex_colors=False,           # 'Partes' no debe salir
            export_attributes=False,                  # el atributo 'parte' se queda aquí
            export_yup=True)
    finally:
        arm.hide_set(estado_arm[0])
        arm.hide_viewport = estado_arm[1]
        for o in mallas:
            o.hide_set(estado[o.name][0])
            o.hide_viewport = estado[o.name][1]

    return {"ruta": ruta, "MB": round(os.path.getsize(ruta) / 1e6, 1),
            "mallas_exportadas": len(mallas), "excluidas": sorted(FUERA),
            "siguiente": "exportar_balandra.comprobar(ruta) y luego godot --headless --import"}


# Recuento de producción, medido sobre el .glb del 9 de septiembre de 2026 y reproducido por
# `exportar()`. Cuidado al contar mallas: hay NOMBRES REPETIDOS, así que un dict indexado por
# nombre da 121 en lugar de 124 y parece que faltan tres.
ESPERADO = {"mallas": 124, "primitivas": 139, "nodos": 134, "huesos": 9, "materiales": 15}


def comprobar(ruta: str = "", esperado: dict = None) -> dict:
    """Lee el .glb y contrasta su recuento con el de producción.

    Sirve para exportar a un archivo aparte y comprobarlo ANTES de sustituir el bueno, que es
    la única forma de no descubrir en Godot que falta el esqueleto o sobra la carga."""
    import json
    import struct
    if not ruta:
        ruta = os.path.join(CARPETA_MODELOS, "balandra.glb")
    esperado = esperado or ESPERADO
    with open(ruta, "rb") as f:
        struct.unpack("<III", f.read(12))
        largo, _ = struct.unpack("<II", f.read(8))
        j = json.loads(f.read(largo).decode("utf-8"))

    primitivas = sum(len(m["primitivos"] if "primitivos" in m else m["primitives"])
                     for m in j["meshes"])
    con_color = sorted(m.get("name") for m in j["meshes"]
                       for p in m["primitives"] if "COLOR_0" in p["attributes"])
    medido = {"mallas": len(j["meshes"]), "primitivas": primitivas,
              "nodos": len(j["nodes"]), "materiales": len(j["materials"]),
              "huesos": len(j["skins"][0]["joints"]) if j.get("skins") else 0}
    fallos = {k: (v, medido[k]) for k, v in esperado.items() if medido.get(k) != v}
    return {"ruta": ruta, "MB": round(os.path.getsize(ruta) / 1e6, 1), "medido": medido,
            "telas_con_Col": con_color,
            "fallos": fallos or None,
            "veredicto": "OK" if not fallos and len(con_color) == 3 else "REVISAR: no coincide"}
