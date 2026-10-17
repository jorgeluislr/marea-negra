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

La cota de cada isla con nombre es la de su pico real a la escala de altura (1/8); las demás, una
estimación por su área. El cerro sube con `1 − e^(−d/L)` y L escala con la isla: con una L fija un
islote salía plano y Cuba, una aguja.
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
FONDO = -25.0

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


def _distancia(px, pz, a, b):
    """Distancia mínima de cada punto a los tramos (a, b), por trozos para no reventar memoria."""
    d = np.full(px.shape, np.inf)
    ab = b - a
    largo2 = np.maximum((ab ** 2).sum(1), 1e-12)
    for i in range(0, len(a), 256):
        sa, sab, sl = a[i:i + 256], ab[i:i + 256], largo2[i:i + 256]
        rx = px[:, None] - sa[None, :, 0]
        rz = pz[:, None] - sa[None, :, 1]
        t = np.clip((rx * sab[None, :, 0] + rz * sab[None, :, 1]) / sl[None, :], 0.0, 1.0)
        dx = rx - t * sab[None, :, 0]
        dz = rz - t * sab[None, :, 1]
        d = np.minimum(d, np.sqrt(dx * dx + dz * dz).min(axis=1))
    return d


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


def alturas_celda(cx, cz, polis, a, b, cubos, cotas, eles):
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
    cota = np.where(tierra, cotas[np.maximum(dueño, 0)], 0.0)
    ele = np.where(tierra, eles[np.maximum(dueño, 0)], 1.0)
    d_in = np.minimum(d, ALCANCE_TIERRA)
    n = _ruido(px, pz).reshape(LADO, LADO)
    s = np.clip(d_in / PLAYA, 0, 1)
    playa = COTA_PLAYA * s * s * (3 - 2 * s)
    cerro = np.maximum(cota - COTA_PLAYA, 0) * (1 - np.exp(-np.maximum(d_in - PLAYA, 0) / ele))
    peso = np.clip((d_in - PLAYA) / (2 * PLAYA), 0, 1)
    h_tierra = playa + np.maximum(cerro * (1 + 0.45 * n * peso), 0)
    h_agua = np.where(d < PLATAFORMA, -d * PEND_PLATAFORMA,
                      np.maximum(-PLATAFORMA * PEND_PLATAFORMA - (d - PLATAFORMA) * PEND_TALUD, FONDO))
    return np.where(tierra, h_tierra, h_agua).astype(np.float32)


_G = {}


def _iniciar():
    d, polis, nombres = cargar()
    a, b, cubos, cotas, eles = preparar(polis, nombres)
    _G.update(polis=polis, a=a, b=b, cubos=cubos, cotas=cotas, eles=eles)


def _trabajar(c):
    cx, cz = c
    h = alturas_celda(cx, cz, _G["polis"], _G["a"], _G["b"], _G["cubos"], _G["cotas"], _G["eles"])
    with gzip.open(os.path.join(SALIDA, "c_%d_%d.alt" % (cx, cz)), "wb", compresslevel=6) as f:
        f.write(h.astype(np.float16).tobytes())
    basto = h[::BASTO, ::BASTO]
    return cx, cz, float(h.min()), float(h.max()), basto.astype(np.float16).tobytes()


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
    if len(sys.argv) > 2:
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
            utiles[(cx, cz)] = ({"c": [cx, cz], "min": round(lo, 2), "max": round(hi, 2)}, basto)
        else:
            os.remove(os.path.join(SALIDA, "c_%d_%d.alt" % (cx, cz)))
    ruta = os.path.join(SALIDA, "indice.json")
    bastos = os.path.join(SALIDA, "basto.bin")
    todas = {}
    if len(sys.argv) > 2 and os.path.exists(ruta):
        # Regenerar unas pocas celdas conserva las demás.
        viejo = json.load(open(ruta))["celdas"]
        crudo = open(bastos, "rb").read()
        n = (LADO - 1) // BASTO + 1
        for i, e in enumerate(viejo):
            todas[tuple(e["c"])] = (e, crudo[i * n * n * 2:(i + 1) * n * n * 2])
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
