"""Retopología del rostro por PLANTILLA: se ajusta una malla de bucles buenos al escaneo.

El rostro del capitán viene de Meshy: 967.419 vértices, triangulados sin orden, sin un
solo bucle en su sitio. Lo que hace falta para animar una cara son los anillos alrededor
de ojos y boca, el nasolabial y los radiales de la nariz — y esos no los pone ningún
remallador automático (Quadriflow, MMG): esos deciden la dirección por CURVATURA, y no
saben dónde está el ojo. Son una decisión anatómica, no geométrica.

Así que se hace al revés, como en producción: se parte de una malla que YA tiene los
bucles donde deben ir y se deforma hasta pegarla al escaneo. La plantilla es
`GEO-head_animation_realistic` del bundle CC0 de Blender Studio (3.242 vértices,
99,1 % quads). El resultado es este rostro con esa topología.

El ajuste va en tres pasos:

1. SEMEJANZA por mínimos cuadrados sobre los pares de marcas (escala y traslación; sin
   rotación, porque ambas cabezas miran a -Y y están a plomo).
2. DEFORMACIÓN SUAVE (RBF de base r) que lleva cada marca de la plantilla exactamente
   sobre la suya del escaneo y arrastra el resto de forma continua.
3. AJUSTE ITERATIVO tipo ICP no rígido: cada vértice busca el punto más cercano del
   escaneo y se mueve hacia él, con un suavizado laplaciano que impide que la malla se
   rompa. La rigidez baja con las iteraciones: primero la forma global, luego el detalle.

QUÉ MARCAS SE USAN Y POR QUÉ NO TODAS. En el escaneo están las 18 que colocó el usuario.
En la plantilla hay que encontrar las mismas, y solo algunas salen fiables:
  - los OJOS salen de los globos oculares, que la plantilla trae como objetos hijos. Dos
    trampas, las dos medidas. La primera es la cadena de matrices: hay que componer
    `plantilla.matrix_world @ ojo.matrix_parent_inverse @ ojo.matrix_basis`; usar
    `ojo.matrix_world` da el origen del padre duplicado que se importa con ellos, y los
    dos ojos salen en el MISMO punto (interpupilar 0). La segunda es que el centro del
    globo es un punto INTERIOR — está a 12,1 mm de la superficie de la propia plantilla —
    mientras que en el escaneo la marca del ojo está sobre la córnea, en superficie.
    Emparejarlos y clavarlos hunde el párpado 12 mm hacia dentro del ojo y deshace el
    anillo, que es justo el bucle que se venía a buscar. Hay que PROYECTAR el centro del
    globo a la superficie del párpado antes de usarlo como par.
  - las ALAS de la nariz salen de los pliegues cóncavos de la malla.
  - SUBNASAL y LABIOS salen del perfil del plano medio.
  - las COMISURAS y las OREJAS no salen: buscar "lo más lateral" da 88 mm de boca (casi
    el doble de una boca real) y pone el trago en el pómulo, porque a la altura de la
    oreja la mejilla también cumple el filtro. Se descartan: es mejor una marca menos que
    una marca mentirosa, y el ajuste iterativo resuelve esa zona por proximidad.

LO QUE ESTE AJUSTE NO HACE. La plantilla es una cabeza calva y afeitada; el escaneo tiene
melena, trenzas y barba tupida. Al proyectar, el cráneo se pega al PELO (queda el volumen
del peinado, que es lo que se quiere para el juego) y el mentón a la BARBA. Las trenzas
largas caen fuera del alcance de la plantilla y son pieza aparte.
"""

import bpy
import bmesh
import json
import numpy as np
from mathutils import Vector, kdtree

SCRATCH = None  # se fija al invocar

# marcas que existen y son fiables en AMBAS mallas
PARES = ["ojo_izq_centro", "ojo_der_centro", "lagrimal_izq", "lagrimal_der",
         "canto_izq", "canto_der", "nariz_punta", "ala_izq", "ala_der",
         "subnasal", "labio_sup", "labio_inf"]


def vertices_mundo(o):
    me = o.data
    n = len(me.vertices)
    a = np.empty(n * 3, dtype=np.float32)
    me.vertices.foreach_get("co", a)
    M = np.array(o.matrix_world)
    return a.reshape(n, 3) @ M[:3, :3].T + M[:3, 3]


def normales_mundo(o):
    me = o.data
    n = len(me.vertices)
    a = np.empty(n * 3, dtype=np.float32)
    me.vertices.foreach_get("normal", a)
    M = np.array(o.matrix_world)
    v = a.reshape(n, 3) @ M[:3, :3].T
    return v / np.maximum(np.linalg.norm(v, axis=1, keepdims=True), 1e-9)


def aristas(o):
    me = o.data
    n = len(me.edges)
    a = np.empty(n * 2, dtype=np.int32)
    me.edges.foreach_get("vertices", a)
    return a.reshape(n, 2)


def semejanza(origen, destino):
    """Escala uniforme y traslación que llevan `origen` sobre `destino`.

    La escala es la MEDIANA de la razón entre distancias homólogas, no un ajuste por
    mínimos cuadrados. Las 12 marcas caen casi en un plano — son todas de la cara — y con
    mínimos cuadrados eso da una escala sin sentido: la primera prueba encogió la cabeza
    entera contra la cara y dejó un bulto de 7 cm de profundidad donde debía haber 20.
    Una razón de distancias no puede hacer eso: es positiva y del orden correcto por
    construcción, y la mediana ignora la marca que esté peor puesta.
    """
    n = len(origen)
    i, j = np.triu_indices(n, 1)
    do = np.linalg.norm(origen[i] - origen[j], axis=1)
    dd = np.linalg.norm(destino[i] - destino[j], axis=1)
    s = float(np.median(dd / np.maximum(do, 1e-9)))
    return s, destino.mean(axis=0) - s * origen.mean(axis=0)


def rbf(puntos, origen, destino, sigma=0.06, reg=1e-3):
    """Deformación LOCAL que lleva `origen` sobre `destino` y se apaga con la distancia.

    La base es gaussiana a propósito. Con la base r clásica (thin-plate) el término afín
    crece con la distancia, y como las 12 marcas están todas en la cara frontal, la nuca
    y el cuello — que no tienen ninguna cerca — salían disparados: la primera prueba dejó
    la cabeza achatada y con púas de varios centímetros. Con la gaussiana, un vértice a
    más de dos sigmas de toda marca simplemente no se mueve, que es lo correcto cuando no
    hay información sobre él.
    """
    d2 = ((origen[:, None, :] - origen[None, :, :]) ** 2).sum(axis=2)
    K = np.exp(-d2 / sigma ** 2) + reg * np.eye(len(origen))
    W = np.linalg.solve(K, destino - origen)
    dp2 = ((puntos[:, None, :] - origen[None, :, :]) ** 2).sum(axis=2)
    return puntos + np.exp(-dp2 / sigma ** 2) @ W


def detectar_interior(o, umbral=0.75):
    """Marca los vértices que NO están en la piel de fuera: la ranura de los párpados, el
    interior de los labios y las fosas nasales.

    Hacen falta porque el ajuste por punto más cercano no puede colocarlos: en el escaneo
    esa geometría NO EXISTE — el ojo es un párpado cerrado y la boca una línea — así que
    el punto más cercano de un vértice del interior de la boca es la piel de fuera, y la
    cuenca se aplasta contra la cara. Es lo que deformaba la boca en las primeras pruebas.
    Marcados, se dejan fuera de la atracción y solo los arrastran sus vecinos, que es lo
    que conserva la forma de la cuenca.

    El criterio es de VISIBILIDAD, no de posición: se lanzan 18 rayos en el hemisferio de
    la normal de cada vértice y se mira cuántos vuelven a chocar con la propia malla. Un
    punto de la mejilla no choca con nada; uno del interior del labio choca casi siempre.
    Medido sobre esta plantilla: 678 de 3.242 vértices, justo ojos, boca y fosas.
    """
    import math
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    me = o.data
    n = len(me.vertices)
    co = np.empty(n * 3, dtype=np.float32); me.vertices.foreach_get("co", co); co = co.reshape(n, 3)
    nr = np.empty(n * 3, dtype=np.float32); me.vertices.foreach_get("normal", nr); nr = nr.reshape(n, 3)
    bvh = BVHTree.FromPolygons([tuple(v) for v in co.tolist()],
                               [tuple(p.vertices) for p in me.polygons], all_triangles=False)
    conos = [(a, math.radians(b)) for a in (0.0, 0.35, 0.7) for b in range(0, 360, 60)]
    marca = np.zeros(n, dtype=bool)
    for i in range(n):
        nz = Vector(nr[i].tolist()).normalized()
        up = Vector((0, 0, 1)) if abs(nz.z) < 0.9 else Vector((1, 0, 0))
        t1 = nz.cross(up).normalized(); t2 = nz.cross(t1).normalized()
        origen = Vector(co[i].tolist()) + nz * 0.0005
        golpes = 0
        for ang, rot in conos:
            d = (nz * math.cos(ang) + (t1 * math.cos(rot) + t2 * math.sin(rot)) * math.sin(ang)).normalized()
            if bvh.ray_cast(origen, d, 0.08)[0] is not None:
                golpes += 1
        marca[i] = golpes / len(conos) > umbral
    return marca


def ajustar(plantilla, escaneo, marcas_pl, marcas_esc, pasos=60):
    """Pega la plantilla al escaneo. Devuelve las posiciones finales, en mundo.

    Cada paso: cada vértice busca su punto más cercano en el escaneo y avanza hacia él
    (`avance`), y después la malla se relaja hacia el promedio de los vecinos (`rigidez`).
    El avance sube y la rigidez baja: primero cuadra la forma, luego el detalle. Sin el
    relajado la malla se rompe — cada vértice se iría por su cuenta al punto más cercano,
    que en una barba o en una trenza está en cualquier parte.
    """
    V = vertices_mundo(plantilla).astype(np.float64)
    N = normales_mundo(plantilla)
    interior = detectar_interior(plantilla)      # ojos, boca y fosas: no se pegan a nada
    W = vertices_mundo(escaneo)
    NW = normales_mundo(escaneo)

    kd = kdtree.KDTree(len(W))
    for i, p in enumerate(W):
        kd.insert(Vector(p.tolist()), i)
    kd.balance()

    # vecinos, para el relajado
    ar = aristas(plantilla)
    vecinos = [[] for _ in range(len(V))]
    for a, b in ar:
        vecinos[a].append(b)
        vecinos[b].append(a)

    origen = np.array([marcas_pl[k] for k in PARES])
    destino = np.array([marcas_esc[k] for k in PARES])

    # 1. semejanza
    s, t = semejanza(origen, destino)
    V = V * s + t
    origen = origen * s + t

    # 2. deformación suave que clava las marcas
    V = rbf(V, origen, destino)

    # los vértices que hacen de marca, para volver a clavarlos en cada paso
    anclas = {}
    for k, d in zip(PARES, destino):
        i = int(np.argmin(np.linalg.norm(V - d, axis=1)))
        anclas[i] = d

    # 3. ajuste iterativo
    SALTO = 0.008          # metros por paso: sin tope, un vértice salta a una trenza
    # El alcance ENCOGE con los pasos: empieza ANCHO para que el cráneo encuentre el pelo,
    # que está lejos, y acaba fino para que al final nadie se agarre a lo que no le toca.
    # El número importa y está medido: la profundidad de la cabeza terminada sale 15,4 cm
    # con 25 mm de alcance, 15,4 con 60 y 22,1 con 120 — y una cabeza con pelo son 22.
    # La razón de que haga falta tanto: los rasgos de la plantilla son proporcionalmente
    # MÁS GRANDES que los de este rostro (interpupilar 79,6 mm contra 62,2), así que al
    # clavar las marcas la semejanza encoge la cabeza un 28 % y el cráneo queda hundido
    # dentro del pelo. Es el ajuste iterativo el que tiene que volver a sacarlo.
    ALCANCE_INI, ALCANCE_FIN = 0.120, 0.020
    for paso in range(pasos):
        frac = paso / max(pasos - 1, 1)
        avance = 0.35 + 0.45 * frac
        rigidez = 0.55 - 0.42 * frac
        ALCANCE = ALCANCE_INI + (ALCANCE_FIN - ALCANCE_INI) * frac
        if paso % 5 == 0:                      # normales al día: la malla ha cambiado
            plantilla.data.vertices.foreach_set(
                "co", (V @ np.array(plantilla.matrix_world.inverted())[:3, :3].T
                       + np.array(plantilla.matrix_world.inverted())[:3, 3]
                       ).astype(np.float32).ravel())
            plantilla.data.update()
            N = normales_mundo(plantilla)
        objetivo = V.copy()
        for i, p in enumerate(V):
            if interior[i]:
                continue
            co, idx, dist = kd.find(Vector(p.tolist()))
            # dos filtros, y los dos hacen falta: la NORMAL evita que un vértice se pegue
            # a una trenza o a la cara interna de la malla, y la DISTANCIA deja quieto lo
            # que no tiene correspondencia — el cuello y los hombros de la plantilla, que
            # el escaneo no trae, y que sin esto se estiraban en una pala plana hacia
            # adelante buscando la superficie más cercana, que era la barbilla.
            if dist < ALCANCE and float(N[i] @ NW[idx]) > 0.25:
                objetivo[i] = np.array(co[:])      # si no, el punto más cercano puede
        paso_v = avance * (objetivo - V)           # ser una trenza o la cara interna
        largo = np.linalg.norm(paso_v, axis=1, keepdims=True)
        paso_v = np.where(largo > SALTO, paso_v * (SALTO / np.maximum(largo, 1e-9)), paso_v)
        V = V + paso_v
        suave = V.copy()
        for i, vs in enumerate(vecinos):
            if vs:
                suave[i] = V[list(vs)].mean(axis=0)
        V = (1.0 - rigidez) * V + rigidez * suave
        for i, d in anclas.items():
            V[i] = d
    return V


def error_de_ajuste(V, escaneo):
    """Distancia de cada vértice ajustado a la superficie del escaneo, en mm."""
    W = vertices_mundo(escaneo)
    kd = kdtree.KDTree(len(W))
    for i, p in enumerate(W):
        kd.insert(Vector(p.tolist()), i)
    kd.balance()
    d = np.array([kd.find(Vector(p.tolist()))[2] for p in V]) * 1000
    return {"medio": round(float(d.mean()), 2), "p95": round(float(np.percentile(d, 95)), 2),
            "peor": round(float(d.max()), 2)}


def calidad(o):
    """Lo que debe seguir cumpliéndose después de deformar: quads y caras sin invertir."""
    me = o.data
    lados = {}
    for p in me.polygons:
        lados[len(p.vertices)] = lados.get(len(p.vertices), 0) + 1
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    degen = sum(1 for f in bm.faces if f.calc_area() < 1e-9)
    bm.free()
    n = len(me.polygons)
    return {"caras": n, "por_lados": lados,
            "quads_%": round(100.0 * lados.get(4, 0) / max(n, 1), 1),
            "degeneradas": degen}


def cortar_cuencas(plantilla):
    """Devuelve los índices del interior de OJOS y BOCA, para dejarlos como aberturas.

    En retopología facial lo normal es que ojos y boca sean agujeros y el interior se
    ponga aparte. Aquí además hace falta para poder mirar el resultado: con las cuencas
    puestas no se ve si los anillos han quedado bien.

    Dos detalles, los dos aprendidos a base de cortar mal:

    1. La máscara se calcula sobre la PLANTILLA, no sobre la malla ya ajustada. Sobre la
       ajustada `detectar_interior` encuentra 1.042 vértices en vez de 678 —el ajuste crea
       concavidades nuevas— y el corte sale dentado, porque no sigue el bucle del párpado.
       Los índices no cambian al deformar, así que la máscara de la plantilla vale igual.

    2. Solo se cortan las TRES BOLSAS MAYORES: los dos sacos de los párpados (232 y 231
       vértices) y el interior de los labios (120). Las demás bolsas que la visibilidad
       marca —la concha de las orejas, las fosas, el surco del mentón— son superficie
       legítima, y cortarlas abre agujeros en las orejas.
    """
    import bmesh
    dentro = detectar_interior(plantilla)
    bm = bmesh.new()
    bm.from_mesh(plantilla.data)
    bm.verts.ensure_lookup_table()
    marcados = set(np.where(dentro)[0].tolist())
    visto, bolsas = set(), []
    for i in list(marcados):
        if i in visto:
            continue
        pila, grupo = [i], []
        while pila:
            x = pila.pop()
            if x in visto:
                continue
            visto.add(x)
            grupo.append(x)
            for e in bm.verts[x].link_edges:
                y = e.other_vert(bm.verts[x]).index
                if y in marcados and y not in visto:
                    pila.append(y)
        bolsas.append(grupo)
    bm.free()
    bolsas.sort(key=len, reverse=True)
    return sorted(i for g in bolsas[:3] for i in g)
