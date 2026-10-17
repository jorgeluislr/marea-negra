"""Cuanto se desmienten las cuatro vistas SOBRE LA CARA, que es donde salen las costuras.

El registro de `registrar_referencias` ajusta cada vista contra la silueta entera, y la
silueta entera es sobre todo torso y brazos: la cabeza son 370 px de los 954 que mide el
sujeto, asi que el ajuste lo gobierna el cuerpo y la cara se lleva lo que sobre. Si dos
vistas caen desplazadas entre si sobre la cara, donde se mezclan aparece un escalon -- que
es la costura que se ve en la barba y en la nariz.

Aqui se vuelve a ajustar cada vista usando SOLO la banda de la cabeza, y se compara con el
ajuste del cuerpo. La diferencia entre los dos, en pixeles, es el desplazamiento que tiene
la cara ahora mismo.

La banda de la cabeza se saca del MODELO y no de la referencia: el modelo no tiene barba,
asi que su cuello es una garganta limpia en el perfil de anchuras, mientras que en la
imagen la barba lo rellena y no hay minimo que encontrar.
"""

import os
import sys

import bpy
import numpy as np

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import registrar_referencias as reg          # noqa: E402


def _banda_cabeza(silueta):
    """De la coronilla al cuello, leido en la silueta del modelo."""
    filas = np.nonzero(silueta.any(axis=1))[0]
    y0, y1 = int(filas.min()), int(filas.max())
    anchos = silueta.sum(axis=1).astype(float)
    a = y0 + int(0.18 * (y1 - y0))
    b = y0 + int(0.55 * (y1 - y0))
    tramo = np.where(anchos[a:b] > 0, anchos[a:b], 1e9)
    cuello = a + int(np.argmin(tramo))
    return y0, cuello


def main(destino):
    os.makedirs(destino, exist_ok=True)
    tmp = os.path.join(destino, "_silueta.png")
    _, cam, centro, tam = reg._preparar_escena()

    siluetas = {}
    for nom, d in reg.CAMARAS.items():
        siluetas[nom] = reg._reducir(reg._silueta(cam, centro, tam, d, tmp), reg.BUSQUEDA)

    refs = {}
    for i in range(4):
        m, _ = reg._mascara_imagen(
            os.path.join(reg.DESCARGAS, "multiview_%d_%s.jpeg" % (i, reg.JUEGO))
        )
        refs[i] = reg._reducir(m, reg.BUSQUEDA)

    asignacion = {0: "frente", 1: "perfil_izq", 2: "espalda", 3: "perfil_der"}
    escala = reg.RES // reg.BUSQUEDA

    print("")
    print("=== ajuste con el CUERPO entero contra ajuste con la CABEZA sola ===")
    print("vista            s_cuerpo  s_cabeza    dx      dy    desplaz. de la cara")
    peor = 0.0
    for vista in sorted(asignacion):
        nom = asignacion[vista]
        sc, txc, tyc, _ = reg._ajustar(siluetas[nom], refs[vista])

        y0, cuello = _banda_cabeza(siluetas[nom])
        mod = np.zeros_like(siluetas[nom])
        mod[y0:cuello] = siluetas[nom][y0:cuello]
        # en la referencia se recorta la misma banda, llevada por el ajuste del cuerpo
        ry0 = int(round((y0 - (reg.BUSQUEDA - 1) / 2) * sc + (reg.BUSQUEDA - 1) / 2 + tyc))
        ry1 = int(round((cuello - (reg.BUSQUEDA - 1) / 2) * sc + (reg.BUSQUEDA - 1) / 2 + tyc))
        ref = np.zeros_like(refs[vista])
        ry0, ry1 = max(ry0, 0), min(ry1, reg.BUSQUEDA)
        ref[ry0:ry1] = refs[vista][ry0:ry1]
        if not mod.any() or not ref.any():
            print("  vista %d: sin banda de cabeza" % vista)
            continue

        sh, txh, tyh, iouh = reg._ajustar(mod, ref)
        dx = (txh - txc) * escala
        dy = (tyh - tyc) * escala
        d = float(np.hypot(dx, dy))
        peor = max(peor, d)
        print(
            "  %-11s %8.4f  %8.4f  %+6.1f  %+6.1f   %5.1f px   (IoU cabeza %.3f)"
            % (nom, sc, sh, dx, dy, d, iouh)
        )

    print("")
    print("  peor desplazamiento de la cara entre los dos ajustes: %.1f px de %d" % (peor, reg.RES))
    if os.path.exists(tmp):
        os.remove(tmp)


if __name__ == "__main__":
    main(sys.argv[-1])
