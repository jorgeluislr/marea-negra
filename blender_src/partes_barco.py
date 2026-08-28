# partes_barco.py — Clasificación de las partes del barco y todo lo que se deriva de ella.
#
# POR QUÉ EXISTE: los modelos vienen de fotogrametría, con la geometría partida en cientos
# de trozos y sin ninguna semántica. Asignar pesos "adivinando" qué es cada cosa (por isla,
# por forma, por distancia) acierta en la mayoría de casos y falla justo en las uniones —y
# cada fallo se ve como una pieza que se retuerce o una cuerda que se rompe. La solución es
# marcar UNA VEZ qué es cada parte, y que todo lo demás salga de ahí.
#
# UNA SOLA FUENTE DE VERDAD: el atributo entero 'parte' (uno por vértice, 0 = sin
# clasificar). Es lo ÚNICO que se edita a mano. De él se derivan, por script:
#
#     atributo 'parte'  ──┬──►  capa de color 'Partes'   (solo para verlo)
#                         ├──►  grupos 'parte_*'         (para el panel de Blender)
#                         ├──►  capa de color 'Col'      (la que lee el shader de tela)
#                         └──►  pesos del esqueleto      (raiz / vela / driza / timon)
#
# Antes había tres marcados independientes sobre la misma malla —grupos, color y capa de
# tela— y había que cotejarlos entre sí para detectar incoherencias. Con una etiqueta entera
# por vértice, un vértice NO PUEDE estar en dos partes: los solapes son imposibles por
# construcción en vez de ser algo que hay que ir cazando.
#
# Ni el atributo 'parte' ni los grupos 'parte_*' se exportan al .glb (glTF solo exporta
# color, UV, huesos y pesos), así que no ensucian el modelo del juego.
#
# PROCEDIMIENTO, IGUAL EN TODOS LOS BARCOS:
#
#   1) Soldar la malla (remove_doubles a 1 mm, dejando sin coser las juntas deslizantes).
#      Sin soldar no hay camino entre trozos y los degradados salen partidos por tramos.
#   2) Marcar las partes. ES EL ÚNICO TRABAJO MANUAL:
#         Modo Edición -> seleccionar -> marcar_parte("casco")
#      Revisar con  ver()  y  seleccionar_parte("casco"), nunca con la selección naranja:
#      el contorno de objeto activo cubre los cabos finos y los hace parecer clasificados.
#   3) informe()  hasta que no quede nada sin clasificar.
#   4) procesar_barco()  ->  genera color, grupos, capa Col y TODOS los pesos; guarda el
#      marcado en JSON y verifica que ninguna parte fija lleve peso de un hueso móvil.
#   5) Exportar a .glb con  export_vertex_color='NAME',  export_vertex_color_name='Col'.

import bpy

# ───────────────── PARTES ─────────────────
# nombre: (color para verlo, regla de movimiento)
PARTES = {
    "casco":     ((0.55, 0.27, 0.07), "fija"),      # madera: no se deforma NUNCA
    "mastil":    ((0.90, 0.75, 0.10), "fija"),      # ídem, aunque la vela tire de él
    # La verga y la botavara van SEPARADAS a propósito: las dos giran al trimar, pero solo
    # la verga sube al izar. Con una sola parte "perchas" no habría regla posible.
    "verga":     ((0.85, 0.45, 0.05), "verga"),     # gira con la vela Y sube con la driza
    "botavara":  ((0.70, 0.35, 0.02), "botavara"),  # gira con la vela, no sube
    "vela":      ((0.95, 0.95, 0.90), "pano"),      # el paño: trimado + izado con degradado
    "bandera":   ((0.20, 0.35, 0.90), "fija"),      # la mueve el shader, no el esqueleto
    "timon":     ((0.85, 0.10, 0.10), "timon"),
    "estay":     ((0.10, 0.70, 0.20), "fija"),      # tope -> proa
    "obenques":  ((0.05, 0.45, 0.15), "fija"),      # tope -> bandas
    "driza":     ((0.10, 0.80, 0.85), "driza"),     # iza la verga
    "escotas":   ((0.95, 0.50, 0.10), "degradado"), # penol de botavara -> borda
    "brazas":    ((0.80, 0.15, 0.75), "degradado"), # penoles de la verga -> borda
    # Añadir partes SIEMPRE al final: el índice sale del orden y los enteros ya escritos
    # en las mallas dejarían de significar lo mismo.
    "contras":   ((0.95, 0.35, 0.55), "degradado"), # penol de botavara -> obenque
    # El foque de la balandra: segundo paño, en el estay de proa. Va con regla "fija" a
    # propósito y NO por descuido: un foque de verdad se caza con su propia escota y ondea
    # solo, pero eso pide un hueso y una regla que todavía no existen. Con "fija" se queda
    # quieto y correcto; lo que NO se puede es dejarlo sin regla, porque un vértice sin peso
    # de ningún hueso se desploma al origen de la armadura al exportar a glTF.
    "foque":     ((0.98, 0.85, 0.55), "fija"),
}

# El índice de cada parte en el atributo. NO reordenar PARTES sin regenerar el atributo:
# los enteros ya escritos en las mallas dejarían de significar lo mismo.
ORDEN = list(PARTES)

ATRIBUTO = "parte"          # INT por vértice: LA FUENTE DE VERDAD (0 = sin clasificar)
CAPA_PARTES = "Partes"      # color DERIVADO del atributo, solo para verlo
CAPA_TELA = "Col"           # color DERIVADO que lee el shader de tela
GRIS = (0.12, 0.12, 0.12, 1.0)


# ───────────────── ACCESO A LA MALLA ─────────────────

def _malla():
    """La malla del barco. No se fía del objeto activo: en cuanto se toca el esqueleto el
    activo pasa a ser la armadura, y todo fallaba con un error incomprensible
    ('Armature' object has no attribute 'vertices')."""
    # getattr: justo después de wm.open_mainfile el contexto no tiene 'object' todavía
    ob = getattr(bpy.context, "object", None)
    if ob is None:
        ob = bpy.context.view_layer.objects.active
    if ob is not None and ob.type == 'MESH':
        return ob, ob.data
    if ob is not None and ob.type == 'ARMATURE':
        for cand in bpy.data.objects:
            if cand.type == 'MESH' and any(m.type == 'ARMATURE' and m.object == ob
                                           for m in cand.modifiers):
                return cand, cand.data
    mallas = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if len(mallas) == 1:
        return mallas[0], mallas[0].data
    raise RuntimeError("No se identifica la malla del barco. Selecciónala. Hay: %s"
                       % ", ".join(o.name for o in mallas))


def _activar(ob):
    """Hace de 'ob' el objeto activo. Imprescindible antes de cualquier mode_set: los
    operadores de modo actúan sobre el ACTIVO, no sobre el objeto que se les pase. Con la
    armadura activa, un mode_set('EDIT') abre el editor de HUESOS y la selección de
    vértices no se ve: parece que la parte se ha quedado vacía sin estarlo."""
    if bpy.context.view_layer.objects.active is not ob:
        if bpy.context.object is not None and bpy.context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
        bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    return ob


def _a_objeto(ob):
    """Sale de Modo Edición. Obligatorio antes de leer atributos o pesos: en EDIT dan
    'IndexError: index 0 out of range, size 0'."""
    _activar(ob)
    if ob.mode == 'EDIT':
        bpy.ops.object.mode_set(mode='OBJECT')


def etiquetas(me=None):
    """El atributo 'parte' como array de numpy. Lo crea a 0 si no existe."""
    import numpy as np
    if me is None:
        _, me = _malla()
    # En Modo Edición los atributos están vacíos y foreach_get lanza un
    # 'sequence length mismatch given N, needed 0' que no dice nada de la causa real.
    ob = getattr(bpy.context, "object", None)
    if ob is not None and ob.data is me and ob.mode == 'EDIT':
        raise RuntimeError("No se pueden leer las etiquetas en Modo Edición: llama antes a "
                           "_a_objeto(ob), o lee los datos que necesites y selecciona después.")
    if ATRIBUTO not in me.attributes:
        me.attributes.new(name=ATRIBUTO, type='INT', domain='POINT')
    arr = np.zeros(len(me.vertices), dtype=np.int32)
    me.attributes[ATRIBUTO].data.foreach_get("value", arr)
    return arr


def _escribir_etiquetas(me, arr):
    if ATRIBUTO not in me.attributes:
        me.attributes.new(name=ATRIBUTO, type='INT', domain='POINT')
    me.attributes[ATRIBUTO].data.foreach_set("value", arr.tolist())
    me.update()


def _indice(nombre: str) -> int:
    if nombre not in PARTES:
        raise ValueError("Parte desconocida: %s. Válidas: %s" % (nombre, ", ".join(PARTES)))
    return ORDEN.index(nombre) + 1          # 0 queda reservado a "sin clasificar"


def _nombre(indice: int) -> str:
    return ORDEN[indice - 1] if 1 <= indice <= len(ORDEN) else ""


# ───────────────── EDICIÓN: lo único manual ─────────────────

def marcar_parte(nombre: str, solo_libres: bool = True) -> dict:
    """Asigna los vértices SELECCIONADOS a una parte y regenera color y grupos.

    Marca EXACTAMENTE la selección, sin filtros ni criterios propios: los límites que el
    usuario ajusta en pantalla son el dato válido. Los vértices que salen de la parte
    vuelven a 'sin clasificar', así que el color nunca miente sobre lo que hay.

    solo_libres=True (por defecto): RESPETA lo que ya está clasificado en otras partes y
    marca solo lo que está libre. Al seleccionar una pieza es inevitable rozar las vecinas
    ya cerradas —el mástil, el estay— y de hecho conviene pasarse un poco para que no quede
    ningún hueco entre dos partes; lo que no se puede es robárselas. Devuelve un informe de
    lo respetado, para poder revisarlo.

    solo_libres=False: reasigna a la fuerza. Solo para corregir a conciencia un límite
    entre dos partes."""
    import numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    sel = np.zeros(len(me.vertices), dtype=bool)
    me.vertices.foreach_get("select", sel)
    if not sel.any():
        raise RuntimeError("No hay vértices seleccionados.")

    idx = _indice(nombre)
    arr = etiquetas(me)
    antes = int((arr == idx).sum())

    ajenos = {}
    for otro in np.unique(arr[sel]):
        if int(otro) not in (0, idx):
            ajenos[_nombre(int(otro))] = int(((arr == otro) & sel).sum())
    if solo_libres:
        sel = sel & ((arr == 0) | (arr == idx))
        if not sel.any():
            raise RuntimeError("Toda la selección pertenece ya a otras partes: %s. "
                               "Usa solo_libres=False si de verdad quieres reasignarla."
                               % ", ".join(ajenos))

    arr[(arr == idx) & ~sel] = 0            # los que salen -> sin clasificar
    arr[sel] = idx                          # los seleccionados -> esta parte
    _escribir_etiquetas(me, arr)
    refrescar_color(me)
    sincronizar_grupos(ob, me)

    out = {"parte": nombre, "vertices": int((arr == idx).sum()), "antes": antes}
    if ajenos:
        out["respetados" if solo_libres else "reasignados_desde"] = ajenos
    return out


def limpiar_parte(nombre: str) -> dict:
    """Deja una parte sin clasificar. Para rehacerla desde cero."""
    import numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    arr = etiquetas(me)
    idx = _indice(nombre)
    n = int((arr == idx).sum())
    arr[arr == idx] = 0
    _escribir_etiquetas(me, arr)
    refrescar_color(me)
    sincronizar_grupos(ob, me)
    return {"parte": nombre, "vertices_liberados": n}


def seleccionar_parte(nombre: str) -> int:
    """Deja seleccionados los vértices de una parte, para revisarla o corregirla."""
    import numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    arr = etiquetas(me)
    sel = (arr == _indice(nombre))
    for p in me.polygons:
        p.select = False
    for e in me.edges:
        e.select = False
    me.vertices.foreach_set("select", sel.tolist())
    me.update()
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.context.tool_settings.mesh_select_mode = (True, False, False)
    return int(sel.sum())


def por_parte(nombre: str) -> list:
    """Índices de los vértices de una parte. Comparación exacta de enteros: sin
    tolerancias, al contrario que buscar por color."""
    import numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    return np.where(etiquetas(me) == _indice(nombre))[0].tolist()


# ───────────────── DERIVADOS ─────────────────

def refrescar_color(me=None) -> dict:
    """Repinta la capa 'Partes' desde el atributo. El color es una PROYECCIÓN del dato, no
    el dato: así no puede quedarse desfasado ni mentir."""
    import numpy as np
    if me is None:
        ob, me = _malla()
        _a_objeto(ob)
    if CAPA_PARTES not in me.color_attributes:
        me.color_attributes.new(name=CAPA_PARTES, type='FLOAT_COLOR', domain='POINT')
    arr = etiquetas(me)
    n = len(me.vertices)
    col = np.tile(np.array(GRIS, dtype=np.float32), (n, 1))
    cuenta = {}
    for nombre in PARTES:
        m = arr == _indice(nombre)
        if m.any():
            r, g, b = PARTES[nombre][0]
            col[m] = (r, g, b, 1.0)
            cuenta[nombre] = int(m.sum())
    me.color_attributes[CAPA_PARTES].data.foreach_set("color", col.ravel().tolist())
    me.update()
    return cuenta


def sincronizar_grupos(ob=None, me=None) -> dict:
    """Regenera los grupos 'parte_*' desde el atributo. Existen solo por comodidad —el
    panel de Blender sabe seleccionar por grupo— y son DERIVADOS: si alguien los edita a
    mano, la siguiente llamada los sobrescribe."""
    import numpy as np
    if ob is None or me is None:
        ob, me = _malla()
        _a_objeto(ob)
    arr = etiquetas(me)
    out = {}
    for nombre in PARTES:
        grupo = "parte_" + nombre
        ids = np.where(arr == _indice(nombre))[0].tolist()
        if grupo in ob.vertex_groups:
            ob.vertex_groups.remove(ob.vertex_groups[grupo])
        # El grupo se crea SIEMPRE, aunque esté vacío: así el panel de Blender muestra la
        # lista completa de partes desde el primer momento y se ve de un vistazo qué falta.
        # Antes solo aparecían las ya marcadas y al empezar un barco el panel salía vacío,
        # que parece que el marcado no está montado. Un grupo vacío no molesta: los
        # 'parte_*' no se exportan al .glb (glTF solo exporta los que son huesos).
        g = ob.vertex_groups.new(name=grupo)
        if ids:
            g.add(ids, 1.0, 'REPLACE')
        out[nombre] = len(ids)
    return out


def informe() -> dict:
    """Qué está clasificado y qué no. Lo que quede sin clasificar es lo que falta marcar."""
    import numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    arr = etiquetas(me)
    out = {"total": len(me.vertices), "sin_clasificar": int((arr == 0).sum())}
    for nombre in PARTES:
        n = int((arr == _indice(nombre)).sum())
        if n:
            out[nombre] = n
    desconocidas = sorted({int(v) for v in np.unique(arr)} - {0} -
                          {_indice(p) for p in PARTES})
    if desconocidas:
        # Pasa si se reordenó PARTES con mallas ya etiquetadas.
        out["etiquetas_desconocidas"] = desconocidas
    return out


def verificar(nombre: str) -> dict:
    """Contrasta una parte con los pesos del esqueleto. Una parte 'fija' cuyos vértices
    tengan peso en 'vela' o 'driza' se moverá al animar, por bien marcada que esté."""
    ob, me = _malla()
    _a_objeto(ob)
    ids = set(por_parte(nombre))
    huesos = {h: ob.vertex_groups[h].index for h in ("vela", "driza", "timon", "raiz")
              if h in ob.vertex_groups}
    fuera = {h: 0 for h in huesos}
    for v in me.vertices:
        if v.index not in ids:
            continue
        pesos = {g.group: g.weight for g in v.groups}
        for h, hi in huesos.items():
            if pesos.get(hi, 0.0) > 0.5:
                fuera[h] += 1
    return {"parte": nombre, "regla": PARTES[nombre][1], "vertices": len(ids),
            "con_peso_de_hueso": fuera}


def ver(capa: str = CAPA_PARTES, texturas: bool = False) -> dict:
    """Alterna la vista del viewport entre las dos capas de color, o vuelve a texturas.

        ver()               -> clasificación por partes
        ver("Col")          -> rojo de la tela, verde de la bandera
        ver(texturas=True)  -> el modelo normal

    Existe porque las dos capas conviven y es fácil creer que una se ha perdido cuando lo
    que se está mirando es la otra —o las texturas. Apaga además el contorno de objeto
    activo, que cubre por completo los cabos finos y los hace parecer clasificados."""
    ob, me = _malla()
    area = next(a for a in bpy.context.window.screen.areas if a.type == 'VIEW_3D')
    sd = area.spaces.active
    if texturas:
        sd.shading.type = 'SOLID'
        # 'TEXTURE', no 'MATERIAL': el segundo solo muestra el color base del material y
        # parece que las texturas se hayan perdido.
        sd.shading.color_type = 'TEXTURE'
        sd.shading.show_xray = False
        sd.overlay.show_outline_selected = True
        sd.overlay.show_overlays = True
        return {"viendo": "texturas"}
    if capa not in me.color_attributes:
        raise RuntimeError("No existe la capa %s. Hay: %s"
                           % (capa, ", ".join(me.color_attributes.keys())))
    me.color_attributes.active_color_index = list(me.color_attributes.keys()).index(capa)
    sd.shading.type = 'SOLID'
    sd.shading.color_type = 'VERTEX'
    sd.overlay.show_outline_selected = False
    sd.shading.show_xray = False
    return {"viendo": capa,
            "significa": "clasificación de partes" if capa == CAPA_PARTES
                         else "rojo = cuánto se mueve la tela, verde = bandera"}


# ───────────────── PERSISTENCIA ─────────────────

CARPETA_MARCADO = r"E:\Godot\Game3D\marea_negra\blender_src"


def ruta_marcado(barco: str = "") -> str:
    """Un fichero por barco, nombrado por su .blend. Sin esto, el segundo barco
    sobrescribiría el marcado del primero."""
    import os
    if not barco:
        barco = os.path.splitext(os.path.basename(bpy.data.filepath))[0] or "sin_nombre"
    return os.path.join(CARPETA_MARCADO, "marcado_%s.json" % barco)


def _huella(me) -> dict:
    """Identifica la topología. Si cambia, los índices de vértice ya no valen."""
    return {"vertices": len(me.vertices), "aristas": len(me.edges),
            "caras": len(me.polygons)}


def _a_rangos(indices) -> list:
    """[3,4,5,9,10] -> [[3,5],[9,10]]. Los vértices de una parte van en bloques contiguos,
    así que esto comprime el fichero de megabytes a kilobytes."""
    out = []
    for i in sorted(indices):
        i = int(i)
        if out and i == out[-1][1] + 1:
            out[-1][1] = i
        else:
            out.append([i, i])
    return out


def _de_rangos(rangos) -> list:
    return [i for a, b in rangos for i in range(a, b + 1)]


def guardar_marcado(ruta: str = "") -> dict:
    """Vuelca el atributo a JSON, con la huella de topología. El marcado vive en el .blend,
    pero un fichero aparte lo protege de un purge o de un archivo corrupto."""
    import json, numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    ruta = ruta or ruta_marcado()
    arr = etiquetas(me)
    datos = {"objeto": ob.name, "huella": _huella(me), "partes": {}}
    for nombre in PARTES:
        ids = np.where(arr == _indice(nombre))[0]
        if len(ids):
            datos["partes"][nombre] = {"n": int(len(ids)), "rangos": _a_rangos(ids)}
    # compacto a propósito: con indentación cada rango ocupa 4 líneas y el fichero se va
    # a megabytes. Sigue siendo JSON inspeccionable con cualquier herramienta.
    with open(ruta, "w", encoding="utf-8") as f:
        json.dump(datos, f, separators=(",", ":"))
    return {"ruta": ruta, "huella": datos["huella"],
            "partes": {k: v["n"] for k, v in datos["partes"].items()}}


def restaurar_marcado(ruta: str = "", forzar: bool = False) -> dict:
    """Rehace el atributo (y de ahí color y grupos) desde el JSON. Se niega si la topología
    cambió: restaurar índices sobre otra malla pinta piezas al azar. Soldar o decimar
    reindexa todo y ANULA el marcado guardado."""
    import json, numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    ruta = ruta or ruta_marcado()
    with open(ruta, encoding="utf-8") as f:
        datos = json.load(f)
    ahora, antes = _huella(me), datos["huella"]
    if ahora != antes and not forzar:
        return {"error": "la topología cambió: el marcado guardado no es aplicable",
                "guardado": antes, "actual": ahora,
                "que_hacer": "volver a marcar a mano, o forzar=True si sabes que los "
                             "índices siguen siendo los mismos"}
    arr = np.zeros(len(me.vertices), dtype=np.int32)
    hecho = {}
    for nombre, d in datos["partes"].items():
        if nombre not in PARTES:
            continue
        ids = _de_rangos(d["rangos"])
        arr[ids] = _indice(nombre)
        hecho[nombre] = len(ids)
    _escribir_etiquetas(me, arr)
    refrescar_color(me)
    sincronizar_grupos(ob, me)
    return {"restaurado": hecho, "huella": ahora}


def migrar_desde_grupos() -> dict:
    """Construye el atributo desde los grupos 'parte_*' que ya existan. Solo se usa una
    vez, al pasar del marcado por grupos al marcado por etiqueta."""
    import numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    arr = np.zeros(len(me.vertices), dtype=np.int32)
    solapes = {}
    for nombre in PARTES:
        grupo = "parte_" + nombre
        if grupo not in ob.vertex_groups:
            continue
        gi = ob.vertex_groups[grupo].index
        idx = _indice(nombre)
        for v in me.vertices:
            if any(g.group == gi and g.weight > 0.5 for g in v.groups):
                if arr[v.index] != 0 and arr[v.index] != idx:
                    clave = " + ".join(sorted((_nombre(int(arr[v.index])), nombre)))
                    solapes[clave] = solapes.get(clave, 0) + 1
                arr[v.index] = idx
    _escribir_etiquetas(me, arr)
    color = refrescar_color(me)
    grupos = sincronizar_grupos(ob, me)
    out = {"etiquetado": {k: v for k, v in color.items()},
           "grupos_regenerados": grupos, "sin_clasificar": int((arr == 0).sum())}
    if solapes:
        # Con grupos un vértice podía estar en dos partes; con etiqueta no. Gana la última
        # parte del orden de PARTES, y se avisa de cuántos vértices se han resuelto así.
        out["solapes_resueltos"] = solapes
    return out


# ═════════════ GENERACIÓN: capa de tela y pesos ═════════════
# La herramienta común es la DISTANCIA GEODÉSICA: distancia recorriendo las aristas de la
# malla, no en línea recta. Es lo que hace que los degradados salgan continuos —dos
# vértices que se tocan reciben valores casi iguales, estén en el trozo que estén— y la
# razón de que las cuerdas ya no se partan por tramos. Solo funciona sobre malla SOLDADA:
# sin soldar no hay camino entre trozos y la distancia sale infinita.
#
# Exponentes medidos contra el rojo pintado a mano en la lancha (error medio sobre 0..1):
#   bandera  k=1.0 (lineal)  -> 0.021
#   vela     k=0.5 (raíz)    -> 0.096
CURVA_TELA = {"bandera": 1.0, "vela": 0.5}

# Por parte con degradado: (hueso móvil, hueso fijo, partes móviles vecinas, partes fijas
# vecinas). El degradado va de 0 en el amarre fijo a 1 en el extremo móvil.
DEGRADADOS = {
    "escotas": ("vela",  "raiz", ("vela", "botavara", "verga"), ("casco",)),
    "brazas":  ("vela",  "raiz", ("verga", "vela"),             ("casco",)),
    # La contra amarra al obenque, no al casco. El obenque es 'fija' (raiz=1), así que la
    # regla es la misma que la escota; lo que cambia es DÓNDE está su extremo quieto, y el
    # generador lo localiza por contacto con la parte vecina que se declare aquí.
    "contras": ("vela",  "raiz", ("botavara",),                 ("obenques",)),
    "driza":   ("driza", "raiz", ("verga",),                    ("mastil",)),
}


def _geodesica(me, co, dominio: set, origen: set):
    """Distancia por la malla desde 'origen', moviéndose solo dentro de 'dominio'.
    Devuelve {indice: distancia}; los inalcanzables no aparecen."""
    import heapq
    from collections import defaultdict
    ady = defaultdict(list)
    for e in me.edges:
        a, b = int(e.vertices[0]), int(e.vertices[1])
        if a in dominio and b in dominio:
            d = ((co[a][0] - co[b][0]) ** 2 + (co[a][1] - co[b][1]) ** 2
                 + (co[a][2] - co[b][2]) ** 2) ** 0.5
            ady[a].append((b, d))
            ady[b].append((a, d))
    dist = {}
    h = []
    for o in origen:
        if o in dominio:
            dist[o] = 0.0
            h.append((0.0, o))
    heapq.heapify(h)
    INF = float("inf")
    while h:
        d, v = heapq.heappop(h)
        if d > dist.get(v, INF):
            continue
        for w, p in ady[v]:
            nd = d + p
            if nd < dist.get(w, INF):
                dist[w] = nd
                heapq.heappush(h, (nd, w))
    return dist


def _contacto(me, dentro: set, fuera: set) -> set:
    """Vértices de 'dentro' unidos por una arista a algún vértice de 'fuera'. Así se
    detectan los amarres sin que nadie los marque: un anclaje es, por definición, el sitio
    donde la tela toca la madera."""
    out = set()
    for e in me.edges:
        a, b = int(e.vertices[0]), int(e.vertices[1])
        if a in dentro and b in fuera:
            out.add(a)
        elif b in dentro and a in fuera:
            out.add(b)
    return out


def derivar_tela() -> dict:
    """Genera la capa 'Col' desde las partes: rojo = distancia al anclaje, verde = bandera.
    Sustituye al pintado a mano del degradado."""
    import numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    n = len(me.vertices)
    co = np.empty(n * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    arr = etiquetas(me)

    if CAPA_TELA not in me.color_attributes:
        me.color_attributes.new(name=CAPA_TELA, type='FLOAT_COLOR', domain='POINT')
    datos = me.color_attributes[CAPA_TELA].data

    fijas = set()
    for p in ("verga", "botavara", "mastil", "casco"):
        fijas |= set(np.where(arr == _indice(p))[0].tolist())

    out = {}
    for parte, k in CURVA_TELA.items():
        ids = set(np.where(arr == _indice(parte))[0].tolist())
        if not ids:
            out[parte] = "no marcada"
            continue
        ancla = _contacto(me, ids, fijas)
        if not ancla:
            out[parte] = "sin anclaje detectado: falta marcar la percha o el mastil"
            continue
        dist = _geodesica(me, co, ids, ancla)
        dmax = max(dist.values()) or 1.0
        es_bandera = 1.0 if parte == "bandera" else 0.0
        for i in ids:
            r = (dist.get(i, 0.0) / dmax) ** k
            c = datos[i].color
            datos[i].color = (r, es_bandera, c[2], 1.0)
        out[parte] = {"vertices": len(ids), "anclajes": len(ancla),
                      "sin_camino": len(ids) - len(dist),
                      "distancia_max_cm": round(dmax * 100, 1), "curva": k}
    me.update()
    return out


def aplicar_reglas() -> dict:
    """Genera los pesos del esqueleto desde las partes. Cada parte tiene una regla y de ahí
    sale su peso; nadie pinta pesos a mano.

    Regla de oro: poner peso 1 en un hueso NO basta, hay que QUITAR el de los demás. El
    motor normaliza, así que un vértice con dos huesos a 1 se queda a medio camino —es el
    fallo que desgarró la arboladura la primera vez que se montó el izado."""
    import numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    n = len(me.vertices)
    co = np.empty(n * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    arr = etiquetas(me)

    def ids_de(parte):
        return set(np.where(arr == _indice(parte))[0].tolist())

    armadura = next((m.object for m in ob.modifiers
                     if m.type == 'ARMATURE' and m.object), None)
    if armadura is None:
        raise RuntimeError("La malla no tiene modificador de armadura.")
    huesos = {b.name for b in armadura.data.bones}
    for h in huesos:
        if h not in ob.vertex_groups:
            ob.vertex_groups.new(name=h)

    def asignar(ids, pesos):
        """pesos = {hueso: valor} o {hueso: {indice: valor}}. Lo que no aparezca se QUITA."""
        ids = list(ids)
        for h in huesos:
            g = ob.vertex_groups[h]
            if h not in pesos:
                g.remove(ids)
                continue
            v = pesos[h]
            if isinstance(v, dict):
                for i in ids:
                    g.add([i], float(v.get(i, 0.0)), 'REPLACE')
            else:
                g.add(ids, float(v), 'REPLACE')

    out = {}
    simples = {"fija": {"raiz": 1.0}, "timon": {"timon": 1.0},
               "verga": {"driza": 1.0}, "botavara": {"vela": 1.0}}
    for parte, (_, regla) in PARTES.items():
        ids = ids_de(parte)
        if not ids or regla not in simples:
            continue
        pesos = {k: v for k, v in simples[regla].items() if k in huesos}
        if not pesos:
            out[parte] = "el esqueleto no tiene el hueso que pide la regla " + regla
            continue
        asignar(ids, pesos)
        out[parte] = {"vertices": len(ids), "regla": regla, "pesos": pesos}

    # El paño: degradado de la botavara (0) a la verga (1) por distancia geodésica DENTRO
    # del paño, no por altura.
    #
    # Con la altura, el borde cosido a cada percha no llega a 0 ni a 1 exactos —los vértices
    # de la costura están un poco por debajo del eje de la percha, así que salen con t ≈ 0,95
    # en vez de 1— y esa diferencia estira la costura: 38 mm medidos contra la verga y 23
    # contra la botavara. La geodésica los pone a 0 y a 1 por construcción, porque parte
    # justamente de esas costuras.
    pano, bot, verga = ids_de("vela"), ids_de("botavara"), ids_de("verga")
    if pano and bot and verga and {"vela", "driza"} <= huesos:
        z0 = float(np.mean([co[i][2] for i in bot]))
        z1 = float(np.mean([co[i][2] for i in verga]))
        borde_bajo = _contacto(me, pano, bot)
        borde_alto = _contacto(me, pano, verga)
        d_bajo = _geodesica(me, co, pano, borde_bajo) if borde_bajo else {}
        d_alto = _geodesica(me, co, pano, borde_alto) if borde_alto else {}
        t, fuente = {}, {"geodesica": 0, "costura": 0, "altura": 0}
        for i in pano:
            a, b = d_bajo.get(i), d_alto.get(i)
            # La pertenencia a una costura MANDA sobre todo lo demás. Un vértice cosido a la
            # botavara tiene que ir a 0 aunque también toque la verga: si toca las dos, la
            # suma de distancias es 0 y sin esta guarda caía al fallback por altura, que le
            # daba t = 0,024 y estiraba la costura 19 mm.
            if a == 0.0:
                t[i] = 0.0
                fuente["costura"] += 1
            elif b == 0.0:
                t[i] = 1.0
                fuente["costura"] += 1
            elif a is not None and b is not None and (a + b) > 1e-9:
                t[i] = a / (a + b)
                fuente["geodesica"] += 1
            else:
                # islas del paño que no alcanzan una de las dos costuras: se cae a la
                # altura, que es el criterio de siempre y no depende de la topología
                t[i] = (min(1.0, max(0.0, (co[i][2] - z0) / (z1 - z0)))
                        if abs(z1 - z0) > 1e-6 else 0.0)
                fuente["altura"] += 1
        asignar(pano, {"driza": t, "vela": {i: 1.0 - t[i] for i in pano}})
        out["vela"] = {"vertices": len(pano), "regla": "pano",
                       "costura_con_botavara": len(borde_bajo),
                       "costura_con_verga": len(borde_alto),
                       "por": fuente,
                       "z_botavara_cm": round(z0 * 100, 1),
                       "z_verga_cm": round(z1 * 100, 1)}
    elif pano:
        out["vela"] = "falta marcar botavara y/o verga: sin ellas no hay eje de izado"

    # Cuerdas con degradado: se resuelven por CADENAS, no parte por parte.
    #
    # Una escota puede venir partida en dos tramos por el amarre de una contra: el tramo de
    # arriba solo toca la botavara y el de abajo solo toca el casco, así que por separado
    # ninguno encuentra sus DOS extremos y el degradado sale como un escalón brusco en el
    # nudo (uno entero a 'vela', el otro entero a 'raiz'). La cadena real es
    # botavara -> escota corta -> nudo -> contra -> obenque, y el degradado tiene que
    # recorrerla completa. Uniendo por conectividad las cuerdas que se tocan, la geodésica
    # atraviesa el nudo y el reparto sale continuo.
    from collections import defaultdict as _dd
    parte_de = {}
    for p in DEGRADADOS:
        if {DEGRADADOS[p][0], DEGRADADOS[p][1]} <= huesos:
            for i in ids_de(p):
                parte_de[i] = p
        elif ids_de(p):
            out[p] = "faltan huesos %s/%s" % (DEGRADADOS[p][0], DEGRADADOS[p][1])
    if parte_de:
        dominio_total = set(parte_de)
        padre = {i: i for i in dominio_total}

        def _raiz(a):
            while padre[a] != a:
                padre[a] = padre[padre[a]]
                a = padre[a]
            return a

        for e in me.edges:
            a, b = int(e.vertices[0]), int(e.vertices[1])
            if a in dominio_total and b in dominio_total:
                ra, rb = _raiz(a), _raiz(b)
                if ra != rb:
                    padre[rb] = ra
        cadenas = _dd(list)
        for i in dominio_total:
            cadenas[_raiz(i)].append(i)

        informe_cadenas = []
        for vs in sorted(cadenas.values(), key=len, reverse=True):
            dom = set(vs)
            partes_en = sorted({parte_de[i] for i in vs})
            moviles, fijas_ = set(), set()
            for p in partes_en:
                for q in DEGRADADOS[p][2]:
                    moviles |= ids_de(q)
                for q in DEGRADADOS[p][3]:
                    fijas_ |= ids_de(q)
            a = _contacto(me, dom, moviles)
            b = _contacto(me, dom, fijas_)
            if not a or not b:
                informe_cadenas.append({"partes": partes_en, "vertices": len(vs),
                                        "error": "extremos no detectados (movil=%d, fijo=%d)"
                                                 % (len(a), len(b))})
                continue
            da = _geodesica(me, co, dom, a)
            db = _geodesica(me, co, dom, b)
            t = {}
            for i in vs:
                x, y = da.get(i), db.get(i)
                if x is None:
                    t[i] = 0.0
                elif y is None:
                    t[i] = 1.0
                else:
                    t[i] = y / (x + y) if (x + y) > 1e-9 else 1.0
            # el valor sale de la cadena, pero cada vértice usa los huesos de SU parte:
            # una cadena puede mezclar escota (vela/raiz) con driza (driza/raiz)
            for p in partes_en:
                ids_p = [i for i in vs if parte_de[i] == p]
                h_movil, h_fijo = DEGRADADOS[p][0], DEGRADADOS[p][1]
                asignar(ids_p, {h_movil: {i: t[i] for i in ids_p},
                                h_fijo: {i: 1.0 - t[i] for i in ids_p}})
            informe_cadenas.append({
                "partes": partes_en, "vertices": len(vs),
                "extremo_movil": len(a), "extremo_fijo": len(b),
                "t_min": round(min(t.values()), 3), "t_max": round(max(t.values()), 3)})
        out["cuerdas_por_cadena"] = informe_cadenas

    me.update()
    return out


def procesar_barco(guardar: bool = True) -> dict:
    """El procedimiento completo, idéntico en todos los barcos. Se ejecuta cuando el marcado
    de partes está terminado y confirmado.

        1) informe()          - queda algo sin clasificar?
        2) refrescar_color()  - color y grupos al dia
        3) derivar_tela()     - genera la capa Col
        4) aplicar_reglas()   - genera los pesos
        5) verificar()        - alguna parte fija con peso de un hueso movil?
        6) guardar_marcado()

    No hace falta comprobar solapes: con una etiqueta entera por vértice no pueden
    existir."""
    ob, me = _malla()
    _a_objeto(ob)
    out = {"informe": informe(),
           "color": refrescar_color(me),
           "grupos": sincronizar_grupos(ob, me),
           "tela": derivar_tela(),
           "pesos": aplicar_reglas()}
    out["verificacion"] = {p: verificar(p) for p in PARTES if por_parte(p)}
    if guardar:
        out["marcado"] = guardar_marcado()
    return out


def separar_costura(movil: str = "verga",
                    fijas: tuple = ("mastil", "estay", "obenques"),
                    destino: str = "mastil") -> dict:
    """Desconecta una pieza que se DESLIZA de las piezas fijas que la rodean.

    El problema: al soldar la malla, el racamento de la verga quedó compartiendo caras con
    el mástil. Si la verga sube 77 cm y el mástil no, esas caras se estiran 77 cm y salen
    como hilos larguísimos. No hay reparto de pesos ni de etiquetas que lo arregle: mover
    la frontera solo cambia el sitio donde se rompe. Hay que cortar la malla.

    Lo que NO funciona, comprobado:
      · `split_edges` sobre las aristas mixtas: duplica la arista pero deja los dos
        extremos unidos, y el número de aristas mixtas se dobla.
      · `vert_separate`: necesita dos abanicos de caras que repartir, y las aristas de
        borde (una sola cara) no tienen por dónde cortar.
      · `mesh.split` de las caras "puras" de un lado: las caras de costura mezclan las dos
        partes, quedan fuera de cualquier selección pura y siguen uniendo.

    Lo que sí: `bmesh.ops.split` sobre las caras de costura. Las desconecta del resto
    duplicando los vértices de su borde —la geometría se conserva íntegra, sin agujeros— y
    después la lámina se etiqueta como parte fija para que se quede quieta, igual que el
    racamento real, que no se mueve con la verga sino que desliza sobre el palo.

    CLAVE: los vértices de la lámina hay que leerlos del resultado de la operación, no
    capturarlos antes. Al separar, las caras se quedan con los vértices NUEVOS y los viejos
    siguen con el resto de la malla; etiquetar los viejos deja el corte a medias.

    Hay que llamarla DESPUÉS de cada cambio de etiquetas que toque esa frontera."""
    import bmesh
    import numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    antes_v, antes_c = len(me.vertices), len(me.polygons)

    i_movil = _indice(movil)
    i_dest = _indice(destino)
    idx_fijas = {_indice(p) for p in fijas}

    bm = bmesh.new()
    bm.from_mesh(me)
    capa = bm.verts.layers.int[ATRIBUTO]
    costura = [f for f in bm.faces
               if i_movil in {v[capa] for v in f.verts}
               and ({v[capa] for v in f.verts} & idx_fijas)]
    if not costura:
        bm.free()
        return {"costura": 0, "nota": "no hay caras que mezclen %s con %s"
                                      % (movil, "/".join(fijas))}
    geom = (list({v for f in costura for v in f.verts})
            + list({e for f in costura for e in f.edges}) + costura)
    res = bmesh.ops.split(bm, geom=geom, use_only_faces=False)

    lamina = {v for g in res["geom"] if isinstance(g, bmesh.types.BMFace) for v in g.verts}
    recolocados = 0
    for v in lamina:
        if v[capa] == i_movil:
            v[capa] = i_dest
            recolocados += 1
    bm.to_mesh(me)
    bm.free()
    me.update()
    refrescar_color(me)
    sincronizar_grupos(ob, me)

    arr = etiquetas(me)
    E = np.empty(len(me.edges) * 2, dtype=np.int32)
    me.edges.foreach_get("vertices", E)
    E = E.reshape(-1, 2)
    a_p, b_p = arr[E[:, 0]], arr[E[:, 1]]
    quedan = int((((a_p == i_movil) & np.isin(b_p, list(idx_fijas)))
                  | ((b_p == i_movil) & np.isin(a_p, list(idx_fijas)))).sum())
    return {"caras_de_costura": len(costura), "vertices_de_la_lamina": len(lamina),
            "recolocados_a_" + destino: recolocados,
            "vertices": {"antes": antes_v, "ahora": len(me.vertices)},
            "caras": {"antes": antes_c, "ahora": len(me.polygons)},
            "aristas_que_aun_unen": quedan}


def islas_de(nombre: str) -> list:
    """Tamaños de las componentes conexas de una parte, de mayor a menor. Una parte que
    debería ser una pieza y sale en 13 trozos indica que la malla no está cosida ahí."""
    import numpy as np
    from collections import defaultdict
    ob, me = _malla()
    _a_objeto(ob)
    arr = etiquetas(me)
    idx = _indice(nombre)
    suyos = set(np.where(arr == idx)[0].tolist())
    padre = {i: i for i in suyos}

    def raiz(a):
        while padre[a] != a:
            padre[a] = padre[padre[a]]
            a = padre[a]
        return a

    for e in me.edges:
        a, b = int(e.vertices[0]), int(e.vertices[1])
        if a in suyos and b in suyos:
            ra, rb = raiz(a), raiz(b)
            if ra != rb:
                padre[rb] = ra
    tam = defaultdict(int)
    for i in suyos:
        tam[raiz(i)] += 1
    return sorted(tam.values(), reverse=True)


def soldar_parte(nombre: str, dist: float = 0.001) -> dict:
    """Funde los vértices coincidentes DENTRO de una parte, para que quede en una sola isla.

    Restringido a los vértices de esa etiqueta: así no puede coser dos partes distintas ni
    deshacer una costura ya separada —las copias que dejó `separar_costura` tienen etiquetas
    diferentes, de modo que quedan fuera del merge aunque estén en la misma posición.

    EL UMBRAL NO PUEDE PASAR DEL GROSOR DE LA PIEZA. Los cabos de estos modelos miden 2-3 mm,
    así que 1 mm es seguro y 4 mm los DESTRUYE: funde los vértices de un lado del tubo con
    los del lado opuesto y el cabo se colapsa en una lámina. Medido en el estay: a 1 mm se
    funden 176 vértices (9 islas -> 5); a 4 mm se funden 6.894, el 77 % de la pieza.
    El bounding box NO lo detecta —cambió 1,6 mm— porque el colapso es hacia dentro; el
    indicador válido es cuántos vértices se funden.

    Y no hace falta para el rigging: islas separadas dentro de una misma parte se mueven
    igual (mismo peso) y no comparten aristas, así que nada puede estirarse entre ellas.
    Solo aporta en las partes con degradado geodésico (vela, escotas, contras, driza), donde
    la geodésica necesita un camino continuo.

    OJO: cambia el número de vértices, así que REINDEXA la malla y anula el JSON de marcado
    guardado. Hay que volver a llamar a guardar_marcado() después."""
    import bmesh
    import numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    antes_islas = islas_de(nombre)
    antes_v = len(me.vertices)
    idx = _indice(nombre)

    bm = bmesh.new()
    bm.from_mesh(me)
    capa = bm.verts.layers.int[ATRIBUTO]
    suyos = [v for v in bm.verts if v[capa] == idx]
    if not suyos:
        bm.free()
        return {"parte": nombre, "error": "no hay vértices con esa etiqueta"}
    bmesh.ops.remove_doubles(bm, verts=suyos, dist=dist)
    bm.to_mesh(me)
    bm.free()
    me.update()

    refrescar_color(me)
    sincronizar_grupos(ob, me)
    despues_islas = islas_de(nombre)
    return {"parte": nombre, "dist_mm": dist * 1000,
            "islas": {"antes": len(antes_islas), "ahora": len(despues_islas)},
            "mayores_antes": antes_islas[:6], "mayores_ahora": despues_islas[:6],
            "vertices_de_la_malla": {"antes": antes_v, "ahora": len(me.vertices),
                                     "fundidos": antes_v - len(me.vertices)},
            "vertices_de_la_parte": sum(despues_islas)}


CARPETA_MODELOS = r"E:\Godot\Game3D\marea_negra\assets\models"


def exportar_glb(ruta: str = "") -> dict:
    """Exporta malla + esqueleto a .glb con los ajustes correctos para el juego.

    Dos trampas que este wrapper evita, y que NO dan ningún error al fallar:

    1) Si la ARMADURA está oculta en el viewport, `select_set()` no tiene efecto sobre ella
       y `use_selection=True` la ignora en silencio: el .glb sale sin JOINTS_0, sin WEIGHTS_0
       y con `skins: []`. En Godot eso se ve como un barco que no se mueve en absoluto. Aquí
       se muestra temporalmente y se devuelve a su estado.
    2) El color hay que exportarlo por NOMBRE. Con la capa activa (que suele quedarse en
       'Partes' después de revisar el marcado) se exportaría la clasificación en lugar del
       degradado, y la vela dejaría de ondear sin que nada avise.

    Verificar siempre el resultado: el .glb debe traer COLOR_0, JOINTS_0 y WEIGHTS_0."""
    import os
    ob, me = _malla()
    _a_objeto(ob)
    arm = next((m.object for m in ob.modifiers
                if m.type == 'ARMATURE' and m.object), None)
    if arm is None:
        raise RuntimeError("La malla no tiene modificador de armadura: el .glb saldría sin "
                           "esqueleto.")
    if not ruta:
        barco = os.path.splitext(os.path.basename(bpy.data.filepath))[0] or "sin_nombre"
        ruta = os.path.join(CARPETA_MODELOS, barco + ".glb")

    oculta = arm.hide_get()
    arm.hide_set(False)
    if CAPA_TELA in me.color_attributes:
        me.color_attributes.active_color_index = list(me.color_attributes.keys()).index(CAPA_TELA)
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = ob
    try:
        bpy.ops.export_scene.gltf(
            filepath=ruta, export_format='GLB', use_selection=True,
            export_apply=False,                  # NO aplicar el modificador de armadura
            export_skins=True, export_rest_position_armature=True, export_normals=True,
            export_vertex_color='NAME', export_vertex_color_name=CAPA_TELA,
            export_all_vertex_colors=False,      # 'Partes' no debe salir
            export_attributes=False,             # el atributo 'parte' se queda en Blender
            export_yup=True)
    finally:
        arm.hide_set(oculta)                     # devolverla como estaba

    return {"ruta": ruta, "MB": round(os.path.getsize(ruta) / 1024 / 1024, 1),
            "armadura_estaba_oculta": oculta, "capa_de_color": CAPA_TELA,
            "siguiente": "godot --path . --headless --import  y luego el test de huesos"}


RUTA_SELECCION = r"E:\Godot\Game3D\marea_negra\blender_src\seleccion_temporal.json"


def guardar_seleccion(ruta: str = RUTA_SELECCION) -> dict:
    """Guarda la selección actual en disco, con la huella de topología.

    Existe porque el flujo de revisión ("muéstrame las islas una a una") sobrescribe la
    selección en cada paso: si no se ha guardado antes, la selección de partida del usuario
    se pierde y hay que pedirle que la repita. Llamar a esto ANTES de empezar a mostrar
    nada."""
    import json
    import numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    sel = np.zeros(len(me.vertices), dtype=bool)
    me.vertices.foreach_get("select", sel)
    ids = np.where(sel)[0]
    datos = {"huella": _huella(me), "n": int(len(ids)), "rangos": _a_rangos(ids)}
    with open(ruta, "w", encoding="utf-8") as f:
        json.dump(datos, f, separators=(",", ":"))
    return {"ruta": ruta, "vertices": int(len(ids))}


def restaurar_seleccion(ruta: str = RUTA_SELECCION) -> dict:
    """Devuelve a la malla una selección guardada. Se niega si la topología cambió."""
    import json
    import numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    with open(ruta, encoding="utf-8") as f:
        datos = json.load(f)
    if datos["huella"] != _huella(me):
        return {"error": "la topología cambió: la selección guardada no es aplicable",
                "guardado": datos["huella"], "actual": _huella(me)}
    ids = _de_rangos(datos["rangos"])
    sel = np.zeros(len(me.vertices), dtype=bool)
    sel[ids] = True
    for p in me.polygons:
        p.select = False
    for e in me.edges:
        e.select = False
    me.vertices.foreach_set("select", sel.tolist())
    me.update()
    return {"restaurados": len(ids)}


def sanear_tela() -> dict:
    """Pone la capa 'Col' a NEGRO en todo lo que no sea tela, y avisa de cuánto había.

    POR QUÉ HACE FALTA: Blender inicializa el color de los vértices NUEVOS a BLANCO, o sea
    rojo=1 y verde=1. Para el shader eso significa "soy bandera y me muevo al máximo", así
    que cualquier geometría que se añada a mano —un cilindro de relleno, un anillo extruido,
    una tapa— se pone a ondear como si fuera un paño. Y no da ningún error: simplemente se
    mueve algo que debería estar quieto.

    Antes esto pasaba desapercibido porque el shader exigía rojo > 0.001 para tocar un
    vértice; al corregir el gratil de la bandera (que necesita girar con rojo 0) esa guarda
    dejó de filtrar, y el fallo se hizo visible.

    Llamar SIEMPRE después de crear geometría, junto con aplicar_reglas()."""
    import numpy as np
    ob, me = _malla()
    _a_objeto(ob)
    if CAPA_TELA not in me.color_attributes:
        return {"nota": "no hay capa %s" % CAPA_TELA}
    n = len(me.vertices)
    buf = np.empty(n * 4)
    me.color_attributes[CAPA_TELA].data.foreach_get("color", buf)
    C = buf.reshape(n, 4)
    arr = etiquetas(me)
    es_tela = np.isin(arr, [_indice("vela"), _indice("bandera")])
    sucios = (~es_tela) & ((C[:, 0] > 0.001) | (C[:, 1] > 0.001))
    por_parte = {}
    for nombre in PARTES:
        k = int((sucios & (arr == _indice(nombre))).sum())
        if k:
            por_parte[nombre] = k
    C[sucios, 0] = 0.0
    C[sucios, 1] = 0.0
    me.color_attributes[CAPA_TELA].data.foreach_set("color", C.ravel().tolist())
    me.update()
    return {"vertices_limpiados": int(sucios.sum()), "por_parte": por_parte}
