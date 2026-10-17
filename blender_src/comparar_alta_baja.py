"""Mide si la alta de Meshy y la baja de Tripo son la misma forma, antes de hornear nada.

POR QUE ESTA COMPROBACION VA PRIMERO  Hornear de una alta a una baja lanza un rayo desde
cada punto de la baja y coge lo que encuentra en la alta. Eso solo tiene sentido si las dos
superficies estan a milimetros: si son generaciones distintas del mismo personaje, el rayo
cruza el aire y trae el color de otra parte del cuerpo -- el hombro pinta la oreja, la
barbilla pinta el cuello -- y el resultado no parece un fallo de alineacion, parece una
textura sucia.

COMO SE ALINEAN  Por caja envolvente: mismo centro y misma altura. No se ajusta mas fino a
proposito; lo que se quiere saber es si de partida se parecen, y un ICP encima escondería
una diferencia de forma dentro de una diferencia de pose.

QUE SE MIDE  La distancia de cada vertice de la BAJA a la superficie mas cercana de la
ALTA, en milimetros y en porcentaje de la altura del personaje. Con la mediana por debajo
del 0,5 % de la altura el horneado es viable con una jaula normal; por encima del 2 % no lo
es, y hay que retopologizar sobre la alta en vez de reutilizar la baja.
"""

import os
import sys

import bpy
import numpy as np
from mathutils import Vector

DESCARGAS = r"C:\Users\ASUS TUF\Downloads"
BAJA = os.path.join(DESCARGAS, "muscular man 3d model.fbx")
ALTA = (
    r"C:\Users\ASUSTU~1\AppData\Local\Temp\claude\E--Godot-Game3D-marea-negra"
    r"\c3a456cd-af8e-4aed-9376-b1971b11bd78\scratchpad\meshy"
    r"\Meshy_AI__0918201935_texture_fbx\Meshy_AI__0918201935_texture.fbx"
)


def _importar(ruta, nombre):
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=ruta)
    nuevos = [o for o in set(bpy.data.objects) - antes if o.type == "MESH"]
    nuevos.sort(key=lambda o: -len(o.data.vertices))
    ob = nuevos[0]
    ob.name = nombre
    for o in nuevos[1:]:
        bpy.data.objects.remove(o, do_unlink=True)
    return ob


def _caja(ob):
    co = np.array([(ob.matrix_world @ v.co) for v in ob.data.vertices])
    return co.min(0), co.max(0)


def _separacion(alta, puntos):
    """Distancia de cada punto a la superficie mas cercana de la alta, y ese punto."""
    mi = alta.matrix_world.inverted()
    mw = alta.matrix_world
    d = np.empty(len(puntos))
    cerca = np.empty((len(puntos), 3))
    for i, p in enumerate(puntos):
        vp = Vector(p)
        hit, loc, _, _ = alta.closest_point_on_mesh(mi @ vp)
        q = mw @ loc if hit else vp
        cerca[i] = tuple(q)
        d[i] = (q - vp).length if hit else np.nan
    return d, cerca


def alinear(traza=True, vueltas=12):
    """Carga las dos mallas y deja la ALTA encajada sobre la baja. Devuelve las dos.

    Las vueltas tienen que ser bastantes y hay que MIRAR si convergen: con tres, la escala
    seguia subiendo un 1 % en la ultima (1,0195 / 1,0136 / 1,0104) y el ajuste se quedaba a
    medio camino. Con la alta todavia mas grande que la baja, el horneado sale negro en el
    pecho -- el rayo arranca dentro de la alta y no encuentra superficie hacia la que mirar.
    """
    bpy.ops.wm.read_factory_settings(use_empty=True)
    baja = _importar(BAJA, "baja")
    alta = _importar(ALTA, "alta")

    lo_b, hi_b = _caja(baja)
    lo_a, hi_a = _caja(alta)
    eje = int(np.argmax(hi_b - lo_b))
    alto_b = (hi_b - lo_b)[eje]
    k = alto_b / (hi_a - lo_a)[eje]
    alta.scale = (k, k, k)
    bpy.context.view_layer.update()
    lo_a, hi_a = _caja(alta)
    alta.location = Vector(tuple((lo_b + hi_b) / 2 - (lo_a + hi_a) / 2))
    bpy.context.view_layer.update()

    puntos = np.array([tuple(baja.matrix_world @ v.co) for v in baja.data.vertices])
    # refinado rigido: traslacion y escala uniforme, tres vueltas. La caja envolvente la
    # fijan las trenzas, que es lo que mas difiere entre generaciones, asi que sin esto se
    # mide -- y se hornea -- el desajuste del pelo y no el del cuerpo.
    previa = None
    for vuelta in range(vueltas):
        d, cerca = _separacion(alta, puntos)
        ok = ~np.isnan(d)
        p, q = puntos[ok], cerca[ok]
        cp, cq = p.mean(0), q.mean(0)
        kk = np.linalg.norm(q - cq, axis=1).sum() / max(
            np.linalg.norm(p - cp, axis=1).sum(), 1e-9
        )
        kk = float(np.clip(kk, 0.97, 1.03))
        alta.scale = tuple(np.array(alta.scale) / kk)
        bpy.context.view_layer.update()
        d, cerca = _separacion(alta, puntos)
        ok = ~np.isnan(d)
        alta.location = tuple(
            np.array(alta.location) - (cerca[ok].mean(0) - puntos[ok].mean(0))
        )
        bpy.context.view_layer.update()
        d, _ = _separacion(alta, puntos)
        med = float(np.nanmedian(d)) * 1000.0
        if traza:
            print("  refinado %2d: escala x %.4f   mediana %6.2f mm" % (vuelta + 1, 1.0 / kk, med))
        if previa is not None and abs(previa - med) < 0.02:
            break
        previa = med
    return baja, alta, float(alto_b), eje, puntos


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    baja = _importar(BAJA, "baja")
    alta = _importar(ALTA, "alta")

    print("")
    print("=== las dos mallas ===")
    for ob in (baja, alta):
        lo, hi = _caja(ob)
        print(
            "  %-5s verts %8d  caras %8d  uv %-12s  caja %s .. %s"
            % (
                ob.name,
                len(ob.data.vertices),
                len(ob.data.polygons),
                [u.name for u in ob.data.uv_layers],
                np.round(lo, 3),
                np.round(hi, 3),
            )
        )
    for im in bpy.data.images:
        if im.size[0]:
            print("  textura %-40s %d x %d" % (im.name[:40], im.size[0], im.size[1]))

    # alineacion por caja: mismo centro y misma altura
    lo_b, hi_b = _caja(baja)
    lo_a, hi_a = _caja(alta)
    eje = int(np.argmax(hi_b - lo_b))                  # el eje largo es la altura
    alto_b = (hi_b - lo_b)[eje]
    alto_a = (hi_a - lo_a)[eje]
    k = alto_b / alto_a
    alta.scale = (k, k, k)
    bpy.context.view_layer.update()
    lo_a, hi_a = _caja(alta)
    alta.location = Vector(tuple((lo_b + hi_b) / 2 - (lo_a + hi_a) / 2))
    bpy.context.view_layer.update()
    print("")
    print("  eje de la altura: %s   alta escalada x %.4f para igualar %.4f m" % ("XYZ"[eje], k, alto_b))

    puntos = np.array([tuple(baja.matrix_world @ v.co) for v in baja.data.vertices])

    def separacion():
        mi = alta.matrix_world.inverted()
        mw = alta.matrix_world
        d = np.empty(len(puntos))
        cerca = np.empty((len(puntos), 3))
        for i, p in enumerate(puntos):
            vp = Vector(p)
            hit, loc, _, _ = alta.closest_point_on_mesh(mi @ vp)
            q = mw @ loc if hit else vp
            cerca[i] = tuple(q)
            d[i] = (q - vp).length if hit else np.nan
        return d, cerca

    # refinado rigido: traslacion y escala uniforme, tres vueltas.
    # La caja envolvente la fijan las trenzas, que es justo lo que mas difiere entre
    # generaciones, asi que sin esto se mide el desajuste del pelo y no el del cuerpo.
    for vuelta in range(3):
        d, cerca = separacion()
        ok = ~np.isnan(d)
        p = puntos[ok]
        q = cerca[ok]
        cp, cq = p.mean(0), q.mean(0)
        k = np.linalg.norm(q - cq, axis=1).sum() / max(np.linalg.norm(p - cp, axis=1).sum(), 1e-9)
        k = float(np.clip(k, 0.97, 1.03))
        alta.scale = tuple(np.array(alta.scale) / k)
        bpy.context.view_layer.update()
        d, cerca = separacion()
        ok = ~np.isnan(d)
        alta.location = tuple(
            np.array(alta.location) - (cerca[ok].mean(0) - puntos[ok].mean(0))
        )
        bpy.context.view_layer.update()
        print("  refinado %d: escala x %.4f" % (vuelta + 1, 1.0 / k))

    d, _ = separacion()
    ok = ~np.isnan(d)
    d = d[ok] * 1000.0                                 # a milimetros
    z = puntos[ok][:, eje]
    pct = 100.0 * d / (alto_b * 1000.0)

    print("")
    print("=== separacion entre las dos superficies (%d vertices) ===" % len(d))
    for q_ in (50, 90, 95, 99):
        print(
            "  p%-2d  %7.1f mm   %5.2f %% de la altura"
            % (q_, np.percentile(d, q_), np.percentile(pct, q_))
        )
    print("  max  %7.1f mm   %5.2f %%" % (d.max(), pct.max()))

    print("")
    print("=== por franjas de altura, de los pies a la cabeza ===")
    bordes = np.linspace(z.min(), z.max(), 9)
    for i in range(8):
        m = (z >= bordes[i]) & (z < bordes[i + 1] if i < 7 else z <= bordes[i + 1])
        if m.sum() < 10:
            continue
        print(
            "  franja %d  %6d verts   mediana %6.1f mm   p90 %6.1f mm"
            % (i + 1, int(m.sum()), np.median(d[m]), np.percentile(d[m], 90))
        )

    med = np.percentile(pct, 50)
    if med < 0.5:
        print("\n  -> se parecen: el horneado es viable con una jaula normal")
    elif med < 2.0:
        print("\n  -> se parecen a medias: hara falta jaula generosa y habra zonas sucias")
    else:
        print("\n  -> son formas distintas: no se puede hornear una sobre otra")


if __name__ == "__main__":
    main()
