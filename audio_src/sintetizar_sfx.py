"""Sintetiza las camas de sonido continuas de Marea Negra a `assets/audio/`.

Solo las que se sintetizan BIEN, que son las de banda ancha: viento, mar, flameo de lona y
agua en el costado. Físicamente son ruido filtrado, así que generarlas no es imitar un sonido
sino producir el mismo fenómeno. Los crujidos de madera, los motones, los pasos y la cadena NO
están aquí a propósito: son fricción de stick-slip y sonarían a sintetizador; ésos se graban o
se compran (ver `assets/audio/PROCEDENCIA.md`).

Necesita numpy. El Python del sistema no lo tiene, pero **el de Blender sí**, así que se ejecuta
desde ahí:

    import sys; sys.path.insert(0, r"E:\\Godot\\Game3D\\marea_negra\\audio_src")
    import sintetizar_sfx; sintetizar_sfx.main(r"E:\\Godot\\Game3D\\marea_negra\\assets\\audio")

**Todo sale en bucle perfecto, y no por casualidad.** El filtrado se hace multiplicando el
espectro completo (`filtra`), que es una convolución CIRCULAR: el resultado es periódico con el
largo del archivo, así que el final casa con el principio sin costura. Las envolventes de
modulación se construyen igual, y los eventos sueltos (roturas de ola, golpes de lona) se
colocan con índice módulo n, de modo que el que cruza el final continúa al principio.
"""

import os
import wave

import numpy as np

SR = 44100


def _rng(semilla: int) -> np.random.Generator:
    return np.random.default_rng(semilla)


def ruido(n: int, semilla: int) -> np.ndarray:
    return _rng(semilla).standard_normal(n)


def _respuesta(f: np.ndarray, lo: float, hi: float, orden: int) -> np.ndarray:
    """Magnitud tipo Butterworth: paso alto en `lo` y paso bajo en `hi`."""
    fs = np.maximum(f, 1e-9)
    hp = np.ones_like(fs) if lo <= 0.0 else 1.0 / np.sqrt(1.0 + (lo / fs) ** (2 * orden))
    lp = np.ones_like(fs) if hi <= 0.0 else 1.0 / np.sqrt(1.0 + (fs / hi) ** (2 * orden))
    return hp * lp


def filtra(x: np.ndarray, lo: float, hi: float, orden: int = 2) -> np.ndarray:
    """Paso banda por espectro. Circular a propósito: hace el bucle perfecto (ver cabecera)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    return np.fft.irfft(X * _respuesta(f, lo, hi, orden), n=len(x))


def resonancia(x: np.ndarray, f0: float, q: float, ganancia: float) -> np.ndarray:
    """Pico lorentziano. Es lo que convierte ruido agudo en SILBIDO."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    pico = 1.0 + ganancia / (1.0 + ((f - f0) / (f0 / q)) ** 2)
    return np.fft.irfft(X * pico, n=len(x))


def reson_barrido(x: np.ndarray, f_ini: float, f_fin: float, q: float) -> np.ndarray:
    """Resonador de dos polos cuya frecuencia central CAE de `f_ini` a `f_fin`.

    Es la pieza clave del latigazo. Un chasquido de látigo o de lona no es ruido de banda
    ancha: es un pliegue que viaja por el material, y eso se oye como una resonancia que baja
    de tono muy rápido. Con ruido filtrado plano suena a sintetizador; con esto, a restallido.

    Los coeficientes se calculan vectorizados y solo la recursión va en bucle, porque un IIR
    con la frecuencia variando no se puede vectorizar.
    """
    n = len(x)
    if n == 0:
        return x
    f = np.geomspace(max(f_ini, 20.0), max(f_fin, 20.0), n)
    r = np.exp(-np.pi * (f / q) / SR)
    th = 2.0 * np.pi * f / SR
    a1 = (2.0 * r * np.cos(th)).tolist()
    a2 = (-(r * r)).tolist()
    g = ((1.0 - r * r) * np.sin(th)).tolist()
    xs = x.tolist()
    y = [0.0] * n
    y1 = 0.0
    y2 = 0.0
    for i in range(n):
        y0 = g[i] * xs[i] + a1[i] * y1 + a2[i] * y2
        y2 = y1
        y1 = y0
        y[i] = y0
    return np.asarray(y)


def envolvente(n: int, hz: float, semilla: int, minimo: float = 0.0) -> np.ndarray:
    """Envolvente suave, periódica, en [minimo, 1]. Ruido pasado por un filtro muy bajo."""
    e = filtra(ruido(n, semilla), 0.0, hz, orden=1)
    e = e - e.min()
    m = e.max()
    if m > 1e-12:
        e = e / m
    return minimo + (1.0 - minimo) * e


def _evento(destino: np.ndarray, trozo: np.ndarray, inicio: int) -> None:
    """Suma un evento con envoltura circular, para que el bucle case."""
    n = len(destino)
    destino[(np.arange(len(trozo)) + inicio) % n] += trozo


def _golpe_env(largo: int, ataque: float, caida: float) -> np.ndarray:
    t = np.arange(largo) / SR
    return (1.0 - np.exp(-t / ataque)) * np.exp(-t / caida)


def norm(x: np.ndarray, pico: float = 0.72) -> np.ndarray:
    m = float(np.max(np.abs(x)))
    return x * (pico / m) if m > 1e-12 else x


# --------------------------------------------------------------------------- camas


def viento(dur: float, semilla: int, fuerte: bool) -> np.ndarray:
    """Cinco bandas fijas cuyas amplitudes respiran a ritmos distintos. El centro espectral se
    mueve solo, que es lo que hace un paso banda barrido pero sin filtro variable."""
    n = int(dur * SR)
    if fuerte:
        bandas = [(60, 180, 0.90), (180, 420, 1.00), (420, 900, 1.00),
                  (900, 1800, 0.70), (1800, 3600, 0.35)]
    else:
        bandas = [(60, 180, 0.25), (180, 420, 1.00), (420, 900, 0.80),
                  (900, 1800, 0.35), (1800, 3600, 0.12)]
    out = np.zeros(n)
    for i, (lo, hi, g) in enumerate(bandas):
        capa = filtra(ruido(n, semilla + i), lo, hi, orden=2)
        hz = 0.18 + 0.10 * i + (0.25 if fuerte else 0.0)
        capa *= envolvente(n, hz, semilla + 100 + i, minimo=0.25)
        out += g * capa
    if fuerte:
        # Silbido de la jarcia. Es la capa que hace que suene a barco y no a ventilador: solo
        # aparece con viento fuerte, y va al cuadrado para que entre y salga con las rachas.
        s = filtra(ruido(n, semilla + 50), 1500, 2600, orden=6)
        s = resonancia(s, 1950.0, 14.0, 8.0)
        s *= envolvente(n, 0.5, semilla + 60, minimo=0.0) ** 2
        out += 0.30 * s
    return out * envolvente(n, 0.12, semilla + 70, minimo=0.45)


def mar(dur: float, semilla: int) -> np.ndarray:
    """Tres capas: vaivén de fondo, roturas de ola y espuma."""
    n = int(dur * SR)
    base = filtra(ruido(n, semilla), 0.0, 420, orden=2)
    base *= envolvente(n, 0.09, semilla + 1, minimo=0.30)

    roturas = np.zeros(n)
    rg = _rng(semilla + 2)
    for k in range(max(3, int(dur * 0.9))):
        largo = int(rg.uniform(0.5, 1.4) * SR)
        b = filtra(ruido(largo, semilla + 300 + k), 350, 5200, orden=2)
        b *= _golpe_env(largo, 0.035, rg.uniform(0.22, 0.50))
        _evento(roturas, rg.uniform(0.5, 1.0) * b, int(rg.uniform(0, n)))

    espuma = filtra(ruido(n, semilla + 3), 2800, 12000, orden=2)
    espuma *= envolvente(n, 5.0, semilla + 4, minimo=0.15)
    return base + 0.55 * roturas + 0.18 * espuma


def latigazo(semilla: int, f_ini: float = 850.0, f_fin: float = 110.0, q: float = 5.0,
             cuerpo: float = 1.0, silbido: float = 0.16, techo: float = 1800.0) -> np.ndarray:
    """Golpe de lona con carácter de LÁTIGO, en tres partes.

    La primera versión era una ráfaga de ruido de banda ancha y sonaba sintética: demasiado
    ruidosa y demasiado aguda. Un restallido de lona no es ruido, así que ahora son:

    1. **silbido** corto que sube, el aire en el paño antes de restallar (flojo: el latigazo es
       el chasquido, no el siseo);
    2. **chasquido**, una excitación de 2 ms metida en un resonador cuya frecuencia cae de
       ~850 a ~110 Hz — esto es lo que suena a látigo;
    3. **cuerpo grave** de 45-170 Hz con caída larga, que es la masa del paño y lo que lo hace
       GRUESO.

    Y todo por debajo de `techo`: una lona grande no tiene agudos.
    """
    rg = _rng(semilla)
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    tc = rg.uniform(0.050, 0.080)          # instante del chasquido
    i0 = int(tc * SR)
    m = n - i0
    out = np.zeros(n)

    sil = filtra(ruido(n, semilla + 1), 300, 1300, orden=2)
    out += silbido * sil * np.where(t < tc, (t / max(tc, 1e-6)) ** 3, 0.0)

    exc = ruido(m, semilla + 2) * np.exp(-np.arange(m) / (0.0022 * SR))
    ch = reson_barrido(exc, f_ini * rg.uniform(0.85, 1.15), f_fin, q)
    out[i0:] += ch * np.exp(-np.arange(m) / (0.075 * SR))

    gr = filtra(ruido(m, semilla + 3), 45, 170, orden=2) * _golpe_env(m, 0.004, 0.17)
    out[i0:] += cuerpo * 1.1 * gr

    return filtra(out, 0.0, techo, orden=3)


def flameo(dur: float, semilla: int, **kw) -> np.ndarray:
    """Lona desventada: latigazos irregulares, 4-7 por segundo. La cadencia real se liga en
    Godot a cuánto está desventada la vela disparando los one-shots."""
    n = int(dur * SR)
    out = np.zeros(n)
    rg = _rng(semilla)
    t = 0.0
    k = 0
    while t < dur:
        _evento(out, rg.uniform(0.5, 1.0) * latigazo(semilla + 500 + k, **kw), int(t * SR))
        t += rg.uniform(0.14, 0.30)
        k += 1
    return out


def agua_casco(dur: float, semilla: int) -> np.ndarray:
    """Agua corriendo por el costado, más chapoteos sueltos."""
    n = int(dur * SR)
    base = filtra(ruido(n, semilla), 260, 4200, orden=2)
    base *= envolvente(n, 4.0, semilla + 1, minimo=0.35)
    granos = np.zeros(n)
    rg = _rng(semilla + 2)
    for k in range(int(dur * 14)):
        largo = int(rg.uniform(0.03, 0.10) * SR)
        b = filtra(ruido(largo, semilla + 400 + k), 1500, 7000, orden=2)
        b *= _golpe_env(largo, 0.003, 0.025)
        _evento(granos, rg.uniform(0.3, 1.0) * b, int(rg.uniform(0, n)))
    return base + 0.40 * granos


# --------------------------------------------------------------------------- salida


def guarda(ruta: str, canales: list) -> dict:
    datos = np.stack(canales, axis=-1)
    datos = np.clip(datos, -1.0, 1.0)
    pcm = (datos * 32767.0).astype("<i2")
    with wave.open(ruta, "wb") as w:
        w.setnchannels(len(canales))
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    x = canales[0]
    # Costura del bucle: si el filtrado circular funciona, el salto final->principio tiene que
    # ser del mismo orden que un salto cualquiera dentro del archivo.
    salto = abs(float(x[0] - x[-1]))
    tipico = float(np.mean(np.abs(np.diff(x))))
    return {
        "archivo": os.path.basename(ruta),
        "seg": round(len(x) / SR, 2),
        "canales": len(canales),
        "kb": round(os.path.getsize(ruta) / 1024),
        "pico": round(float(np.max(np.abs(x))), 3),
        "rms_db": round(20.0 * np.log10(max(float(np.sqrt(np.mean(x ** 2))), 1e-9)), 1),
        "costura_vs_salto_medio": round(salto / max(tipico, 1e-12), 2),
    }


def main(destino: str) -> list:
    os.makedirs(destino, exist_ok=True)
    inf = []

    # Dos camas de viento: Godot cruza entre ellas segun Viento.fuerza. Con una sola no hay
    # manera de que aparezca el silbido de la jarcia solo cuando sopla de verdad.
    for nombre, fuerte, sem in [("viento_calma", False, 11), ("viento_fuerte", True, 23)]:
        # Canales con semillas distintas para que haya anchura, pero la envolvente de rachas
        # es COMUN: si no, parecen dos vientos independientes en cada oreja.
        n = int(14.0 * SR)
        rachas = envolvente(n, 0.10, sem + 999, minimo=0.5)
        izq = viento(14.0, sem, fuerte) * rachas
        der = viento(14.0, sem + 7, fuerte) * rachas
        p = norm(np.concatenate([izq, der]), 0.72)
        inf.append(guarda(os.path.join(destino, nombre + ".wav"),
                          [p[:n].copy(), p[n:].copy()]))

    n = int(18.0 * SR)
    izq = mar(18.0, 31)
    der = mar(18.0, 47)
    p = norm(np.concatenate([izq, der]), 0.80)
    inf.append(guarda(os.path.join(destino, "mar.wav"), [p[:n].copy(), p[n:].copy()]))

    inf.append(guarda(os.path.join(destino, "flameo_vela.wav"),
                      [norm(flameo(6.0, 53, **SABORES["medio"]), 0.85)]))
    for i in range(4):
        inf.append(guarda(os.path.join(destino, "flameo_golpe_%d.wav" % (i + 1)),
                          [norm(latigazo(61 + i * 13, **SABORES["medio"]), 0.85)]))
    inf.append(guarda(os.path.join(destino, "agua_casco.wav"),
                      [norm(agua_casco(12.0, 71), 0.78)]))
    return inf


## Tres grosores del latigazo, para elegir de oído. Lo que los separa es dónde acaba el barrido
## de la resonancia y cuánto cuerpo grave llevan.
SABORES = {
    "grueso": dict(f_ini=700.0, f_fin=85.0, q=4.0, cuerpo=1.5, silbido=0.10, techo=1300.0),
    "medio": dict(f_ini=850.0, f_fin=110.0, q=5.0, cuerpo=1.0, silbido=0.16, techo=1800.0),
    "seco": dict(f_ini=1050.0, f_fin=150.0, q=7.0, cuerpo=0.6, silbido=0.22, techo=2600.0),
}


def comparar_flameo(destino: str) -> list:
    """Genera los tres sabores, golpe suelto y bucle, para escucharlos y elegir."""
    os.makedirs(destino, exist_ok=True)
    inf = []
    for nombre, kw in SABORES.items():
        inf.append(guarda(os.path.join(destino, "latigazo_%s.wav" % nombre),
                          [norm(latigazo(61, **kw), 0.85)]))
        inf.append(guarda(os.path.join(destino, "flameo_%s.wav" % nombre),
                          [norm(flameo(3.0, 53, **kw), 0.85)]))
    return inf
