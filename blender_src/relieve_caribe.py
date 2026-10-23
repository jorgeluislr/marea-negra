"""Alturas del Caribe por celdas de 1 km, a partir de las costas.

    PY="C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"
    $PY blender_src/relieve_caribe.py celdas                 # todas
    $PY blender_src/relieve_caribe.py celdas 0,0 -1,0         # solo esas (pruebas)
    $PY blender_src/relieve_caribe.py contar

Se corre con el Python de Blender por numpy. Lee `fuentes/derivados/costas_caribe.json` y escribe
`assets/islas/relieve/`: un `c_<cx>_<cz>.alt` por celda (251 × 251 alturas en float16, gzip) y un
`indice.json` con las celdas, más `basto.bin` con sus versiones bastas (26 × 26, float16, en el
orden del índice) para las siluetas lejanas: en binario aparte para que el arranque no tenga que
interpretar cinco megas de texto. El juego
lo lee con `Relieve` y lo dibuja `GestorTierra`. Son datos REGENERABLES (unos minutos), por eso no
van a git.

Mismo criterio que `GeneradorIsla`: la altura sale de la DISTANCIA CON SIGNO a la costa, así que la
costa del relieve es la de la carta por construcción. La distancia es EXACTA a los tramos de costa
cercanos —sacados de una rejilla de cubos— en vez de propagada por un raster: la versión con chaflán
iterado tardaba 2 min por 16 km², y el Caribe tiene 2.087 celdas con tierra.

**Alturas REALES** (22-10-2026): la tierra sale de Copernicus GLO-90 y el fondo de ETOPO 2022
(`fuentes/crudo/dem/`, ver su FUENTES.md), leídos con `tifffile` desde `fuentes/pylib`. Cada celda
guarda DOS capas: la BASE en metros de juego (la playa y el fondo, que no se escalan: el calado del
barco es real) y el RELIEVE en metros REALES, fundido a cero junto a la costa. El juego compone
`base + escala_vertical · relieve` al cargar (`Relieve`), así que la escala vertical se cambia sin
regenerar. La costa sigue siendo la de OSM: el mapa de alturas solo da la forma de dentro.

Donde no hay mapa de alturas descargado queda el cerro sintético de antes —la cota de su pico real
(o una por su área) con `1 − e^(−d/L)`, L según la isla—, guardado también como relieve real.

    $PY blender_src/relieve_caribe.py zona 17.6,18.6,-78.5,-76.1     # las celdas de esa caja lat/lon
"""
import gzip
import json
import math
import os
import sys
from multiprocessing import Pool

import numpy as np

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COSTAS = os.path.join(RAIZ, "fuentes/derivados/costas_caribe.json")
SALIDA = os.path.join(RAIZ, "assets/islas/relieve")
DEM = os.path.join(RAIZ, "fuentes/crudo/dem")
sys.path.append(os.path.join(RAIZ, "fuentes/pylib"))   # tifffile + imagecodecs, fuera de git
M_POR_GRADO = 111320.0

CELDA = 1000.0
PASO = 4.0                      # m entre alturas
LADO = int(CELDA / PASO) + 1    # 251: el borde se comparte con la celda vecina
BASTO = 10                      # una de cada 10 → 26 × 26, 40 m, para la silueta lejana
ALCANCE_TIERRA = 1100.0         # más adentro el cerro ya está saturado (e^-5)
ALCANCE_AGUA = 300.0            # más afuera ya es fondo
ESCALA_ALTURA = 1.0 / 8.0

PLAYA = 6.0
COTA_PLAYA = 1.2
PLATAFORMA = 20.0
PEND_PLATAFORMA = 0.05
PEND_TALUD = 0.22
FONDO = -40.0                   # tope de profundidad: más hondo nadie lo ve ni vara
ORILLA = 12.0                   # m de juego tierra adentro en que el relieve real llega entero

# Pico más alto de cada isla con nombre, en metros REALES.
PICOS = {
    "Cuba": 1974, "La Española": 3098, "Jamaica": 2256, "Puerto Rico": 1338,
    "Isla de la Juventud": 310, "Vieques": 301, "Culebra": 198, "Saint Thomas": 474,
    "Saint John": 389, "Saint Croix": 355, "Tortola": 521, "Virgen Gorda": 414, "Anegada": 8,
    "Jost Van Dyke": 321, "Norman Island": 130, "Anguila": 73, "San Martín": 424,
    "San Bartolomé": 286, "Saba": 887, "San Eustaquio": 601, "San Cristóbal": 1156,
    "Nieves": 985, "Barbuda": 38, "Antigua": 402, "Montserrat": 915, "Guadalupe": 1467,
    "María Galante": 204, "Dominica": 1447, "Martinica": 1397, "Santa Lucía": 950,
    "San Vicente": 1234, "Bequia": 268, "Barbados": 336, "Granada": 840, "Carriacou": 291,
    "Tobago": 576, "Trinidad": 940, "Aruba": 188, "Curazao": 372, "Bonaire": 241,
    "Margarita": 920, "La Tortuga": 378, "Gonâve": 778, "Saona": 40, "Mona": 90,
    "Gran Caimán": 18, "Caimán Brac": 43, "Pequeño Caimán": 12, "Roatán": 235, "Utila": 74,
    "Guanaja": 412, "Cozumel": 15, "Isla Mujeres": 15, "San Andrés": 85, "Providencia": 360,
    "Providenciales": 49, "Gran Turca": 20, "Gran Inagua": 40, "Andros": 20,
    "Nueva Providencia": 37, "Gran Bahama": 20, "Eleuthera": 63, "Ábaco": 40,
    "Long Island": 55, "Gran Exuma": 43, "Cat Island": 63, "La Tortuga (Venezuela)": 40,
    "Tierra Firme": 800,
}


def cargar():
    d = json.load(open(COSTAS, encoding="utf-8"))
    polis = [np.array(i["puntos"], dtype=np.float64) for i in d["islas"]]
    nombres = [i["nombre"] for i in d["islas"]]
    return d, polis, nombres


def _area(p):
    return abs(0.5 * float(np.dot(p[:, 0], np.roll(p[:, 1], -1)) - np.dot(np.roll(p[:, 0], -1), p[:, 1])))


def preparar(polis, nombres):
    """Tramos de costa en una rejilla de cubos de 1 km, y cota y L de cada isla."""
    a = np.concatenate(polis)
    b = np.concatenate([np.roll(p, -1, axis=0) for p in polis])
    cubos = {}
    lo = np.floor(np.minimum(a, b) / CELDA).astype(int)
    hi = np.floor(np.maximum(a, b) / CELDA).astype(int)
    for k in range(len(a)):
        for cx in range(lo[k, 0], hi[k, 0] + 1):
            for cz in range(lo[k, 1], hi[k, 1] + 1):
                cubos.setdefault((cx, cz), []).append(k)
    cotas, eles = [], []
    for p, n in zip(polis, nombres):
        area = _area(p)
        if n in PICOS:
            cota = PICOS[n] * ESCALA_ALTURA
        else:
            cota = min(max(0.02 * math.sqrt(area), 3.0), 60.0)
        cotas.append(cota)
        eles.append(min(max(0.12 * math.sqrt(area), 8.0), 220.0))
    return a, b, cubos, np.array(cotas), np.array(eles)


def _distancia(px, pz, a, b, paso=2.0, vecinos=6):
    """Distancia mínima de cada punto a los tramos (a, b).

    Por KD-tree: los tramos se muestrean cada `paso` metros, se busca a cada punto sus `vecinos`
    muestras más cercanas y se mide la distancia EXACTA a los tramos de esas muestras. Antes era
    fuerza bruta (cada punto contra cada tramo cercano): la celda tardaba 0,6 s de media y 7,9 en
    las costas recortadas; así, 0,12 y 1,2 (22-10-2026, mismas 80 celdas).

    Con 3 vecinos el tramo más cercano a veces NO estaba entre los candidatos —en un rincón, las
    tres muestras más próximas pueden ser de otro tramo— y salía 2 mm de más a 12 m de la costa
    (3 cm de altura). Con 6, idéntica a la fuerza bruta en las 41 celdas de Jamaica y Vírgenes.
    """
    from scipy.spatial import cKDTree
    ab = b - a
    largo = np.sqrt((ab ** 2).sum(1))
    n = np.maximum(np.ceil(largo / paso).astype(np.int64), 1)
    tramo = np.repeat(np.arange(len(a)), n)
    inicio = np.repeat(np.cumsum(n) - n, n)
    t = (np.arange(len(tramo)) - inicio) / n[tramo]
    muestras = a[tramo] + ab[tramo] * t[:, None]
    k = min(vecinos, len(muestras))
    _, ix = cKDTree(muestras).query(np.stack([px, pz], axis=1), k=k)
    cand = tramo[ix.reshape(len(px), k)]                      # N × k tramos candidatos
    sa, sab = a[cand], ab[cand]
    rx = px[:, None] - sa[..., 0]
    rz = pz[:, None] - sa[..., 1]
    largo2 = np.maximum((sab ** 2).sum(-1), 1e-12)
    u = np.clip((rx * sab[..., 0] + rz * sab[..., 1]) / largo2, 0.0, 1.0)
    dx = rx - u * sab[..., 0]
    dz = rz - u * sab[..., 1]
    return np.sqrt(dx * dx + dz * dz).min(axis=1)


def _dueno(polis, x0, z0):
    """Qué isla hay en cada punto de la celda (-1 agua), par-impar fila a fila."""
    dueño = np.full((LADO, LADO), -1, dtype=np.int32)
    xs = x0 + np.arange(LADO) * PASO
    zs = z0 + np.arange(LADO) * PASO
    for k, p in enumerate(polis):
        if p[:, 0].max() < x0 or p[:, 0].min() > x0 + CELDA or p[:, 1].max() < z0 or p[:, 1].min() > z0 + CELDA:
            continue
        a, b = p, np.roll(p, -1, axis=0)
        for j in np.nonzero((zs >= p[:, 1].min()) & (zs <= p[:, 1].max()))[0]:
            z = zs[j]
            cruza = (a[:, 1] > z) != (b[:, 1] > z)
            if not cruza.any():
                continue
            aa, bb = a[cruza], b[cruza]
            cx = aa[:, 0] + (z - aa[:, 1]) * (bb[:, 0] - aa[:, 0]) / (bb[:, 1] - aa[:, 1])
            cx.sort()
            for i in range(0, len(cx) - 1, 2):
                dentro = (xs >= cx[i]) & (xs < cx[i + 1])
                dueño[j, dentro] = k
    return dueño


def _ruido(px, pz):
    """fBm de valor anclado al MUNDO, en [-1, 1]: dos celdas vecinas dan lo mismo en su borde."""
    total = np.zeros(px.shape)
    amp, norma, esc = 1.0, 0.0, 180.0
    for o in range(5):
        gx, gz = np.floor(px / esc), np.floor(pz / esc)
        fx, fz = px / esc - gx, pz / esc - gz
        fx, fz = fx * fx * (3 - 2 * fx), fz * fz * (3 - 2 * fz)

        def h(ix, iz):
            v = np.sin(ix * 127.1 + iz * 311.7 + o * 74.7) * 43758.5453
            return (v - np.floor(v)) * 2 - 1

        top = h(gx, gz) + (h(gx + 1, gz) - h(gx, gz)) * fx
        bot = h(gx, gz + 1) + (h(gx + 1, gz + 1) - h(gx, gz + 1)) * fx
        total += amp * (top + (bot - top) * fz)
        norma += amp
        amp *= 0.5
        esc *= 0.5
    return total / norma


class Mosaico:
    """Teselas GeoTIFF en lat/lon, cargadas a demanda; `muestrear` da metros reales (NaN sin tesela)."""

    def __init__(self, carpeta, nombre, grado, tope):
        import tifffile
        self.tifffile = tifffile
        self.carpeta, self.nombre, self.grado = carpeta, nombre, grado
        # Cuántas teselas se guardan a la vez: con 18 procesos y sin tope cada uno acababa con todo
        # el Caribe en memoria (~1,6 GB por proceso). Se suelta la usada hace más tiempo.
        self.tope = tope
        self.teselas = {}

    def _tesela(self, clave):
        if clave in self.teselas:
            self.teselas[clave] = self.teselas.pop(clave)   # al final: la más reciente
        else:
            while len(self.teselas) >= self.tope:
                self.teselas.pop(next(iter(self.teselas)))
            ruta = os.path.join(self.carpeta, self.nombre(*clave))
            if os.path.exists(ruta):
                with self.tifffile.TiffFile(ruta) as t:
                    g = t.geotiff_metadata
                    datos = t.pages[0].asarray().astype(np.float32)
                tp, ps = g["ModelTiepoint"], g["ModelPixelScale"]
                self.teselas[clave] = (datos, tp[3], tp[4], ps[0], ps[1])
            else:
                self.teselas[clave] = None
        return self.teselas[clave]

    def muestrear(self, lat, lon):
        r = np.full(lat.shape, np.nan, dtype=np.float32)
        # La esquina SUROESTE de la tesela, en múltiplos de `grado`.
        kl = np.floor(lat / self.grado).astype(int)
        ko = np.floor(lon / self.grado).astype(int)
        for a, b in set(zip(kl.ravel().tolist(), ko.ravel().tolist())):
            t = self._tesela((a * self.grado, b * self.grado))
            if t is None:
                continue
            datos, oeste, norte, dx, dy = t
            m = (kl == a) & (ko == b)
            fx = (lon[m] - oeste) / dx
            fy = (norte - lat[m]) / dy
            i0 = np.clip(np.floor(fx).astype(int), 0, datos.shape[1] - 2)
            j0 = np.clip(np.floor(fy).astype(int), 0, datos.shape[0] - 2)
            u = np.clip(fx - i0, 0, 1)
            v = np.clip(fy - j0, 0, 1)
            arr = datos[j0, i0] * (1 - u) + datos[j0, i0 + 1] * u
            aba = datos[j0 + 1, i0] * (1 - u) + datos[j0 + 1, i0 + 1] * u
            r[m] = arr * (1 - v) + aba * v
        return r


def _nombre_copernicus(lat, lon):
    return "Copernicus_DSM_COG_30_%s%02d_00_%s%03d_00_DEM.tif" % (
        "N" if lat >= 0 else "S", abs(lat), "W" if lon < 0 else "E", abs(lon))


def _nombre_etopo(lat, lon):
    # ETOPO nombra por la esquina NOROESTE: la tesela de 15-30 N, 75-60 W es N30W075.
    n = lat + 15
    return "ETOPO_2022_v1_15s_%s%02d%s%03d_surface.tif" % (
        "N" if n >= 0 else "S", abs(n), "W" if lon < 0 else "E", abs(lon))


def a_lat_lon(px, pz, origen, escala):
    """Inversa de `Archipielago.de_lat_lon`: equirrectangular centrada en `origen`."""
    lat = origen[0] + (-pz / escala) / M_POR_GRADO
    lon = origen[1] + (px / escala) / (M_POR_GRADO * math.cos(math.radians(origen[0])))
    return lat, lon


def alturas_celda(cx, cz, polis, a, b, cubos, cotas, eles, dem=None):
    """Las dos capas de la celda: base (m de juego) y relieve (m REALES), LADO × LADO cada una."""
    x0, z0 = cx * CELDA, cz * CELDA
    alc = int(math.ceil(ALCANCE_TIERRA / CELDA))
    idx = set()
    for i in range(cx - alc, cx + alc + 1):
        for j in range(cz - alc, cz + alc + 1):
            idx.update(cubos.get((i, j), []))
    idx = np.array(sorted(idx), dtype=np.int64)
    gx, gz = np.meshgrid(x0 + np.arange(LADO) * PASO, z0 + np.arange(LADO) * PASO)
    px, pz = gx.ravel(), gz.ravel()
    d = _distancia(px, pz, a[idx], b[idx]).reshape(LADO, LADO) if len(idx) else np.full((LADO, LADO), np.inf)
    dueño = _dueno(polis, x0, z0)
    tierra = dueño >= 0
    d_in = np.minimum(d, ALCANCE_TIERRA)
    s = np.clip(d_in / PLAYA, 0, 1)
    playa = COTA_PLAYA * s * s * (3 - 2 * s)
    h_agua = np.where(d < PLATAFORMA, -d * PEND_PLATAFORMA,
                      np.maximum(-PLATAFORMA * PEND_PLATAFORMA - (d - PLATAFORMA) * PEND_TALUD, FONDO))

    # El cerro sintético, en metros REALES (la cota de la lista lo es): lo que queda donde no hay mapa.
    cota = np.where(tierra, cotas[np.maximum(dueño, 0)], 0.0) / ESCALA_ALTURA
    ele = np.where(tierra, eles[np.maximum(dueño, 0)], 1.0)
    n = _ruido(px, pz).reshape(LADO, LADO)
    cerro = np.maximum(cota - COTA_PLAYA / ESCALA_ALTURA, 0) * (1 - np.exp(-np.maximum(d_in - PLAYA, 0) / ele))
    peso = np.clip((d_in - PLAYA) / (2 * PLAYA), 0, 1)
    real = np.maximum(cerro * (1 + 0.45 * n * peso), 0)

    if dem is not None:
        lat, lon = a_lat_lon(px, pz, dem["origen"], dem["escala"])
        lat, lon = lat.reshape(LADO, LADO), lon.reshape(LADO, LADO)
        tierra_real = dem["tierra"].muestrear(lat, lon)
        fondo_real = dem["fondo"].muestrear(lat, lon)
        # Tierra: el relieve real, fundido a cero en la orilla para que la costa siga siendo la de OSM
        # (los dos mapas no coinciden al metro). Sin tesela de Copernicus queda el sintético.
        f = np.clip((d_in - PLAYA) / ORILLA, 0, 1)
        f = f * f * (3 - 2 * f)
        real = np.where(np.isnan(tierra_real), real, np.maximum(np.nan_to_num(tierra_real), 0.0) * f)
        # Fondo: la profundidad REAL en metros de juego (el calado es real), con su tope, fundida desde
        # la rampa de la orilla —que es la que casa con la costa— y nunca más somera que ella. La
        # rampa también lleva el tope: sin él seguía bajando lejos de la costa (−72 m el 23-10-2026).
        hondo = np.clip(np.nan_to_num(fondo_real, nan=FONDO), FONDO, -0.5)
        g = np.clip(d / (3 * PLATAFORMA), 0, 1)
        rampa = np.maximum(-np.minimum(d, 1e4) * PEND_PLATAFORMA, FONDO)
        h_agua = np.where(np.isnan(fondo_real), h_agua, np.minimum(h_agua * (1 - g) + hondo * g, rampa))
    base = np.where(tierra, playa, h_agua).astype(np.float32)
    real = np.where(tierra, real, 0.0).astype(np.float32)
    return base, real


_G = {}


def _iniciar():
    d, polis, nombres = cargar()
    a, b, cubos, cotas, eles = preparar(polis, nombres)
    dem = {"origen": d["origen"], "escala": d["escala"],
           "tierra": Mosaico(os.path.join(DEM, "copernicus_glo90"), _nombre_copernicus, 1, 12),   # 6 MB
           "fondo": Mosaico(os.path.join(DEM, "etopo2022"), _nombre_etopo, 15, 3)}                # 52 MB
    _G.update(polis=polis, a=a, b=b, cubos=cubos, cotas=cotas, eles=eles, dem=dem)


def _trabajar(c):
    cx, cz = c
    base, real = alturas_celda(cx, cz, _G["polis"], _G["a"], _G["b"], _G["cubos"], _G["cotas"],
                               _G["eles"], _G["dem"])
    # Las dos capas seguidas, base y relieve: `Relieve` lo sabe por "capas" en el índice.
    with gzip.open(os.path.join(SALIDA, "c_%d_%d.alt" % (cx, cz)), "wb", compresslevel=6) as f:
        f.write(base.astype(np.float16).tobytes())
        f.write(real.astype(np.float16).tobytes())
    basto = (base[::BASTO, ::BASTO].astype(np.float16).tobytes()
             + real[::BASTO, ::BASTO].astype(np.float16).tobytes())
    # Para descartar las celdas que son solo fondo vale cualquier escala: la tierra está sobre cero.
    h = base + real * ESCALA_ALTURA
    return cx, cz, float(h.min()), float(h.max()), basto


def celdas_necesarias(d, polis):
    """Celdas con tierra o a menos de ALCANCE_AGUA de ella (el fondo somero también cuenta)."""
    x0, z0, w, h = d["mundo"]
    hay = set()
    m = ALCANCE_AGUA
    for p in polis:
        lo = np.floor((p.min(0) - m) / CELDA).astype(int)
        hi = np.floor((p.max(0) + m) / CELDA).astype(int)
        # Las islas pequeñas caben en pocas celdas; las grandes se filtran luego por contenido.
        for cx in range(lo[0], hi[0] + 1):
            for cz in range(lo[1], hi[1] + 1):
                if x0 <= cx * CELDA < x0 + w and z0 <= cz * CELDA < z0 + h:
                    hay.add((cx, cz))
    return sorted(hay)


def main():
    d, polis, nombres = cargar()
    os.makedirs(SALIDA, exist_ok=True)
    parcial = len(sys.argv) > 2
    if parcial and sys.argv[1] == "zona":
        la0, la1, lo0, lo1 = (float(v) for v in sys.argv[2].split(","))
        o, e = d["origen"], d["escala"]
        xs = sorted((lo - o[1]) * M_POR_GRADO * math.cos(math.radians(o[0])) * e for lo in (lo0, lo1))
        zs = sorted(-(la - o[0]) * M_POR_GRADO * e for la in (la0, la1))
        lista = [c for c in celdas_necesarias(d, polis)
                 if xs[0] <= (c[0] + 0.5) * CELDA <= xs[1] and zs[0] <= (c[1] + 0.5) * CELDA <= zs[1]]
    elif parcial:
        lista = [tuple(int(v) for v in s.split(",")) for s in sys.argv[2:]]
    else:
        lista = celdas_necesarias(d, polis)
    print("%d celdas candidatas" % len(lista))
    resultado = []
    with Pool(processes=max(os.cpu_count() - 2, 1), initializer=_iniciar) as pool:
        for i, r in enumerate(pool.imap_unordered(_trabajar, lista, chunksize=4)):
            resultado.append(r)
            if i % 200 == 0:
                print("  %d / %d" % (i, len(lista)), flush=True)
    # Fuera las celdas que resultan ser solo fondo: no hay nada que dibujar ni en qué varar.
    utiles = {}
    for cx, cz, lo, hi, basto in resultado:
        if hi > -3.0:
            utiles[(cx, cz)] = ({"c": [cx, cz], "min": round(lo, 2), "max": round(hi, 2), "capas": 2},
                                basto)
        else:
            os.remove(os.path.join(SALIDA, "c_%d_%d.alt" % (cx, cz)))
    ruta = os.path.join(SALIDA, "indice.json")
    bastos = os.path.join(SALIDA, "basto.bin")
    todas = {}
    if parcial and os.path.exists(ruta):
        # Regenerar unas pocas celdas conserva las demás, con las capas que tengan (sin "capas", 1:
        # las de antes de las alturas reales, con la escala vertical ya aplicada).
        viejo = json.load(open(ruta))["celdas"]
        crudo = open(bastos, "rb").read()
        n = (LADO - 1) // BASTO + 1
        pos = 0
        for e in viejo:
            largo = n * n * 2 * e.get("capas", 1)
            todas[tuple(e["c"])] = (e, crudo[pos:pos + largo])
            pos += largo
    # Las regeneradas que ahora son solo fondo se van también del índice: su fichero ya no existe.
    for c in lista:
        if tuple(c) not in utiles:
            todas.pop(tuple(c), None)
    todas.update(utiles)
    orden = sorted(todas)
    json.dump({"celda": CELDA, "paso": PASO, "lado": LADO, "basto": BASTO,
               "escala_altura": ESCALA_ALTURA, "fuente": d["fuente"],
               "celdas": [todas[c][0] for c in orden]}, open(ruta, "w"))
    with open(bastos, "wb") as f:
        for c in orden:
            f.write(todas[c][1])
    print("%d celdas con relieve útil (de %d candidatas)" % (len(utiles), len(lista)))


if __name__ == "__main__":
    main()
