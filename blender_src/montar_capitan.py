"""Monta el capitán pirata a partir de las siete piezas sueltas de Meshy.

Las piezas vienen de siete trabajos independientes (fuentes/crudo/Meshy_AI*0911225*),
así que ninguna comparte escala ni origen con las demás: Meshy normaliza cada malla a
2 unidades en su eje mayor. Aquí se les da metros y se encajan unas con otras.

LA ESCALA SE DERIVA DE UNA MEDIDA ANATÓMICA POR PIEZA, no de la caja entera, porque
la caja miente en casi todas: la de la cabeza incluye las trenzas (que cuelgan hasta el
pecho y valen tanto como la cabeza), la de las manos y la de las botas contienen DOS
piezas lado a lado, y la de la casaca la fijan las bocamangas, no los hombros.

Las proporciones se comprueban contra un hombre de 1,80 m:
    hombros (biacromial)  0,46 m, con casaca holgada  0,52
    cabeza mentón-coronilla 0,24;  con barba tupida y pelo  0,30
    mano muñeca-dedo medio  0,19
    caña de bota bajo la rodilla  0,45
Fue el ancho de hombros el que destapó el primer montaje: con la casaca escalada a
1,18 m de largo daba 0,60 m de hombros — un hombre de 2,05 m — y la cabeza parecía
pequeña sin serlo. Se escala por los HOMBROS y el largo de la levita sale de ahí.

El frente del personaje mira a -Y, los pies en z = 0, como el resto del proyecto.
"""

import bpy
import numpy as np

# ---------------------------------------------------------------- piezas

PIEZAS = {
    "p_225044": "sombrero",   # tricornio
    "p_225055": "busto",      # cabeza, cuello y hombros; solo se aprovecha el cuello
    "p_225102": "cabeza",     # cara, melena y trenzas — la cabeza que se usa
    "p_225108": "casaca",     # levita con camisa, faja y brazos en pose A
    "p_225119": "manos",      # las dos, en islas separadas
    "p_225128": "pantalon",
    "p_225135": "botas",      # las dos, en islas separadas
}

ESTATURA = 1.80          # a la coronilla, sin sombrero
HOMBROS_CASACA = 0.52    # ancho sobre la casaca, no sobre el cuerpo
CABEZA = 0.30            # de la coronilla al borde inferior de la barba
MANO = 0.19
CANA_BOTA = 0.45
BAJO_LEVITA = 0.42       # a media pantorrilla
TOBILLO_PANTALON = 0.06


def mundo(o):
    """Los vértices del objeto en coordenadas de mundo, como (n, 3)."""
    me = o.data
    n = len(me.vertices)
    co = np.empty(n * 3, dtype=np.float32)
    me.vertices.foreach_get("co", co)
    M = np.array(o.matrix_world)
    return co.reshape(n, 3) @ M[:3, :3].T + M[:3, 3]


def banda(w, desde, hasta):
    """Los vértices entre dos fracciones de la altura, contadas desde abajo."""
    zmin, zmax = w[:, 2].min(), w[:, 2].max()
    h = zmax - zmin
    m = (w[:, 2] >= zmin + desde * h) & (w[:, 2] <= zmin + hasta * h)
    return w[m]


def escalar(o, factor):
    o.scale = tuple(s * factor for s in o.scale)
    bpy.context.view_layer.update()


def llevar(o, destino, ancla):
    """Traslada el objeto hasta que su punto de anclaje caiga en destino."""
    p = ancla(mundo(o))
    o.location = tuple(o.location[i] + destino[i] - p[i] for i in range(3))
    bpy.context.view_layer.update()


def centro_base(w):
    return np.array([w[:, 0].mean(), w[:, 1].mean(), w[:, 2].min()])


def centrado_en_suelo(w):
    return np.array([(w[:, 0].min() + w[:, 0].max()) / 2,
                     (w[:, 1].min() + w[:, 1].max()) / 2,
                     w[:, 2].min()])


# ------------------------------------------------------- escalas medidas
#
# Unidad normalizada = la que trae el .fbx de Meshy (eje mayor = 2, y el importador
# lo deja en escala 0,5, así que la caja mide 1).
#
# casaca    los HOMBROS, no el largo: X vale 0,40 unidades en la banda 88-92 % de la
#           altura (más arriba está el cuello alzado, 0,22; más abajo, las bocamangas,
#           que llegan a 0,81 y son las que fijan la caja y engañan). 0,47 m de hombros
#           sobre la casaca corresponde a los 0,46 de un hombre de 1,80.
# cabeza    medida sobre un render ortográfico a 1 mm/px: de la coronilla al borde de
#           la barba salen 280 mm con el factor 0,58, y de coronilla a mentón 255 —
#           canon 7,1 cabezas, correcto. Las cajas no sirven aquí: las trenzas cuelgan
#           hasta el pecho y valen tanto como la cabeza.
# busto     no se escala por anatomía sino CONTRA la cabeza: es la misma persona, así
#           que se iguala su distancia nariz-coronilla (0,202 → 0,186, factor 0,921).
#           Del busto solo se aprovecha el cuello; la cara la pone la otra pieza.
# manos     0,19 m de muñeca a dedo medio, sobre los 0,5817 de la caja en Z.
# botas     0,45 m de caña, sobre los 0,821 de la caja en Z.
# sombrero  0,42 m de punta a punta del tricornio, sobre el eje mayor (Y).
#
FACTOR = {"casaca":   1.18,
          "cabeza":   0.58,
          "pantalon": 1.01,
          "botas":    CANA_BOTA / 0.821,
          "manos":    MANO / 0.5817,
          "sombrero": 0.42}

# altura del punto más bajo de cada pieza, con el suelo en z = 0
APOYO = {"botas": 0.0, "pantalon": TOBILLO_PANTALON, "casaca": BAJO_LEVITA,
         "cabeza": 1.22, "sombrero": 1.72}


def escalar_y_apoyar():
    """Da metros a cada pieza y la deja a su altura, centrada en el eje del cuerpo."""
    for nombre, f in FACTOR.items():
        o = bpy.data.objects[nombre]
        escalar(o, f)
    for nombre, z in APOYO.items():
        o = bpy.data.objects[nombre]
        llevar(o, (0.0, 0.0, z), centrado_en_suelo)


def encajar_busto():
    """Iguala el busto a la cabeza por la nariz: misma cara, dos generaciones.

    La nariz es el vértice de Y mínimo (el personaje mira a -Y) y es el único punto
    que ambas piezas comparten sin ambigüedad — la coronilla depende del peinado, que
    es justo lo que cambia entre las dos.
    """
    cab, bus = bpy.data.objects["cabeza"], bpy.data.objects["busto"]
    def nariz_y_coronilla(o):
        w = mundo(o)
        return w[int(np.argmin(w[:, 1]))], float(w[:, 2].max())
    n_cab, cor_cab = nariz_y_coronilla(cab)
    n_bus, cor_bus = nariz_y_coronilla(bus)
    escalar(bus, (cor_cab - n_cab[2]) / (cor_bus - n_bus[2]))
    llevar(bus, n_cab, lambda w: w[int(np.argmin(w[:, 1]))])


def colocar_manos():
    """Cada muñeca al centro de su bocamanga, medido sobre la casaca."""
    w = mundo(bpy.data.objects["casaca"])
    for lado, sel in (("izq", w[:, 0] > w[:, 0].max() - 0.035),
                      ("der", w[:, 0] < w[:, 0].min() + 0.035)):
        destino = w[sel].mean(axis=0)
        o = bpy.data.objects["mano_" + lado]
        # la muñeca es el borde superior: los dedos apuntan hacia abajo
        llevar(o, destino, lambda w: w[w[:, 2] > w[:, 2].max() - 0.012].mean(axis=0))


def colocar_botas():
    """Cada bota bajo su pernera, con la suela en el suelo."""
    p = mundo(bpy.data.objects["pantalon"])
    tobillos = p[p[:, 2] < p[:, 2].min() + 0.05]
    for lado, sel in (("izq", tobillos[:, 0] > 0), ("der", tobillos[:, 0] < 0)):
        c = tobillos[sel].mean(axis=0)
        llevar(bpy.data.objects["bota_" + lado], (c[0], c[1], 0.0), centro_base)


def comprobar():
    """Las medidas que deciden si el montaje está bien, en metros."""
    def w(n): return mundo(bpy.data.objects[n])
    casaca, cabeza = w("casaca"), w("cabeza")
    hombros = banda(casaca, 0.88, 0.92)
    return {"estatura": round(float(cabeza[:, 2].max()), 3),
            "hombros_casaca": round(float(np.ptp(hombros[:, 0])), 3),
            "mano": round(float(np.ptp(w("mano_izq")[:, 2])), 3),
            "cana_bota": round(float(np.ptp(w("bota_izq")[:, 2])), 3)}
