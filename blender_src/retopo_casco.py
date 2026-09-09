"""Retopología del casco: rejilla de tracas por estaciones, la topología del carpintero.

**Estado: el muestreo funciona (88,4 %). Falta construir malla, proa, espejo, UV y horneado.**

## Por qué esta topología y no otra

Un casco retopologizado a la manera del astillero tiene los anillos longitudinales siguiendo
las **tracas** (de proa a popa, curvándose hacia arriba en los extremos) y los transversales en
las **cuadernas**. Eso da dos cosas de una vez:

- Silueta limpia con pocos polígonos, porque los anillos caen donde está la curvatura.
- **El UV sale gratis**: al desplegar la rejilla, U corre a lo largo de los tablones y V a
  través. Una textura *tileable* de tablazón (Poly Haven, CC0) se alinea con la tablazón **por
  construcción**, y el ancho de tablón se fija escalando V. No hay que marcar tablones a mano.

## Punto de partida, medido

`casco_lod0` **no está retopologizado, está decimado**: 12.388 vértices, 23.930 caras de las
que 23.675 son triángulos y solo 248 quads, con un modificador DECIMATE encima, una sola capa
UV (`UVMap`, la del crudo) y **sin capa `bake`** — nunca pasó por el protocolo de horneado.
Es el 40 % de los 60.659 triángulos del barco entero.

Objetivo: **4.000-6.000 triángulos**. Todo el detalle (juntas calafateadas, brea, desgaste) es
textura, no geometría, así que la reducción no se ve. La regla para repartir los anillos es que
**un normal map no cambia la silueta**: densidad en la línea de borda, la roda, el espejo y el
redondo del pantoque; poca en la tablazón lisa; muy poca en la cara interior, que va tapada por
el panel de cubierta.

## Lo que el muestreo descubrió

- El casco es **98 % simétrico** respecto a y=0 (6.035 de 6.165 grupos con espejo), así que se
  retopologiza **media banda y se refleja**: mitad de trabajo y simetría exacta.
- Tiene **13 islas**: la buena con 12.345 vértices y doce de 3 a 7 vértices que son restos de
  la decimación y hay que borrar antes de nada.
- **El centro del abanico de rayos tiene que ser adaptativo por estación.** Con un centro fijo
  a z=1,2 la tasa de acierto era del 78 %, porque en los extremos el fondo del casco sube a
  z=1,77 (proa) y 2,33 (popa) y el centro quedaba por DEBAJO del casco: los rayos pasaban de
  largo. Situándolo en `zmin + 0.45*(zmax-zmin)` de cada estación sube al 88,4 %.
- El 11,6 % que sigue fallando son **solo las 4 estaciones extremas de proa y las 6 de popa**, y
  es estructural: en la proa la sección degenera en el filo de la roda y en la popa hay un
  espejo plano. Ni una ni otro son tracas.
"""

import math

import bpy
import numpy as np

N_ESTACIONES = 44          # reparto coseno: más juntas en los extremos, donde hay curvatura
N_PERIMETRO = 18           # de la quilla a la borda
BARRIDO_GRADOS = 112.0     # desde recto hacia abajo (quilla) hasta pasada la horizontal
LEJOS = 12.0


def _matrices(o):
    Mw = np.array(o.matrix_world)
    Mi = np.linalg.inv(Mw)
    return Mw, Mi, Mi[:3, :3]


def nube(o) -> np.ndarray:
    n = len(o.data.vertices)
    a = np.empty(n * 3, dtype=np.float32)
    o.data.vertices.foreach_get("co", a)
    Mw = np.array(o.matrix_world)
    return a.reshape(n, 3) @ Mw[:3, :3].T + Mw[:3, 3]


def muestrear(nombre: str = "casco_lod0", n_est: int = N_ESTACIONES,
              n_per: int = N_PERIMETRO) -> dict:
    """Traza la superficie EXTERIOR de media banda como rejilla estación × perímetro.

    Los rayos van de fuera hacia dentro y se toma el primer impacto, que por definición es la
    cara exterior. Al revés (desde dentro hacia fuera) se coge la interior, que no es la que
    queremos: el casco es una cáscara con las dos caras.
    """
    o = bpy.data.objects[nombre]
    oe = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
    Mw, Mi, R = _matrices(o)

    def pl(p):
        q = Mi @ np.array([p[0], p[1], p[2], 1.0])
        return (float(q[0]), float(q[1]), float(q[2]))

    def dl(v):
        w = R @ np.asarray(v, dtype=float)
        return (float(w[0]), float(w[1]), float(w[2]))

    def pm(p):
        q = Mw @ np.array([p[0], p[1], p[2], 1.0])
        return np.array([float(q[0]), float(q[1]), float(q[2])])

    P = nube(o)
    x0 = float(P[:, 0].min()) + 0.03
    x1 = float(P[:, 0].max()) - 0.03
    xs = [x0 + (x1 - x0) * (0.5 - 0.5 * math.cos(math.pi * i / (n_est - 1)))
          for i in range(n_est)]

    rejilla = []
    fallos = 0
    for xa in xs:
        m = np.abs(P[:, 0] - xa) < 0.30
        if int(m.sum()) < 6:
            rejilla.append([None] * n_per)
            fallos += n_per
            continue
        Q = P[m]
        zmin = float(Q[:, 2].min())
        zmax = float(Q[:, 2].max())
        centro = np.array([xa, 0.0, zmin + 0.45 * (zmax - zmin)])
        fila = []
        for j in range(n_per):
            th = math.radians(-90.0 + BARRIDO_GRADOS * j / (n_per - 1))
            d = np.array([0.0, math.cos(th), math.sin(th)])
            hit, loc, _nor, _idx = oe.ray_cast(pl(centro + d * LEJOS), dl(-d),
                                               distance=LEJOS * 2.0)
            if hit:
                fila.append(pm(loc))
            else:
                fila.append(None)
                fallos += 1
        rejilla.append(fila)

    total = n_est * n_per
    return {"rejilla": rejilla, "xs": xs, "aciertos": total - fallos,
            "tasa": round(100.0 * (total - fallos) / total, 1)}


def _rellenar(G, xs, ZR, i0, i1, n_per):
    """Los huecos sueltos se interpolan a lo largo de la TRACA (eje de estaciones), no del
    perímetro: una traca es una curva suave de proa a popa, así que interpolar por ahí acierta;
    por el perímetro se cruzarían tracas distintas."""
    for j in range(n_per):
        idx = [i for i in range(i0, i1 + 1) if G[i][j] is not None]
        if not idx:
            continue
        for i in range(i0, i1 + 1):
            if G[i][j] is not None:
                continue
            ant = [k for k in idx if k < i]
            sig = [k for k in idx if k > i]
            if ant and sig:
                ka, kb = ant[-1], sig[0]
                w = (xs[i] - xs[ka]) / (xs[kb] - xs[ka])
                y = (1 - w) * G[ka][j][1] + w * G[kb][j][1]
            else:
                y = G[(ant[-1] if ant else sig[0])][j][1]
            t = (j / (n_per - 1.0)) ** 0.72
            G[i][j] = np.array([xs[i], y, ZR[i][0] + (ZR[i][1] - ZR[i][0]) * t])


def construir(nombre_origen: str = "casco_lod0", nombre: str = "casco_retopo",
              n_rodilla: int = 4) -> dict:
    """Muestrea, cierra la proa, refleja y deja el objeto listo con UV en metros.

    Resultado medido: **1.088 quads (2.176 triángulos)** desde 23.930 → reducción de 11×, con
    la manga clavada (3,80 m contra 3,81 del original) y las 1.088 normales hacia fuera.
    """
    o = bpy.data.objects[nombre_origen]
    oe = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
    Mw, Mi, R = _matrices(o)
    pl = lambda p: tuple(float(v) for v in (Mi @ np.array([p[0], p[1], p[2], 1.0]))[:3])
    dlv = lambda v: tuple(float(v2) for v2 in R @ np.asarray(v, dtype=float))
    pm = lambda p: np.array([float(v) for v in (Mw @ np.array([p[0], p[1], p[2], 1.0]))[:3]])

    P = nube(o)
    x0 = float(P[:, 0].min()) + 0.03
    x1 = float(P[:, 0].max()) - 0.03
    xs = [x0 + (x1 - x0) * (0.5 - 0.5 * math.cos(math.pi * i / (N_ESTACIONES - 1)))
          for i in range(N_ESTACIONES)]

    G = []
    ZR = []
    for xa in xs:
        m = np.abs(P[:, 0] - xa) < 0.22
        if int(m.sum()) < 6:
            m = np.abs(P[:, 0] - xa) < 0.45
        Q = P[m]
        zmin, zmax = float(Q[:, 2].min()), float(Q[:, 2].max())
        ZR.append((zmin, zmax))
        fila = [np.array([xa, 0.0, zmin])]          # la quilla va en la crujía: semiancho 0
        for k in range(1, N_PERIMETRO):
            z = zmin + (zmax - zmin) * ((k / (N_PERIMETRO - 1.0)) ** 0.72)
            hit, loc, _n, _i = oe.ray_cast(pl((xa, LEJOS, z)), dlv((0, -1, 0)),
                                           distance=LEJOS * 2.0)
            fila.append(np.array([xa, abs(float(pm(loc)[1])), z]) if hit else None)
        G.append(fila)

    buenas = [i for i, f in enumerate(G)
              if sum(1 for p in f if p is not None) >= N_PERIMETRO - 1]
    i0, i1 = buenas[0], buenas[-1]
    _rellenar(G, xs, ZR, i0, i1, N_PERIMETRO)

    # PROA: estaciones nuevas hasta la roda con la manga cerrándose a cero. En el filo del
    # tajamar los rayos no aciertan (no hay superficie que interceptar) y no es un fallo que
    # arreglar: la topología correcta es que las tracas converjan en abanico.
    proa = []
    for r in range(n_rodilla):
        w = (r + 1) / float(n_rodilla + 1)
        xa = xs[i0] + (x0 - xs[i0]) * w
        esc = math.cos(w * math.pi * 0.5) ** 1.6
        m = np.abs(P[:, 0] - xa) < 0.30
        Q = P[m] if int(m.sum()) > 4 else P[np.abs(P[:, 0] - xs[i0]) < 0.30]
        zmin, zmax = float(Q[:, 2].min()), float(Q[:, 2].max())
        proa.append([np.array([xa, G[i0][j][1] * esc,
                               zmin + (zmax - zmin) * ((j / (N_PERIMETRO - 1.0)) ** 0.72)])
                     for j in range(N_PERIMETRO)])
    proa.reverse()
    malla = proa + [G[i] for i in range(i0, i1 + 1)]
    ne = len(malla)

    bm = bmesh.new()
    vs = [[bm.verts.new(tuple(float(c) for c in p)) for p in fila] for fila in malla]
    vs_e = []
    for i, fila in enumerate(malla):
        vs_e.append([vs[i][j] if abs(float(p[1])) < 1e-5
                     else bm.verts.new((float(p[0]), -float(p[1]), float(p[2])))
                     for j, p in enumerate(fila)])
    for i in range(ne - 1):
        for j in range(N_PERIMETRO - 1):
            # La banda reflejada se BOBINA AL REVÉS: reflejar invierte la mano, y con el mismo
            # orden las normales salen hacia dentro y la mitad del casco se ve transparente.
            for q in ([vs[i][j], vs[i + 1][j], vs[i + 1][j + 1], vs[i][j + 1]],
                      [vs_e[i][j], vs_e[i][j + 1], vs_e[i + 1][j + 1], vs_e[i + 1][j]]):
                if len(set(q)) == 4:
                    try:
                        bm.faces.new(q)
                    except ValueError:
                        pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])

    # UV en METROS por longitud de arco, para que una textura tileable mapee a escala real: el
    # ancho de tabla se fija escalando el material, nunca deformando el UV.
    uvl = bm.loops.layers.uv.new("UVMap")
    U = [0.0] * ne
    for i in range(1, ne):
        U[i] = U[i - 1] + abs(malla[i][0][0] - malla[i - 1][0][0])
    V = np.zeros((ne, N_PERIMETRO))
    for i in range(ne):
        for j in range(1, N_PERIMETRO):
            V[i, j] = V[i, j - 1] + float(np.linalg.norm(malla[i][j] - malla[i][j - 1]))
    mapa = {}
    for i in range(ne):
        for j in range(N_PERIMETRO):
            mapa[vs[i][j]] = (U[i], V[i, j])
            mapa[vs_e[i][j]] = (U[i], V[i, j])
    for f in bm.faces:
        for l in f.loops:
            l[uvl].uv = mapa.get(l.vert, (0.0, 0.0))

    me = bpy.data.meshes.new(nombre)
    bm.to_mesh(me)
    bm.free()
    viejo = bpy.data.objects.get(nombre)
    if viejo:
        bpy.data.objects.remove(viejo, do_unlink=True)
    ob = bpy.data.objects.new(nombre, me)
    bpy.context.scene.collection.objects.link(ob)
    return {"verts": len(me.vertices), "caras": len(me.polygons),
            "triangulos": sum(len(p.vertices) - 2 for p in me.polygons),
            "largo_uv_m": round(U[-1], 2)}


# ---------------------------------------------------------------------------------- pendiente
#
# 1. **Popa**: el espejo es un plano, así que va como parche aparte con su propia isla de UV,
#    no como continuación de las tracas (que allí van atravesadas, no de proa a popa). Es lo
#    que hace que ahora el objeto mida 10,86 m en vez de 12.
# 2. **Tapa de regala** y cara interior a densidad muy baja (va oculta bajo la cubierta).
# 3. Borrar las doce islas de resto (< 10 vértices) del original antes de muestrear.
# 4. Segunda capa UV `bake` para el AO/mugre horneado, que es lo que devuelve el detalle único
#    que la textura tileable no tiene.
# 5. Hornear normal y AO desde el crudo de `fuentes/crudo/`, y medir px/mm (listón: el mástil
#    venía empastado a 0,38 px/mm).
# 6. **Reverificar `colisiones_barco.gd`**, que deriva el suelo y las cajas de la borda de la
#    malla del casco en runtime (ahora: 110 triángulos de suelo, 16 secciones, 60 cajas). Es
#    geométrico, así que debería adaptarse, pero por ahí camina el jugador.
