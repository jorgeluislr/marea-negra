"""Sintetiza el cañonazo de Marea Negra a `assets/audio/`.

**Un cañonazo SÍ se sintetiza bien**, y eso no es obvio: la regla del proyecto
(`sintetizar_sfx.py`) es que se genera lo que físicamente es ruido filtrado y se graba lo que es
fricción de stick-slip. Un fogonazo cae del lado bueno — es una onda de choque más gas en
expansión, o sea presión y ruido de banda ancha —, mientras que un crujido de madera no.

Tres partes, y cada una responde a algo que pasa de verdad al disparar:

  · **El frente de choque.** El gas sale a más velocidad que el sonido y el frente sube en menos
    de un milisegundo. Eso es el ATAQUE, y es lo que hace que suene a golpe y no a explosión de
    película: si el ataque se suaviza, deja de ser un cañón.
  · **La bola de gas.** El propelente quemado se expande en una esfera, y **una esfera que crece
    resuena cada vez más grave**. Por eso el cuerpo se hace con `reson_barrido`, la resonancia
    que CAE de frecuencia: la misma herramienta que el latigazo de lona, pero aquí por una razón
    física distinta. Con ruido de banda plana sale un "pssh" de sintetizador.
  · **El retumbo.** Lo que vuelve por reflexión en el agua y lo que queda tras absorberse los
    agudos en el aire — el aire se come las frecuencias altas con la distancia, así que la cola
    de cualquier estampido lejano es SOLO grave. Ése es el release bajo y lento.

**El orden importa: ruido → filtro → envolvente, nunca al revés.** `filtra` multiplica el
espectro completo, o sea que es una convolución CIRCULAR. Sobre ruido estacionario da igual (es
lo que hace que las camas queden en bucle perfecto), pero si se filtra una señal YA envuelta, la
cola da la vuelta y aparece **antes** del disparo: un pre-eco audible delante del golpe, que es
justo lo contrario de un ataque limpio.

Se ejecuta desde el Python de BLENDER, que trae numpy (el del sistema no):

    import sys; sys.path.insert(0, r"E:\\Godot\\Game3D\\marea_negra\\audio_src")
    import sintetizar_canon; sintetizar_canon.main(r"E:\\Godot\\Game3D\\marea_negra\\assets\\audio")

Salen VARIAS tomas con semillas distintas. Una andanada son cuatro piezas casi a la vez, y con
un solo archivo repetido suena a ametralladora: el oído caza la repetición exacta al instante.
"""

import os

import numpy as np

from sintetizar_sfx import SR, filtra, guarda, norm, reson_barrido, ruido


## Sabores, para elegir de oído. Lo que los separa es dónde acaba el barrido de la bola de gas
## (más bajo = pieza más gorda) y cuánto dura el retumbo.
##
## La referencia: una pieza de a 3 libras como la de la balandra es artillería MENUDA — tubo de
## 1,86 m y 76 mm de calibre—, así que no suena como un 32 de batería de costa. "media" es la
## que le corresponde; "gorda" queda para el día que haya un navío, y "seca" es la misma pieza
## oída de cerca y a barlovento, donde el retumbo no vuelve.
SABORES = {
    "seca": dict(f_ini=420.0, f_fin=70.0, q=2.5, cuerpo=0.22, cola=1.1, grave=150.0,
                 chasquido=0.30),
    "media": dict(f_ini=320.0, f_fin=52.0, q=2.0, cuerpo=0.34, cola=2.0, grave=120.0,
                  chasquido=0.22),
    "gorda": dict(f_ini=230.0, f_fin=38.0, q=1.7, cuerpo=0.52, cola=3.0, grave=95.0,
                  chasquido=0.16),
}


def canonazo(semilla: int, f_ini: float = 320.0, f_fin: float = 52.0, q: float = 2.0,
             cuerpo: float = 0.34, cola: float = 2.0, grave: float = 120.0,
             chasquido: float = 0.22, dur: float = 0.0) -> np.ndarray:
    """Un disparo. `cuerpo` y `cola` son las dos constantes de caída, en segundos."""
    if dur <= 0.0:
        # Siete constantes de caida: es lo que tarda una exponencial en bajar 60 dB. Con 1,6
        # —lo primero que puse— el archivo terminaba a -14 dB, o sea con la cola todavia
        # sonando, y eso no es un release lento sino un CORTE. Se veia medido sin escucharlo:
        # el t60 daba exactamente el largo del archivo en los tres sabores, y el indicador de
        # costura de `guarda` (pensado para bucles) se disparaba a 10,15.
        # 2,3 constantes mas el desvanecido largo de abajo. Siete constantes son los 60 dB
        # teoricos, pero dejaban el archivo de la version "media" en 14,3 s con los ultimos
        # seis por debajo de -40 dB: disco y una voz de audio ocupada para nada.
        dur = cola * 2.3 + 0.3
    n = int(dur * SR)
    t = np.arange(n) / SR

    # El ataque: 0,4 ms de subida. No es cero para que no haya un salto de muestra (un click
    # digital suena a error, no a cañón), pero es más rápido que la resolución del oído.
    ataque = 1.0 - np.exp(-t / 0.0004)

    # --- Frente de choque: banda ancha, y se va en un suspiro.
    #
    # Hasta 2,5 kHz y no 9: con el techo alto el centroide del ataque se iba a 7 kHz, que es un
    # siseo agudo. El estampido de una pieza de artilleria tiene su energia en los cientos de
    # hercios; lo que sube arriba es el borde del frente, no el cuerpo del golpe.
    # Orden 3 y no 1: con pendiente de 6 dB/octava el techo de 2,5 kHz no filtra casi nada y el
    # centroide del ataque seguia en 4,1 kHz. Lo que corta es la PENDIENTE, no el numero.
    choque = filtra(ruido(n, semilla), 120.0, 1800.0, orden=3)
    choque *= ataque * np.exp(-t / 0.010)

    # --- Bola de gas: la resonancia que cae mientras la esfera crece. Es el cuerpo del golpe.
    gas = reson_barrido(ruido(n, semilla + 101), f_ini, f_fin, q)
    gas *= ataque * np.exp(-t / cuerpo)

    # --- Retumbo: solo graves, y lento. El aire se come los agudos con la distancia.
    #
    # Se le pone una ondulación muy lenta porque el retumbo sobre el agua no baja liso: vuelve
    # en oleadas según rebota. Sin ella la cola suena a nota que se apaga, no a eco.
    # Orden 4 y no 2: un Butterworth de segundo orden a 120 Hz deja pasar demasiado por encima
    # y la cola no acaba de ser grave. Con la pendiente del doble, el retumbo es retumbo.
    retumbo = filtra(ruido(n, semilla + 202), 0.0, grave, orden=4)
    ondas = 1.0 + 0.35 * np.sin(2.0 * np.pi * 1.7 * t + 0.6) * np.exp(-t / (cola * 0.7))
    retumbo *= ataque * np.exp(-t / cola) * ondas

    x = chasquido * choque + 1.0 * gas + 0.55 * retumbo

    # Saturación suave: un disparo satura el oído y el micrófono, y sin esto el pico se come
    # todo el margen y el resto queda bajito. `tanh` redondea la punta en vez de recortarla en
    # cuadrado, que es lo que suena a distorsión digital.
    # 1,8 y no 2,2: la saturacion genera armonicos, asi que apretarla de mas vuelve a subir el
    # brillo por la puerta de atras, justo lo que se acaba de quitar con el filtro.
    x = np.tanh(x * 1.8)
    # Desvanecido final garantizado. Aunque con siete constantes la cola ya esta 60 dB abajo,
    # cortar una senal viva produce un click, y un click al final de cada canonazo se oye en
    # una andanada de cuatro.
    # El desvanecido se lleva el ULTIMO CUARTO, no 80 ms. Sobre una cola que todavia suena, un
    # corte de 80 ms se oye como un corte; repartido en mas de un segundo es indistinguible de
    # la propia caida, y permite acabar el archivo mucho antes.
    cierre = int(n * 0.25)
    if cierre > 1:
        x[-cierre:] *= np.linspace(1.0, 0.0, cierre) ** 2
    return x


def main(destino: str, sabor: str = "media", tomas: int = 3) -> list:
    os.makedirs(destino, exist_ok=True)
    kw = SABORES[sabor]
    inf = []
    for i in range(tomas):
        inf.append(guarda(os.path.join(destino, "canon_%d.wav" % (i + 1)),
                          [norm(canonazo(1301 + i * 37, **kw), 0.92)]))
    return inf


def comparar(destino: str) -> list:
    """Los tres sabores, para escucharlos y elegir."""
    os.makedirs(destino, exist_ok=True)
    inf = []
    for nombre, kw in SABORES.items():
        inf.append(guarda(os.path.join(destino, "canon_%s.wav" % nombre),
                          [norm(canonazo(1301, **kw), 0.92)]))
    return inf
