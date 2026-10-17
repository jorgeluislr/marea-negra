"""Monta el capitán en BAJA a partir de las cinco piezas de Meshy del 18-09-2026.

Mismo criterio que `montar_capitan.py` y por la misma razón: Meshy normaliza cada malla a
2 unidades en su eje mayor, así que ninguna comparte escala con las demás y la caja de casi
todas MIENTE — la de las manos y la de las botas contienen dos piezas lado a lado, la de la
cabeza incluye las trenzas, que cuelgan hasta el pecho, y la de la casaca la fijan las
bocamangas. Cada pieza se escala por una medida ANATÓMICA y se verifica midiendo.

    pieza                       verts   qué es
    0918230550                  8.441   la cabeza nuestra, texturizada por Meshy
    pirate_torso_coat_qua       8.448   torso con casaca, camisa, calzón y mangas
    pirate_legs_tris_low        2.448   piernas
    0918231017                  3.131   las dos botas
    0918231028                  2.191   las dos manos

24.659 vértices en total, contra los ~7 M del montaje de alta.

LA CASACA MANDA. Es la única pieza con una medida antropométrica limpia y grande — el ancho
de hombros — y de ella cuelgan las demás: el cuello de la cabeza al escote, las muñecas a
las bocamangas, las piernas al bajo del calzón y las botas al suelo. Escalar cada pieza
contra su propio canon y luego juntarlas es lo que en la alta dio un hombre de 2,05 m.

NO HAY SOMBRERO en este juego de piezas.
"""

import math
import os
import sys

import bpy
import numpy as np

PIEZAS_DIR = r"E:\Godot\Game3D\marea_negra\fuentes\blend\capitan\piezas_baja"
PIEZAS = {                      # trozo del nombre de archivo -> nombre en la escena
    "0918230550": "cabeza",
    "pirate_torso_coat_qua": "casaca",
    "pirate_legs_tris_low": "piernas",
    "0918231017": "botas",
    "0918231028": "manos",
}

ESTATURA = 1.80                 # a la coronilla, sin sombrero
HOMBROS_CASACA = 0.52           # ancho sobre la casaca, no sobre el cuerpo
MANO = 0.19                     # muñeca a dedo medio
CANA_BOTA = 0.45                # alto de la caña
ANCHO_CABEZA = 0.155            # biauricular de un varón de 1,80 m
ALTO_CADERA = 0.95              # del suelo a la cadera en un varón de 1,80 m


def mundo(o):
    me = o.data
    co = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    M = np.array(o.matrix_world)
    return co.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]


def banda(w, desde, hasta):
    """Vértices entre dos fracciones de la altura, contadas desde abajo."""
    z0, z1 = w[:, 2].min(), w[:, 2].max()
    h = z1 - z0
    return w[(w[:, 2] >= z0 + desde * h) & (w[:, 2] <= z0 + hasta * h)]


def escalar(o, f):
    o.scale = tuple(s * f for s in o.scale)
    bpy.context.view_layer.update()


def llevar(o, destino, ancla):
    p = ancla(mundo(o))
    o.location = tuple(o.location[i] + destino[i] - p[i] for i in range(3))
    bpy.context.view_layer.update()


def centrado_en_suelo(w):
    return np.array([(w[:, 0].min() + w[:, 0].max()) / 2,
                     (w[:, 1].min() + w[:, 1].max()) / 2,
                     w[:, 2].min()])


def importar():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    hallados = {}
    for raiz, _, ficheros in os.walk(PIEZAS_DIR):
        for f in ficheros:
            if not f.lower().endswith(".fbx"):
                continue
            for clave, nombre in PIEZAS.items():
                if clave in f:
                    antes = set(bpy.data.objects)
                    bpy.ops.import_scene.fbx(filepath=os.path.join(raiz, f))
                    nuevos = [o for o in set(bpy.data.objects) - antes if o.type == "MESH"]
                    ob = max(nuevos, key=lambda o: len(o.data.vertices))
                    for otro in nuevos:
                        if otro is not ob:
                            bpy.data.objects.remove(otro, do_unlink=True)
                    ob.name = nombre
                    # NO se pone la rotacion a cero: eso anula la conversion de ejes del
                    # importador y la casaca sale tumbada, con su eje largo en Y. Lo que se
                    # hace es medir cual es el eje vertical y levantarla si hace falta.
                    bpy.ops.object.select_all(action="DESELECT")
                    ob.select_set(True)
                    bpy.context.view_layer.objects.active = ob
                    bpy.ops.object.transform_apply(rotation=True, scale=False)
                    w = mundo(ob)
                    if int(np.argmax(w.max(0) - w.min(0))) == 1:      # el largo va en Y
                        ob.rotation_euler = (math.radians(90), 0.0, 0.0)
                        bpy.ops.object.transform_apply(rotation=True, scale=False)
                    hallados[nombre] = ob
    faltan = set(PIEZAS.values()) - set(hallados)
    if faltan:
        raise RuntimeError("faltan piezas: %s" % sorted(faltan))
    return hallados


def separar_pares(nombre):
    """Parte una pieza de dos (manos, botas) en sus islas izquierda y derecha."""
    ob = bpy.data.objects[nombre]
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.mesh.separate(type="LOOSE") if False else None
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    trozos = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    if len(trozos) < 2:
        return {nombre: ob}

    # Se agrupan por el SIGNO de x, no por tamaño. Quedarse con los dos trozos mayores
    # da las dos botas una encima de otra cuando una de ellas viene partida en varias
    # islas: los dos mayores salen de la MISMA bota. Aquí cada isla va al lado que le
    # toca y luego se unen, así que da igual en cuántos pedazos venga cada una.
    lados = {"der": [], "izq": []}
    for o in trozos:
        lados["izq" if mundo(o)[:, 0].mean() > 0 else "der"].append(o)
    salida = {}
    for lado, grupo in lados.items():
        if not grupo:
            continue
        grupo.sort(key=lambda o: -len(o.data.vertices))
        principal = grupo[0]
        if len(grupo) > 1:
            bpy.ops.object.select_all(action="DESELECT")
            for o in grupo:
                o.select_set(True)
            bpy.context.view_layer.objects.active = principal
            bpy.ops.object.join()
        principal.name = nombre[:-1] + "_" + lado
        salida[principal.name] = principal
    print("  %s -> %s (de %d islas)" % (nombre, sorted(salida), len(trozos)))
    return salida


def main():
    obs = importar()
    print("")
    print("=== piezas importadas ===")
    for n, o in sorted(obs.items()):
        w = mundo(o)
        print("  %-9s verts %6d  caja %s" % (n, len(o.data.vertices),
                                             np.round(w.max(0) - w.min(0), 4)))

    # --- 1. la casaca fija la escala de todo, por el ancho de HOMBROS
    cas = obs["casaca"]
    w = mundo(cas)
    hombros = np.ptp(banda(w, 0.88, 0.94)[:, 0])
    f_cas = HOMBROS_CASACA / hombros
    escalar(cas, f_cas)
    print("")
    print("  casaca: hombros %.4f u -> x%.4f para %.2f m" % (hombros, f_cas, HOMBROS_CASACA))

    # se apoya por su bajo, a la altura que le toca para una estatura de 1,80
    w = mundo(cas)
    alto_cas = np.ptp(w[:, 2])
    z_hombro = ESTATURA - 0.32                 # coronilla a hombro en un varón de 1,80
    z_bajo = z_hombro - alto_cas * 0.93        # el hombro cae al 93 % de la pieza
    llevar(cas, (0.0, 0.0, z_bajo), centrado_en_suelo)

    # --- 2. las botas, por la caña, con la suela en el suelo
    for nom, o in separar_pares("botas").items():
        escalar(o, CANA_BOTA / np.ptp(mundo(o)[:, 2]))
    b_izq, b_der = bpy.data.objects["bota_izq"], bpy.data.objects["bota_der"]

    # --- 3. las piernas, por su propia anatomía: de la cadera al suelo.
    #
    # NO se escalan contra el bajo de la casaca: ese bajo es el FALDÓN, que llega a media
    # pantorrilla, no el calzón. Midiéndolo así las piernas salían de 3 cm — se veía en que
    # la banda del tobillo recogía sus 2.448 vértices, o sea la pieza entera.
    # Van dentro de la casaca y de las botas; solo asoman entre el faldón y la caña.
    pier = obs["piernas"]
    escalar(pier, ALTO_CADERA / np.ptp(mundo(pier)[:, 2]))
    llevar(pier, (0.0, 0.0, 0.0), centrado_en_suelo)

    # Cada bota bajo su pernera. El reparto se hace por el punto MEDIO de los tobillos,
    # no por el signo de x: las perneras no están centradas en 0 y con el signo un lado
    # se quedaba sin puntos, la media salía vacía y las dos botas caían en el origen,
    # una encima de otra. Si aun así un lado queda vacío, se separan a una distancia de
    # postura normal en vez de apilarse.
    p = mundo(pier)
    tob = p[p[:, 2] < p[:, 2].min() + 0.06]
    corte = float(np.median(tob[:, 0])) if len(tob) else 0.0
    SEPARACION = 0.09          # media entreeje de tobillos, en metros
    for o, sel in ((b_izq, tob[:, 0] > corte), (b_der, tob[:, 0] <= corte)):
        if sel.sum() >= 3:
            c = tob[sel].mean(axis=0)
        else:
            signo = 1.0 if o is b_izq else -1.0
            c = np.array([corte + signo * SEPARACION, float(tob[:, 1].mean()), 0.0])
        llevar(o, (float(c[0]), float(c[1]), 0.0), centrado_en_suelo)
    print("  botas: corte x %.4f, tobillos %d puntos, centros %.3f y %.3f"
          % (corte, len(tob), mundo(b_izq)[:, 0].mean(), mundo(b_der)[:, 0].mean()))

    # --- 4. las manos, por la longitud muñeca-dedo, a la boca de cada manga
    for nom, o in separar_pares("manos").items():
        escalar(o, MANO / np.ptp(mundo(o)[:, 2]))
    w = mundo(cas)
    for lado, sel in (("izq", w[:, 0] > w[:, 0].max() - 0.04),
                      ("der", w[:, 0] < w[:, 0].min() + 0.04)):
        destino = w[sel].mean(axis=0)
        o = bpy.data.objects["mano_" + lado]
        llevar(o, destino, lambda v: v[v[:, 2] > v[:, 2].max() - 0.015].mean(axis=0))

    # --- 5. la cabeza
    #
    # NO se escala por el ancho del cuello contra el escote: el 10 % inferior de nuestra
    # pieza es el pecho del recorte en V, no el cuello, y el factor salia disparatado --
    # 5,32 m de estatura en la primera pasada.
    #
    # Se escala por la CABEZA misma: el ancho biauricular, medido en la banda donde la
    # pieza es mas estrecha por encima de los hombros, que en un varon de 1,80 son 0,155 m.
    # Las trenzas no estorban ahi porque caen por fuera y por debajo, no a la altura de las
    # orejas. La caja entera no sirve: la fijan las trenzas, que cuelgan hasta el pecho.
    # La escala sale de la ESTATURA, que es la medida que el juego fija (la cámara) y la
    # única de la cabeza que no depende de dónde empieza el pelo ni de dónde acaba la
    # barba. Se apoya el cuello en el escote y se escala para que la coronilla caiga en
    # 1,80: factor = (1,80 - z_escote) / alto_de_la_pieza. Medir el biauricular buscando
    # la banda más estrecha no vale — esa banda cae entre las trenzas, no en las orejas,
    # y la primera pasada dio 1,988 m de estatura.
    cab = obs["cabeza"]
    w = mundo(cas)
    escote = banda(w, 0.94, 1.0)
    z_escote = float(escote[:, 2].mean()) - 0.02        # el cuello entra un poco
    escalar(cab, (ESTATURA - z_escote) / np.ptp(mundo(cab)[:, 2]))
    llevar(cab, (0.0, float(escote[:, 1].mean()), z_escote),
           lambda v: np.array([(v[:, 0].min() + v[:, 0].max()) / 2,
                               v[:, 1].mean(), v[:, 2].min()]))
    wc = mundo(cab)
    print("  cabeza: escote en z %.3f, coronilla en %.3f, ancho %.3f m"
          % (z_escote, wc[:, 2].max(), np.ptp(banda(wc, 0.55, 0.85)[:, 0])))

    # --- verificacion
    print("")
    print("=== comprobacion, en metros ===")
    def W(n): return mundo(bpy.data.objects[n])
    med = {
        "estatura a la coronilla": float(W("cabeza")[:, 2].max()),
        "hombros sobre casaca": float(np.ptp(banda(W("casaca"), 0.88, 0.94)[:, 0])),
        "mano": float(np.ptp(W("mano_izq")[:, 2])),
        "cana de bota": float(np.ptp(W("bota_izq")[:, 2])),
        "suelo (min z)": float(min(W(n)[:, 2].min() for n in
                                   ("bota_izq", "bota_der", "piernas", "casaca"))),
    }
    for k, v in med.items():
        print("  %-26s %.3f" % (k, v))

    destino = r"E:\Godot\Game3D\marea_negra\fuentes\blend\capitan_baja.blend"
    bpy.ops.wm.save_as_mainfile(filepath=destino)
    print("")
    print("  -> %s" % destino)


if __name__ == "__main__":
    main()
