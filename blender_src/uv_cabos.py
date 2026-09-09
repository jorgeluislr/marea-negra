"""UV de cabo construido desde la geometria del tubo, no reescalando el que habia.

Recorre los anillos de la seccion (hexagonal) y a cada vertice le da su indice angular y la
distancia recorrida a lo largo del cabo. Con eso:
  - 3 franjas por vuelta  -> una cada 2 vertices del hexagono, como pidio el usuario
  - paso de colchado 3,5 diametros -> el angulo de helice sale en 42 grados, que es el real
La textura trae 27 franjas por unidad de U y 39 por unidad de V (medido sobre la imagen).
"""
import bmesh, math
import numpy as np

# Franjas del patron por unidad de UV, sacadas de la FFT de la textura: el pico fundamental
# es (8, 7) y lo demas son armonicos. Contarlas por umbral daba 27 y 39 porque las fibras
# finas de la lona se cuentan como surcos, y con eso todo el mapeado salia mal.
FRANJAS_U = 8.0
FRANJAS_V = 7.0
FRANJAS_POR_VUELTA = 3.0
PASO_EN_DIAMETROS = 3.5
SENTIDO = 1        # +1 helice a derechas (colchado en Z, el corriente); -1 a izquierdas

# Cuantas veces mas apretada va la fibra a lo largo que alrededor, en un cabo entorchado.
# Sale de la colocacion a mano del usuario sobre el amarre del mastil: 9,750 / 2,543173. Aplicada
# a ese mismo cabo devuelve su 9,75 exacto, asi que es su calibracion generalizada a cualquier
# grueso. La eligio a ojo y por una razon concreta: apretada se pixela menos, porque el texel
# de la textura cubre menos superficie.
RAZON_FIBRA = 3.833794


def _recorrer(bm, semilla, aristas_anillo, avanzar_por):
    """Construye anillos desde una semilla. `aristas_anillo(v)` da las aristas con las que se
    rodea el anillo; `avanzar_por(v)` las que llevan al anillo siguiente."""
    anillo = [semilla]
    previo, actual = None, semilla
    while True:
        sig = None
        for e in aristas_anillo(actual):
            o = e.other_vert(actual)
            if o is previo or o is semilla or o in anillo:
                continue
            sig = o
            break
        if sig is None:
            break
        anillo.append(sig)
        previo, actual = actual, sig
    n = len(anillo)
    if n < 3:
        return None
    anillos = [anillo]
    visitados = set(v.index for v in anillo)
    while True:
        siguiente = []
        for v in anillos[-1]:
            cand = [e.other_vert(v) for e in avanzar_por(v)
                    if e.other_vert(v).index not in visitados]
            cand = [c for c in cand if c not in anillos[-1]]
            if not cand:
                siguiente = []
                break
            siguiente.append(cand[0])
        if len(siguiente) != n or len(set(x.index for x in siguiente)) != n:
            break
        anillos.append(siguiente)
        visitados.update(x.index for x in siguiente)
    return anillos


def anillos_del_tubo(bm):
    """Anillos del tubo en orden, o None.

    Se prueban dos caminos porque ninguno vale para todas las topologias: por vertices de
    valencia 3 funciona en los tubos largos, y por aristas de borde en los de dos anillos,
    donde TODOS los vertices son de borde y el otro metodo mezcla los dos extremos.
    Gana el que cubra mas vertices de la malla.
    """
    candidatos = []
    borde3 = [v for v in bm.verts if len(v.link_edges) == 3]
    if borde3:
        r = _recorrer(bm, borde3[0],
                      lambda v: [e for e in v.link_edges if len(e.other_vert(v).link_edges) == 3],
                      lambda v: v.link_edges)
        if r:
            candidatos.append(r)
    bordes = [e for e in bm.edges if e.is_boundary]
    if bordes:
        r = _recorrer(bm, bordes[0].verts[0],
                      lambda v: [e for e in v.link_edges if e.is_boundary],
                      lambda v: [e for e in v.link_edges if not e.is_boundary])
        if r:
            candidatos.append(r)
    # Un candidato de un solo anillo no es un tubo: descartarlo ANTES de comparar, o empata
    # en cobertura con el bueno (un ciclo de 12 frente a dos anillos de 6) y gana el desempate.
    candidatos = [c for c in candidatos if len(c) >= 2]
    if not candidatos:
        return None
    mejor = max(candidatos, key=lambda a: len(a) * len(a[0]))
    # Un tubo valido cubre casi toda la malla; si no, la pieza no es un tubo simple.
    if len(mejor) * len(mejor[0]) < 0.9 * len(bm.verts):
        return None
    return mejor if len(mejor) >= 2 else None


def uv_de_cabo(obj):
    """Coloca el UV de un cabo a partir de su geometria.

    Los vertices del primer anillo se reparten por las franjas de la textura (una cada dos
    vertices del hexagono = 3 cordones) y los siguientes suben en vertical segun la longitud
    recorrida por el eje del cabo; la diagonal ya la trae la textura.

    Dos cosas que no son evidentes:
      - La costura necesita una columna de mas: el ultimo lado va del vertice 5 al 0, y si al 0
        se le pone u=0 esa cara recorre el UV entera al reves. Como el UV se guarda por LOOP y
        no por vertice, se le da u = lados (la primera columna repetida una vuelta despues) sin
        tocar la malla.
      - La distancia se acumula entre CENTROS de anillo, o sea a lo largo del EJE del cabo, no
        por cada arista longitudinal. En un cabo curvado la cara exterior del codo es mas larga
        que la interior, y darle a cada columna SU distancia mantiene la densidad de textura
        perfecta a costa de DESALINEAR las columnas: los dos vertices de un mismo anillo caen a
        distinta altura del UV y el cordon se parte. Medido en el acollador de una vigota
        (codos de 180 grados): 29 mm de cizalla media y 111 mm de pico, siete veces el ancho
        del cordon, que es el patron rayado que se veia. Por el eje la cizalla es 0 y lo que
        queda es la textura comprimida al 0,65 por dentro del codo y estirada al 2,1 por
        fuera, que es lo que hace un cabo de verdad al doblar.
    """
    me = obj.data
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    anillos = anillos_del_tubo(bm)
    if anillos is None or len(anillos) < 2:
        bm.free(); return None
    lados = len(anillos[0])
    perims = []
    for an in anillos:
        perims.append(sum((an[i].co - an[(i + 1) % lados].co).length for i in range(lados)))
    perim = float(np.mean(perims))
    diam = perim / math.pi
    paso = PASO_EN_DIAMETROS * diam

    # Distancia acumulada a lo largo del EJE: un valor por anillo, para que sus vertices caigan
    # ALINEADOS en una columna del UV. Ver el docstring: por columna la cizalla parte el cordon.
    centros = [np.mean([[v.co.x, v.co.y, v.co.z] for v in an], axis=0) for an in anillos]
    z = [0.0]
    for a in range(1, len(anillos)):
        z.append(z[a - 1] + float(np.linalg.norm(centros[a] - centros[a - 1])))
    largo = z[-1]

    # U: 3 franjas por vuelta. V: la condicion de paralelismo (A + p*B).n = 0 con A.n = 3
    # da B.n = -3/p, o sea v_por_metro = -3 / (FRANJAS_V * paso).
    rango_u_vuelta = FRANJAS_POR_VUELTA / FRANJAS_U
    v_por_metro = -SENTIDO * FRANJAS_POR_VUELTA / (FRANJAS_V * paso)

    idx = {v.index: (a, j) for a, an in enumerate(anillos) for j, v in enumerate(an)}
    bm.free()
    uvl = me.uv_layers[0]
    for poly in me.polygons:
        js = [idx[me.loops[li].vertex_index][1] for li in poly.loop_indices
              if me.loops[li].vertex_index in idx]
        if len(js) != len(poly.loop_indices):
            continue
        cruza = (0 in js) and (lados - 1 in js)
        for li in poly.loop_indices:
            a, j = idx[me.loops[li].vertex_index]
            jj = lados if (cruza and j == 0) else j
            uvl.data[li].uv = (jj / lados * rango_u_vuelta, z[a] * v_por_metro)
    me.update()
    ang = math.degrees(math.atan2(math.pi * diam, paso))
    return {"lados": lados, "anillos": len(anillos), "diam_mm": round(diam * 1000, 1),
            "largo_cm": round(largo * 100, 1), "paso_mm": round(paso * 1000, 1),
            "helice_grados": round(ang, 1),
            "franja_ancho_mm": round(math.pi * diam * 1000 / FRANJAS_POR_VUELTA, 1),
            "U_por_vuelta": round(rango_u_vuelta, 4),
            "V_por_metro": round(v_por_metro, 3)}


def uv_de_cabo_entorchado(obj, cordones=3, densidad_larga=None, razon=RAZON_FIBRA):
    """UV para un cabo cuyo ENTORCHADO ya esta en la geometria (`amarre_mastil`).

    Medido de la colocacion del usuario sobre un fragmento y comprobado contra ella:

      - ALREDEDOR va en **V**, 3/7 = 0,4286 por vuelta. Cruza 3 franjas, una por cordon.
      - A LO LARGO va PARALELO a las franjas, en la direccion (7, -8) perpendicular a la
        normal n=(8,7). Avanzar no cruza ninguna franja: la helice ya la pone la malla y la
        textura no debe anadir otra.

    Ojo con la orientacion: la primera version llevaba la vuelta en U en vez de en V, o sea
    girada 90 grados, y la fibra salia cruzada.

    `densidad_larga` en unidades de UV por metro. **Dejalo en None** y se deriva del perimetro
    real del cabo por `RAZON_FIBRA`, que es lo que reproduce en cualquier grueso el aspecto del
    amarre del mastil. Un valor FIJO no vale: 9,75 sobre un cabo de 53,6 mm da razon 3,834 y
    sobre uno de 16 mm da 1,18, o sea la fibra cambia de aspecto solo por el diametro. Con
    `razon` se pide otra proporcion; `razon=1.0` deja la textura isotropa, como los 61 cabos
    simples del barco (que estan en 1,026 porque su escala sale del paso de colchado).
    """
    me = obj.data
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    anillos = anillos_del_tubo(bm)
    if anillos is None or len(anillos) < 2:
        bm.free(); return None
    lados = len(anillos[0])
    perim = float(np.mean([sum((an[i].co - an[(i + 1) % lados].co).length for i in range(lados))
                           for an in anillos]))
    diam = perim / math.pi
    # Distancia acumulada entre CENTROS de anillo: un solo valor por anillo, para que sus
    # 9 vertices caigan ALINEADOS en una columna del UV. Usar la distancia de cada columna
    # (que es lo correcto en un cabo curvado) aqui desalinea la columna, porque en un cabo
    # entorchado cada una recorre su propia helice y avanza distinto.
    centros = [np.mean([[v.co.x, v.co.y, v.co.z] for v in an], axis=0) for an in anillos]
    z_anillo = [0.0]
    for a in range(1, len(anillos)):
        z_anillo.append(z_anillo[a - 1] + float(np.linalg.norm(centros[a] - centros[a - 1])))
    largo = z_anillo[-1]

    n = np.array([FRANJAS_U, FRANJAS_V], dtype=float)
    d_hat = np.array([n[1], -n[0]]) / float(np.linalg.norm(n))   # paralela a las franjas
    v_perim = cordones / FRANJAS_V                                # 0,4286: la vuelta va en V
    if densidad_larga is None:
        # Escala perimetral (el recorrido de la vuelta repartido entre el perimetro real) por
        # la razon pedida. Con razon=1 la textura sale isotropa.
        densidad_larga = razon * v_perim / (math.pi * diam)

    idx = {v.index: (a, j) for a, an in enumerate(anillos) for j, v in enumerate(an)}
    bm.free()
    uvl = me.uv_layers[0]
    for poly in me.polygons:
        js = [idx[me.loops[li].vertex_index][1] for li in poly.loop_indices
              if me.loops[li].vertex_index in idx]
        if len(js) != len(poly.loop_indices):
            continue
        cruza = (0 in js) and (lados - 1 in js)
        for li in poly.loop_indices:
            a, j = idx[me.loops[li].vertex_index]
            jj = lados if (cruza and j == 0) else j
            q = z_anillo[a] * densidad_larga
            uvl.data[li].uv = (float(q * d_hat[0]),
                               float((jj / lados) * v_perim + q * d_hat[1]))
    me.update()
    lon = d_hat * densidad_larga
    per = np.array([0.0, v_perim])
    return {"lados": lados, "anillos": len(anillos), "cordones": cordones,
            "caras_por_cordon": lados // cordones,
            "diam_mm": round(diam * 1000, 1), "largo_cm": round(largo * 100, 1),
            "perimetral_por_vuelta": [round(float(x), 4) for x in per],
            "longitudinal_por_metro": [round(float(x), 4) for x in lon],
            "franjas_por_vuelta": round(float(per @ n), 2),
            "franjas_al_avanzar_1m": round(float(lon @ n), 2),
            "densidad_larga": round(float(densidad_larga), 3),
            "razon_escalas": round(float(np.linalg.norm(lon)) /
                                   (float(np.linalg.norm(per)) / (math.pi * diam)), 3)}


# ── Cabos cerrados en bucle (toros) ──────────────────────────────────────────
#
# Una trinca, un aforrado o un nudo no tienen extremos: son tubos cerrados sobre si mismos.
# Todos sus vertices tienen valencia 4 y no hay ni una arista de borde, asi que ninguno de los
# dos metodos de arriba los reconoce. Hay que buscar el ciclo mas corto: la seccion.

def _opuesta(v, e_entrada):
    """En una malla de quads, la arista de `v` que no comparte cara con `e_entrada`."""
    caras = set(e_entrada.link_faces)
    for e in v.link_edges:
        if e is e_entrada:
            continue
        if not (set(e.link_faces) & caras):
            return e
    return None


def _seguir_ciclo(v0, e0):
    """Recorre el ciclo de aristas desde `v0` por `e0` hasta volver. Devuelve los vertices."""
    ciclo = [v0]
    v, e = e0.other_vert(v0), e0
    tope = 10000
    while v is not v0 and tope > 0:
        ciclo.append(v)
        e = _opuesta(v, e)
        if e is None:
            return None
        v = e.other_vert(v)
        tope -= 1
    return ciclo if v is v0 else None


def anillos_de_toro(bm, isla=None):
    """Anillos de un tubo cerrado en bucle, o None.

    Se prueban los dos ciclos que pasan por un vertice y se toma el MAS CORTO como seccion;
    el otro es el recorrido a lo largo. Luego se avanza anillo a anillo hasta cerrar.
    """
    verts = [v for v in bm.verts if isla is None or v.index in isla]
    if not verts or any(len(v.link_edges) != 4 for v in verts):
        return None
    v0 = verts[0]
    ciclos = []
    for e in v0.link_edges:
        c = _seguir_ciclo(v0, e)
        if c and len(c) >= 3:
            ciclos.append((len(c), c, e))
    if not ciclos:
        return None
    ciclos.sort(key=lambda x: x[0])
    _, anillo, e_anillo = ciclos[0]
    n = len(anillo)
    total = len(verts)
    if total % n != 0:
        return None
    anillos = [anillo]
    visitados = set(v.index for v in anillo)
    while len(visitados) < total:
        siguiente = []
        for v in anillos[-1]:
            # la arista que sale del anillo: la que no esta en el ciclo de la seccion
            cand = None
            for e in v.link_edges:
                o = e.other_vert(v)
                if o in anillos[-1] or o.index in visitados:
                    continue
                cand = o
                break
            if cand is None:
                siguiente = []
                break
            siguiente.append(cand)
        if len(siguiente) != n or len(set(x.index for x in siguiente)) != n:
            break
        anillos.append(siguiente)
        visitados.update(x.index for x in siguiente)
    return anillos if len(anillos) >= 2 else None


def islas_de(bm):
    """Indices de vertices agrupados por conectividad."""
    bm.verts.ensure_lookup_table()
    pendientes = set(v.index for v in bm.verts)
    islas = []
    while pendientes:
        sem = pendientes.pop()
        pila = [bm.verts[sem]]
        isla = {sem}
        while pila:
            v = pila.pop()
            for e in v.link_edges:
                w = e.other_vert(v)
                if w.index in pendientes:
                    pendientes.discard(w.index)
                    isla.add(w.index)
                    pila.append(w)
        islas.append(isla)
    return islas


def uv_de_cabo_cerrado(obj, cordones=3):
    """Mapea un cabo formado por bucles cerrados, isla por isla.

    Cada isla se trata como un cabo independiente: 3 franjas por vuelta y avance cruzando las
    franjas, como en un cabo colchado. La diferencia esta en el cierre: al ser un bucle, el
    numero de repeticiones a lo largo se REDONDEA a entero, y asi el patron casa al dar la
    vuelta completa en vez de dejar un salto visible.
    """
    me = obj.data
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    uvl = me.uv_layers[0]
    hechas, fallos = 0, 0
    n = np.array([FRANJAS_U, FRANJAS_V], dtype=float)
    for isla in islas_de(bm):
        anillos = anillos_de_toro(bm, isla)
        if anillos is None:
            fallos += 1
            continue
        lados = len(anillos[0])
        perim = float(np.mean([sum((an[i].co - an[(i + 1) % lados].co).length
                                   for i in range(lados)) for an in anillos]))
        diam = perim / math.pi
        # Recorrido cerrado: se suma tambien el salto del ultimo anillo al primero.
        centros = [np.mean([[v.co.x, v.co.y, v.co.z] for v in an], axis=0) for an in anillos]
        z = [0.0]
        for a in range(1, len(anillos)):
            z.append(z[-1] + float(np.linalg.norm(centros[a] - centros[a - 1])))
        largo_total = z[-1] + float(np.linalg.norm(centros[0] - centros[-1]))
        rango_u = FRANJAS_POR_VUELTA / FRANJAS_U
        paso = PASO_EN_DIAMETROS * diam
        v_ideal = FRANJAS_POR_VUELTA / (FRANJAS_V * paso) * largo_total
        vueltas = max(1.0, round(v_ideal))          # entero: el patron casa al cerrar
        v_por_metro = -SENTIDO * vueltas / largo_total
        idx = {v.index: (a, j) for a, an in enumerate(anillos) for j, v in enumerate(an)}
        n_anillos = len(anillos)
        for poly in me.polygons:
            datos = [idx.get(me.loops[li].vertex_index) for li in poly.loop_indices]
            if any(d is None for d in datos):
                continue
            js = [d[1] for d in datos]
            aa = [d[0] for d in datos]
            cruza_u = (0 in js) and (lados - 1 in js)
            # La fila de caras que CIERRA el bucle: une el ultimo anillo con el primero. Sin
            # esto, sus vertices del anillo 0 valen z=0 y los del ultimo z=largo, asi que esa
            # vuelta de caras recibe el patron entero comprimido y se ve rayada distinta. Es
            # la misma costura que en U, pero a lo largo.
            cierra = (0 in aa) and (n_anillos - 1 in aa)
            for li, (a, j) in zip(poly.loop_indices, datos):
                jj = lados if (cruza_u and j == 0) else j
                za = largo_total if (cierra and a == 0) else z[a]
                uvl.data[li].uv = (jj / lados * rango_u, za * v_por_metro)
        hechas += 1
    bm.free()
    me.update()
    return {"islas_mapeadas": hechas, "islas_sin_reconocer": fallos}
