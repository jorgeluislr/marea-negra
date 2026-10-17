"""Costas del Caribe a escala de juego, desde los polígonos de tierra de OpenStreetMap.

    "C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" blender_src/costas_caribe.py

Se corre con el Python de Blender porque es el que trae numpy; no usa bpy.

Entrada: `fuentes/crudo/osm/simplified-land-polygons-complete-3857.zip` (osmdata.openstreetmap.de,
© OpenStreetMap contributors, ODbL), polígonos de tierra en Mercator ya simplificados para zoom 0-9.
Salida: `fuentes/derivados/costas_caribe.json`, que lee `tools/hornear_islas.tscn`.

Qué hace:

1. Lee el shapefile a mano (struct): son polígonos tipo 5 y no hace falta más.
2. Se queda con lo que toca el rectángulo del Caribe; la tierra firme (América es UN polígono en este
   fichero) se recorta a ese rectángulo con Sutherland-Hodgman.
3. Lleva cada punto al mundo con la misma proyección que `Archipielago.de_lat_lon()`:
   equirrectangular centrada en `ORIGEN`, a escala `ESCALA` (1/25, decidido con el usuario el
   17-10-2026). El norte es −Z.
4. Simplifica (Douglas-Peucker) a `TOLERANCIA` metros de JUEGO y descarta lo que no llega a
   `AREA_MIN`.
5. Pone nombre a las islas conocidas: el polígono que contiene el punto del nomenclátor.
"""
import json
import math
import os
import struct
import zipfile

import numpy as np

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZIP = os.path.join(RAIZ, "fuentes/crudo/osm/simplified-land-polygons-complete-3857.zip")
SALIDA = os.path.join(RAIZ, "fuentes/derivados/costas_caribe.json")

# Rectángulo del Caribe (lat, lon) y su proyección al juego.
LAT = (9.0, 27.5)
LON = (-88.0, -59.0)
# Origen del mundo: el Sir Francis Drake Channel, donde ya arranca el juego. Al centro del Caribe el
# barco nacería en tierra (Haití) y Norman Island quedaría a 38 km, más allá de lo que aguanta la
# precisión simple sin origen flotante.
ORIGEN = (18.385, -64.62)
ESCALA = 1.0 / 25.0
TOLERANCIA = 3.0      # m de juego (75 m reales)
AREA_MIN = 30.0       # m² de juego
CERCA = 200.0         # m de juego: hasta dónde se busca la isla de un nombre que cae en el agua
M_POR_GRADO = 111320.0
R_MERCATOR = 6378137.0

# Nomenclátor: un punto DENTRO de cada isla con nombre, en (lat, lon).
NOMBRES = {
    "Cuba": (22.0, -79.0), "Isla de la Juventud": (21.7, -82.8), "Jamaica": (18.1, -77.3),
    "La Española": (18.9, -71.0), "Puerto Rico": (18.2, -66.5), "Vieques": (18.12, -65.45),
    "Culebra": (18.31, -65.29), "Saint Thomas": (18.34, -64.93), "Saint John": (18.33, -64.74),
    "Saint Croix": (17.73, -64.75), "Tortola": (18.43, -64.62), "Virgen Gorda": (18.48, -64.40),
    "Anegada": (18.73, -64.33), "Jost Van Dyke": (18.45, -64.75), "Norman Island": (18.317, -64.617),
    "Anguila": (18.22, -63.05), "San Martín": (18.07, -63.06), "San Bartolomé": (17.9, -62.83),
    "Saba": (17.63, -63.24), "San Eustaquio": (17.49, -62.98), "San Cristóbal": (17.3, -62.73),
    "Nieves": (17.15, -62.58), "Barbuda": (17.63, -61.8), "Antigua": (17.08, -61.8),
    "Montserrat": (16.74, -62.19), "Guadalupe": (16.15, -61.68), "María Galante": (15.93, -61.27),
    "Dominica": (15.42, -61.35), "Martinica": (14.64, -61.02), "Santa Lucía": (13.9, -60.97),
    "San Vicente": (13.25, -61.2), "Bequia": (13.01, -61.23), "Barbados": (13.17, -59.55),
    "Granada": (12.12, -61.68), "Carriacou": (12.48, -61.45), "Tobago": (11.25, -60.68),
    "Trinidad": (10.45, -61.25), "Aruba": (12.52, -69.97), "Curazao": (12.17, -68.98),
    "Bonaire": (12.15, -68.27), "Margarita": (11.0, -63.95), "La Tortuga": (20.03, -72.78),
    "Gonâve": (18.85, -73.05), "Saona": (18.15, -68.67), "Mona": (18.08, -67.9),
    "Gran Caimán": (19.32, -81.24), "Caimán Brac": (19.72, -79.8), "Pequeño Caimán": (19.68, -80.05),
    "Roatán": (16.33, -86.53), "Utila": (16.1, -86.92), "Guanaja": (16.45, -85.9),
    "Cozumel": (20.42, -86.92), "Isla Mujeres": (21.23, -86.73), "San Andrés": (12.55, -81.72),
    "Providencia": (13.35, -81.37), "Providenciales": (21.78, -72.27), "Gran Turca": (21.47, -71.14),
    "Gran Inagua": (21.1, -73.3), "Andros": (24.4, -78.0), "Nueva Providencia": (25.04, -77.35),
    "Gran Bahama": (26.65, -78.4), "Eleuthera": (25.2, -76.2), "Ábaco": (26.4, -77.1),
    "Long Island": (23.2, -75.1), "Gran Exuma": (23.5, -75.8), "Cat Island": (24.4, -75.5),
    "La Tortuga (Venezuela)": (10.94, -65.3), "Tierra Firme": (10.0, -66.0),
}


def mercator_a_lat_lon(x, y):
    lon = np.degrees(x / R_MERCATOR)
    lat = np.degrees(2.0 * np.arctan(np.exp(y / R_MERCATOR)) - math.pi / 2.0)
    return lat, lon


def lat_lon_a_mundo(lat, lon):
    este = (lon - ORIGEN[1]) * M_POR_GRADO * math.cos(math.radians(ORIGEN[0]))
    norte = (lat - ORIGEN[0]) * M_POR_GRADO
    return np.stack([este * ESCALA, -norte * ESCALA], axis=-1)


def leer_poligonos(datos):
    """Anillos de cada registro tipo 5 cuya caja toca el Caribe, en (lat, lon)."""
    lo = mercator_inverso(LAT[0], LON[0])
    hi = mercator_inverso(LAT[1], LON[1])
    pos = 100
    anillos = []
    while pos < len(datos):
        _, largo = struct.unpack(">ii", datos[pos:pos + 8])
        cuerpo = datos[pos + 8:pos + 8 + largo * 2]
        pos += 8 + largo * 2
        tipo = struct.unpack("<i", cuerpo[:4])[0]
        if tipo != 5:
            continue
        xmin, ymin, xmax, ymax = struct.unpack("<4d", cuerpo[4:36])
        if xmax < lo[0] or xmin > hi[0] or ymax < lo[1] or ymin > hi[1]:
            continue
        npartes, npuntos = struct.unpack("<2i", cuerpo[36:44])
        partes = list(struct.unpack("<%di" % npartes, cuerpo[44:44 + 4 * npartes])) + [npuntos]
        pts = np.frombuffer(cuerpo[44 + 4 * npartes:44 + 4 * npartes + 16 * npuntos],
                            dtype="<f8").reshape(-1, 2)
        for a, b in zip(partes[:-1], partes[1:]):
            anillo = pts[a:b]
            # En shapefile el anillo exterior va en sentido HORARIO; los huecos (lagos), al revés.
            if _area(anillo) < 0:
                anillos.append(anillo)
    return anillos


def mercator_inverso(lat, lon):
    x = math.radians(lon) * R_MERCATOR
    y = math.log(math.tan(math.pi / 4.0 + math.radians(lat) / 2.0)) * R_MERCATOR
    return x, y


def _area(p):
    x, y = p[:, 0], p[:, 1]
    return 0.5 * float(np.dot(x, np.roll(y, -1)) - np.dot(np.roll(x, -1), y))


def recortar(p, x0, z0, x1, z1):
    """Sutherland-Hodgman contra el rectángulo del mundo."""
    def corta(puntos, dentro, cruce):
        out = []
        n = len(puntos)
        for i in range(n):
            a, b = puntos[i - 1], puntos[i]
            da, db = dentro(a), dentro(b)
            if db:
                if not da:
                    out.append(cruce(a, b))
                out.append(b)
            elif da:
                out.append(cruce(a, b))
        return out

    def en_x(x):
        return lambda a, b: (x, a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0]))

    def en_z(z):
        return lambda a, b: (a[0] + (b[0] - a[0]) * (z - a[1]) / (b[1] - a[1]), z)

    pts = [tuple(q) for q in p]
    pts = corta(pts, lambda q: q[0] >= x0, en_x(x0))
    if pts: pts = corta(pts, lambda q: q[0] <= x1, en_x(x1))
    if pts: pts = corta(pts, lambda q: q[1] >= z0, en_z(z0))
    if pts: pts = corta(pts, lambda q: q[1] <= z1, en_z(z1))
    return np.array(pts) if len(pts) >= 3 else None


def simplificar(p, tol):
    """Douglas-Peucker sobre un anillo cerrado, iterativo."""
    if len(p) < 4:
        return p
    # Se parte por los dos puntos más alejados para que el anillo no colapse.
    i0 = 0
    i1 = int(np.argmax(np.sum((p - p[0]) ** 2, axis=1)))
    guardar = np.zeros(len(p), bool)
    guardar[[i0, i1]] = True
    pila = [(i0, i1), (i1, len(p))]
    ext = np.vstack([p, p[:1]])
    while pila:
        a, b = pila.pop()
        if b - a < 2:
            continue
        seg = ext[a + 1:b]
        pa, pb = ext[a], ext[b]
        d = pb - pa
        largo = math.hypot(*d) or 1e-9
        dist = np.abs(d[0] * (seg[:, 1] - pa[1]) - d[1] * (seg[:, 0] - pa[0])) / largo
        k = int(np.argmax(dist))
        if dist[k] > tol:
            m = a + 1 + k
            guardar[m % len(p)] = True
            pila += [(a, m), (m, b)]
    return p[guardar]


def contiene(p, q):
    x, z = q
    dentro = False
    n = len(p)
    j = n - 1
    for i in range(n):
        xi, zi = p[i]
        xj, zj = p[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi:
            dentro = not dentro
        j = i
    return dentro


def main():
    z = zipfile.ZipFile(ZIP)
    datos = z.read("simplified-land-polygons-complete-3857/simplified_land_polygons.shp")
    anillos = leer_poligonos(datos)
    esquinas = lat_lon_a_mundo(np.array([LAT[1], LAT[0]]), np.array([LON[0], LON[1]]))
    x0, z0 = esquinas[0]
    x1, z1 = esquinas[1]
    islas = []
    for a in anillos:
        lat, lon = mercator_a_lat_lon(a[:, 0], a[:, 1])
        p = lat_lon_a_mundo(lat, lon)
        if p[:, 0].max() < x0 or p[:, 0].min() > x1 or p[:, 1].max() < z0 or p[:, 1].min() > z1:
            continue
        p = recortar(p, x0, z0, x1, z1)
        if p is None:
            continue
        p = simplificar(p, TOLERANCIA)
        if len(p) < 3 or abs(_area(p)) < AREA_MIN:
            continue
        islas.append({"puntos": p})

    sin_nombre = 0
    for nombre, (lat, lon) in NOMBRES.items():
        q = lat_lon_a_mundo(np.array(lat), np.array(lon))
        dueñas = [i for i in islas if "nombre" not in i
                  and i["puntos"][:, 0].min() <= q[0] <= i["puntos"][:, 0].max()
                  and i["puntos"][:, 1].min() <= q[1] <= i["puntos"][:, 1].max()
                  and contiene(i["puntos"], q)]
        if not dueñas:
            # El punto del nomenclátor cae en el agua (isla estrecha, o el punto es aproximado):
            # se nombra la más cercana, si está a menos de CERCA metros de juego.
            libres = [i for i in islas if "nombre" not in i]
            dist = [float(np.min(np.hypot(*(i["puntos"] - q).T))) for i in libres]
            if dist and min(dist) < CERCA:
                dueñas = [libres[int(np.argmin(dist))]]
        if dueñas:
            dueñas[0]["nombre"] = nombre
        else:
            print("  sin polígono para", nombre)
    for i in islas:
        if "nombre" not in i:
            sin_nombre += 1
            i["nombre"] = ""

    salida = {
        "fuente": "© OpenStreetMap contributors, ODbL — simplified-land-polygons-complete-3857",
        "origen": ORIGEN, "escala": ESCALA,
        "mundo": [float(x0), float(z0), float(x1 - x0), float(z1 - z0)],
        "islas": [{"nombre": i["nombre"], "puntos": np.round(i["puntos"], 2).tolist()}
                  for i in sorted(islas, key=lambda i: -abs(_area(i["puntos"])))],
    }
    os.makedirs(os.path.dirname(SALIDA), exist_ok=True)
    with open(SALIDA, "w", encoding="utf-8") as f:
        json.dump(salida, f, ensure_ascii=False)
    total = sum(len(i["puntos"]) for i in islas)
    print("mundo %.1f × %.1f km, %d polígonos (%d sin nombre), %d puntos"
          % ((x1 - x0) / 1000, (z1 - z0) / 1000, len(islas), sin_nombre, total))
    for i in salida["islas"][:12]:
        p = np.array(i["puntos"])
        print("  %-22s %6d pts  %7.1f × %6.1f km" % (i["nombre"] or "-", len(p),
              np.ptp(p[:, 0]) / 1000, np.ptp(p[:, 1]) / 1000))


if __name__ == "__main__":
    main()
