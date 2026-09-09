"""Deja un `.wav` descargado en un formato que Godot importa, y mide si sirve como bucle.

Hace falta más de lo que parece: de las dos primeras descargas, una venía en **PCM de 24 bits**
y la otra en **IEEE float de 32 bits**, y el importador de Godot solo admite PCM de 8 y 16 bits
(el de 24 lo tragó, el float no). Aquí se normaliza todo a **16 bits** sin tocar la frecuencia
de muestreo, que Godot respeta.

El `wave` de la biblioteca estándar no lee float (`unknown format: 3`), así que los chunks se
recorren a mano.

Necesita numpy: se ejecuta desde el Python de Blender, igual que `sintetizar_sfx.py`.

    import sys; sys.path.insert(0, r"...\\audio_src")
    import preparar_wav
    preparar_wav.convertir(origen, destino)
"""

import os
import struct
import wave

import numpy as np


def leer_wav(ruta: str) -> tuple:
    """Devuelve (datos float64 en [-1,1] con forma [n, canales], frecuencia)."""
    b = np.fromfile(ruta, dtype=np.uint8)
    if bytes(b[0:4]) != b"RIFF" or bytes(b[8:12]) != b"WAVE":
        raise ValueError("no es un RIFF/WAVE: %s" % ruta)
    i = 12
    fmt = canales = bits = 0
    hz = 0
    datos = None
    while i < len(b) - 8:
        ident = bytes(b[i:i + 4])
        tam = int(struct.unpack("<I", bytes(b[i + 4:i + 8]))[0])
        cuerpo = b[i + 8:i + 8 + tam]
        if ident == b"fmt ":
            fmt, canales, hz, _, _, bits = struct.unpack("<HHIIHH", bytes(cuerpo[:16]))
            if fmt == 0xFFFE and tam >= 40:
                # WAVE_FORMAT_EXTENSIBLE: el formato real son los 2 primeros bytes del GUID.
                fmt = int(struct.unpack("<H", bytes(cuerpo[24:26]))[0])
        elif ident == b"data":
            datos = cuerpo
        i += 8 + tam + (tam % 2)
    if datos is None or canales == 0:
        raise ValueError("faltan chunks fmt/data en %s" % ruta)

    if fmt == 3 and bits == 32:
        x = datos.view("<f4").astype(np.float64)
    elif fmt == 3 and bits == 64:
        x = datos.view("<f8").astype(np.float64)
    elif fmt == 1 and bits == 16:
        x = datos.view("<i2").astype(np.float64) / 32768.0
    elif fmt == 1 and bits == 8:
        x = (datos.astype(np.float64) - 128.0) / 128.0
    elif fmt == 1 and bits == 24:
        # 3 bytes por muestra: se rellena a 4 respetando el signo.
        n = len(datos) // 3
        t = datos[: n * 3].reshape(n, 3)
        z = np.zeros((n, 4), dtype=np.uint8)
        z[:, 1:] = t
        x = z.view("<i4").ravel().astype(np.float64) / (2.0 ** 31)
    else:
        raise ValueError("formato %d de %d bits no contemplado" % (fmt, bits))
    return x.reshape(-1, canales), int(hz)


def escribir_wav16(ruta: str, x: np.ndarray, hz: int) -> None:
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(ruta, "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(hz)
        w.writeframes(pcm.tobytes())


def costura(x: np.ndarray) -> float:
    """Cuánto salta del último sample al primero, en veces un salto típico del archivo.

    ≈1 significa que el empalme del bucle es indistinguible de cualquier otro punto. Mucho más
    que eso y se va a oír un chasquido en cada vuelta.
    """
    c = x[:, 0]
    tipico = float(np.mean(np.abs(np.diff(c))))
    return float(abs(c[0] - c[-1])) / max(tipico, 1e-12)


def hacer_bucle(x: np.ndarray, hz: int, cruce_ms: float = 300.0) -> np.ndarray:
    """Empalma el final con el principio para que el bucle no chasquee.

    Una grabación de campo casi nunca cierra sola, por muy 'loop' que diga la etiqueta. Se
    recorta la cola y se funde ENCIMA del principio: así el nuevo final enlaza con el nuevo
    principio por construcción. Cuesta `cruce_ms` de duración.
    """
    n = x.shape[0]
    L = int(hz * cruce_ms / 1000.0)
    if L < 8 or 2 * L >= n:
        return x
    y = x[: n - L].copy()
    f = np.linspace(0.0, 1.0, L)[:, None]
    y[:L] = x[n - L:] * (1.0 - f) + y[:L] * f
    return y


def recortar_silencio(x: np.ndarray, hz: int, umbral_db: float = -50.0,
                      margen_ms: float = 5.0, umbral_cola_db: float = -60.0) -> tuple:
    """Quita el silencio del principio y del final. Devuelve (x, segundos_cortados_delante).

    Muchas grabaciones traen medio segundo de nada al principio, y en un efecto disparado por
    una acción del jugador eso se oye como retraso. El umbral es RELATIVO al pico del archivo,
    así que funciona igual con material fuerte o flojo, y se deja `margen_ms` antes del primer
    sonido para no comerse el ataque.
    """
    env = np.max(np.abs(x), axis=1)
    pico = float(env.max())
    if pico < 1e-9:
        return x, 0.0
    # Los dos extremos NO se cortan igual, y esto importa: delante hay que ser duro, porque
    # una rampa inaudible se percibe como retraso al disparar el efecto; detrás hay que ser
    # suave, o te llevas por delante la caída natural del sonido y queda un corte seco.
    cabeza = np.nonzero(env > pico * (10.0 ** (umbral_db / 20.0)))[0]
    cola = np.nonzero(env > pico * (10.0 ** (umbral_cola_db / 20.0)))[0]
    if cabeza.size == 0 or cola.size == 0:
        return x, 0.0
    margen = int(hz * margen_ms / 1000.0)
    ini = max(int(cabeza[0]) - margen, 0)
    fin = min(int(cola[-1]) + margen, x.shape[0])
    return x[ini:fin], ini / float(hz)


def convertir(origen: str, destino: str, pico: float = 0.0, cruce_ms: float = 0.0,
              recortar: bool = False, umbral_db: float = -50.0) -> dict:
    """`pico` > 0 normaliza; `cruce_ms` > 0 cierra el bucle; `recortar` quita los silencios.

    Ojo con `umbral_db`: −50 quita solo el silencio digital, y muchas grabaciones siguen con
    una rampa casi inaudible durante décimas de segundo. Para un efecto que dispara el jugador
    eso se oye como retraso; ahí hay que subir el umbral (−24 o −20) para empezar donde hay
    energía de verdad. Mídelo antes con el perfil de la envolvente, no lo elijas a ojo.
    """
    x, hz = leer_wav(origen)
    cortado = 0.0
    if recortar:
        x, cortado = recortar_silencio(x, hz, umbral_db)  # la cola va a -60 dB por defecto
    if cruce_ms > 0.0:
        x = hacer_bucle(x, hz, cruce_ms)
    antes = float(np.max(np.abs(x)))
    if pico > 0.0 and antes > 1e-9:
        x = x * (pico / antes)
    escribir_wav16(destino, x, hz)
    return {
        "archivo": os.path.basename(destino),
        "hz": hz,
        "canales": int(x.shape[1]),
        "seg": round(x.shape[0] / float(hz), 2),
        "mb": round(os.path.getsize(destino) / 1048576.0, 1),
        "pico": round(float(np.max(np.abs(x))), 3),
        "rms_db": round(20.0 * np.log10(max(float(np.sqrt(np.mean(x ** 2))), 1e-9)), 1),
        "costura": round(costura(x), 2),
        "silencio_cortado_s": round(cortado, 3),
    }
