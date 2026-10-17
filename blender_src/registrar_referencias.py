"""Registra las cuatro vistas de Tripo contra la malla, midiendo el encaje.

QUE HACE  Coloca una camara ortografica por vista, renderiza la silueta de la malla y la
ajusta contra la silueta del sujeto en la imagen -- escala y desplazamiento por busqueda
sobre la IoU (interseccion sobre union). Deja medido lo que luego proyecta, y un solapado
por vista para poder MIRAR el encaje ademas de leerlo.

POR QUE NO SE AJUSTA A OJO  La barba del capitan no esta modelada: la mandibula de la
malla sale afeitada y la de la imagen lleva barba cerrada. Un ajuste por parecido visual
mete el error justo donde mas se nota, asi que el encaje se da en numeros -- IoU por vista
y desplazamiento en pixeles -- y el solapado solo sirve para confirmarlos.

QUE LADO ES CADA PERFIL NO SE SUPONE, SE PRUEBA  El juego trae la vista 1 y la vista 3 sin
decir cual es babor. Se ajustan las dos contra las dos camaras posibles y se queda la
asignacion con mejor IoU: con la figura de perfil, confundirlas da un encaje peor, asi que
el numero decide solo.

El modelo de Tripo viene con Y arriba; aqui se pasa a Z arriba, que es lo que suponen
tanto Blender como to_track_quat.
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

RES = 1024          # se renderiza al tamano de las referencias
BUSQUEDA = 256      # la busqueda del ajuste va en pequeno; es cuadratica en pixeles
FONDO = 0.93        # el sujeto es todo lo que baja de esto en algun canal

DESCARGAS = r"C:\Users\ASUS TUF\Downloads"
JUEGO = "ad74a6b7-1d7b-4bbb-b690-20a2c8ecd42f"
MALLA = os.path.join(DESCARGAS, "muscular man 3d model.fbx")

# Direccion desde la que MIRA la camara, en ejes de Blender ya con Z arriba.
# El sujeto mira a -Y, asi que su izquierda cae en +X (f x u con f=(0,-1,0), u=(0,0,1)).
CAMARAS = {
    "frente": Vector((0, -1, 0)),
    "espalda": Vector((0, 1, 0)),
    "perfil_izq": Vector((1, 0, 0)),
    "perfil_der": Vector((-1, 0, 0)),
}
FIJAS = {0: "frente", 2: "espalda"}
AMBIGUAS = (1, 3)


def _mascara_imagen(ruta):
    """Sujeto de una referencia: fondo blanco fuera, figura dentro."""
    im = bpy.data.images.load(ruta)
    w, h = im.size
    rgb = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3]
    bpy.data.images.remove(im)
    return rgb.min(axis=2) < FONDO, rgb


def _preparar_escena():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=MALLA)
    ob = [o for o in bpy.data.objects if o.type == "MESH"][0]
    ob.rotation_euler = (math.radians(90), 0, 0)      # Y arriba -> Z arriba
    bpy.context.view_layer.update()

    esc = bpy.context.scene
    esc.render.engine = "BLENDER_EEVEE_NEXT"
    esc.render.resolution_x = RES
    esc.render.resolution_y = RES
    esc.render.film_transparent = True                # la silueta sale en el alfa
    esc.render.image_settings.file_format = "PNG"
    esc.render.image_settings.color_mode = "RGBA"

    co = np.array([(ob.matrix_world @ v.co) for v in ob.data.vertices])
    centro = Vector((co.min(0) + co.max(0)) / 2)
    tam = float(np.max(co.max(0) - co.min(0)))

    dat = bpy.data.cameras.new("cam")
    dat.type = "ORTHO"
    dat.ortho_scale = tam * 1.30                      # holgura: el ajuste la recorta
    cam = bpy.data.objects.new("cam", dat)
    esc.collection.objects.link(cam)
    esc.camera = cam
    return ob, cam, centro, tam


def _silueta(cam, centro, tam, direccion, tmp):
    """Renderiza la malla desde una direccion y devuelve su mascara."""
    cam.location = centro + direccion * (tam * 3.0)
    cam.rotation_euler = (-direccion).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    im = bpy.data.images.load(tmp)
    w, h = im.size
    alfa = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, 3]
    bpy.data.images.remove(im)
    return alfa > 0.5


def _reducir(m, n):
    """Submuestrea una mascara a n x n sin depender de scipy."""
    f = m.shape[0] // n
    return m[: n * f, : n * f].reshape(n, f, n, f).max(axis=(1, 3))


def _iou(modelo, objetivo, sx, sy, tx, ty):
    """IoU del modelo escalado y desplazado contra el objetivo, con escalas separadas.

    El muestreo es INVERSO -- por cada pixel del destino se mira de donde viene -- y no
    directo. Dispersando los pixeles del origen, cualquier escala mayor que 1 deja huecos
    entre ellos y la IoU los cuenta como fallos: con s = 1,18 eso solo ya se comia un 28 %
    del encaje, y el solapado salia como una rejilla en vez de como una silueta.

    La escala va separada en X e Y porque estas referencias no son fotografias: medido,
    los ALTOS de las cuatro vistas concuerdan al 1,7 % y los ANCHOS discrepan un 14 %, con
    el frente y la espalda dando 1,2098 identico y los dos perfiles 1,0612 y 1,1224. El
    vertical es comun a las cuatro vistas de un cuerpo rigido; el horizontal es lo que el
    generador ha puesto distinto en cada una.
    """
    n = objetivo.shape[0]
    c = (n - 1) / 2.0
    ejes = np.arange(n) - c
    fy = np.rint((ejes - ty) / sy + c).astype(np.int32)
    fx = np.rint((ejes - tx) / sx + c).astype(np.int32)
    vy = (fy >= 0) & (fy < n)
    vx = (fx >= 0) & (fx < n)
    puesto = np.zeros_like(objetivo)
    puesto[np.ix_(vy, vx)] = modelo[np.ix_(fy[vy], fx[vx])]
    inter = int((puesto & objetivo).sum())
    union = int((puesto | objetivo).sum())
    return (inter / union if union else 0.0), puesto


def _caja(m):
    ys, xs = np.nonzero(m)
    return ys.min(), ys.max(), xs.min(), xs.max()


def _partida(modelo, objetivo):
    """Escalas y desplazamientos de partida, igualando las cajas."""
    my0, my1, mx0, mx1 = _caja(modelo)
    oy0, oy1, ox0, ox1 = _caja(objetivo)
    c = (objetivo.shape[0] - 1) / 2.0
    sy = (oy1 - oy0) / max(my1 - my0, 1)
    sx = (ox1 - ox0) / max(mx1 - mx0, 1)
    ty = ((oy0 + oy1) / 2 - c) - ((my0 + my1) / 2 - c) * sy
    tx = ((ox0 + ox1) / 2 - c) - ((mx0 + mx1) / 2 - c) * sx
    return sx, sy, tx, ty


def _refinar(modelo, objetivo, sx, sy, tx, ty, sy_fija=False):
    """Busca de grueso a fino sobre lo que se le deje mover."""
    paso_s, paso_t = 0.08, 12.0
    for _ in range(7):
        mejor = (_iou(modelo, objetivo, sx, sy, tx, ty)[0], sx, sy, tx, ty)
        for dsx in (-paso_s, 0.0, paso_s):
            for dsy in ((0.0,) if sy_fija else (-paso_s, 0.0, paso_s)):
                for dx in (-paso_t, 0.0, paso_t):
                    for dy in (-paso_t, 0.0, paso_t):
                        v = _iou(modelo, objetivo, sx + dsx, sy + dsy, tx + dx, ty + dy)[0]
                        if v > mejor[0]:
                            mejor = (v, sx + dsx, sy + dsy, tx + dx, ty + dy)
        _, sx, sy, tx, ty = mejor
        paso_s *= 0.5
        paso_t *= 0.5
    return sx, sy, tx, ty, _iou(modelo, objetivo, sx, sy, tx, ty)[0]


def _ajustar(modelo, objetivo):
    """Ajuste libre de una vista: sus dos escalas y su desplazamiento."""
    return _refinar(modelo, objetivo, *_partida(modelo, objetivo))


def _desfase_por_franjas(puesto, objetivo, franjas=8):
    """Cuanto se separan los dos contornos, franja a franja de altura.

    El IoU es un resumen y esconde DONDE falla: un encaje global de 0,93 puede llevar la
    cara entera desplazada y seguir siendo 0,93, porque la cara es una fraccion pequena de
    la silueta. Aqui se mide, por cada franja, la diferencia entre los bordes izquierdo y
    derecho del modelo y los de la referencia, en pixeles del render.
    """
    n = objetivo.shape[0]
    filas = np.nonzero(objetivo.any(axis=1))[0]
    if len(filas) == 0:
        return []
    cortes = np.linspace(filas.min(), filas.max() + 1, franjas + 1).astype(int)
    salida = []
    for i in range(franjas):
        a, b = cortes[i], cortes[i + 1]
        mo = objetivo[a:b].any(axis=0)
        mm = puesto[a:b].any(axis=0)
        if not mo.any() or not mm.any():
            salida.append((a, b, None, None))
            continue
        co = np.nonzero(mo)[0]
        cm = np.nonzero(mm)[0]
        salida.append((a, b, int(cm.min() - co.min()), int(cm.max() - co.max())))
    return salida


def _con_altura_fija(modelo, objetivo, sy):
    """Ajusta una vista con la escala VERTICAL impuesta desde fuera."""
    sx0, _, tx0, ty0 = _partida(modelo, objetivo)
    return _refinar(modelo, objetivo, sx0, sy, tx0, ty0, sy_fija=True)


def _altura_comun(siluetas, refs, asignacion, sueltas):
    """Una sola escala VERTICAL para las cuatro vistas, la que mas IoU suma.

    Solo el alto es comun a las cuatro vistas de un cuerpo rigido, y de hecho concuerda:
    medido, las cuatro lo dan dentro de un 1,7 %. El ancho no -- 14 % de dispersion, con
    los dos perfiles dando la profundidad un 6 y un 11 % mas estrecha que la malla -- asi
    que imponer una escala unica a las dos direcciones descuadra los perfiles, y dejar
    libres las dos hace que cada vista se contradiga con las demas. Se fija la vertical y
    se deja libre la horizontal.
    """
    lo = min(sueltas.values()) * 0.98
    hi = max(sueltas.values()) * 1.02
    mejor = (-1.0, None)
    for sy in np.linspace(lo, hi, 21):
        total = sum(
            _con_altura_fija(siluetas[asignacion[v]], refs[v][0], sy)[4]
            for v in asignacion
        )
        if total > mejor[0]:
            mejor = (total, float(sy))
    return mejor[1], mejor[0] / len(asignacion)


def _guardar_solapado(ruta, rgb, puesto, escala):
    """Referencia en color con el borde de la silueta del modelo en rojo."""
    g = np.repeat(np.repeat(puesto, escala, axis=0), escala, axis=1)
    borde = (
        (g & ~np.roll(g, 1, 0))
        | (g & ~np.roll(g, -1, 0))
        | (g & ~np.roll(g, 1, 1))
        | (g & ~np.roll(g, -1, 1))
    )
    out = rgb.copy()
    out[borde] = (1.0, 0.0, 0.0)
    img = bpy.data.images.new(os.path.basename(ruta), out.shape[1], out.shape[0])
    px = np.concatenate([out, np.ones(out.shape[:2] + (1,), np.float32)], axis=2)
    img.pixels = px[::-1].ravel()
    img.filepath_raw = ruta
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def main(destino, solapados=True):
    """Ajusta las cuatro vistas y devuelve el encaje, que es lo que luego proyecta.

    Devuelve un dict con la geometria de las camaras (centro, tam, ortho_scale) y, por
    vista, a que camara corresponde y su escala y desplazamiento ya ajustados.
    """
    os.makedirs(destino, exist_ok=True)
    tmp = os.path.join(destino, "_silueta.png")
    _, cam, centro, tam = _preparar_escena()

    siluetas = {}
    for nom, d in CAMARAS.items():
        siluetas[nom] = _reducir(_silueta(cam, centro, tam, d, tmp), BUSQUEDA)

    refs = {}
    for i in range(4):
        m, rgb = _mascara_imagen(os.path.join(DESCARGAS, "multiview_%d_%s.jpeg" % (i, JUEGO)))
        refs[i] = (_reducir(m, BUSQUEDA), rgb)

    combos = [
        {AMBIGUAS[0]: "perfil_izq", AMBIGUAS[1]: "perfil_der"},
        {AMBIGUAS[0]: "perfil_der", AMBIGUAS[1]: "perfil_izq"},
    ]
    puntuadas = []
    for combo in combos:
        val = [_ajustar(siluetas[n], refs[v][0])[4] for v, n in combo.items()]
        puntuadas.append((sum(val) / len(val), combo, val))
    puntuadas.sort(key=lambda x: -x[0])

    print("")
    print("=== que perfil es cual (se decide midiendo) ===")
    for media, combo, val in puntuadas:
        etq = ", ".join(
            "vista %d -> %s (IoU %.3f)" % (v, n, u)
            for (v, n), u in zip(combo.items(), val)
        )
        print("  media %.3f   %s" % (media, etq))

    asignacion = dict(FIJAS)
    asignacion.update(puntuadas[0][1])

    libres = {v: _ajustar(siluetas[asignacion[v]], refs[v][0]) for v in asignacion}
    sueltas = {v: libres[v][1] for v in asignacion}          # la vertical de cada una
    sy_comun, iou_medio = _altura_comun(siluetas, refs, asignacion, sueltas)
    print("")
    print("=== escalas ===")
    for v in sorted(asignacion):
        sx, sy, _, _, iou = libres[v]
        print(
            "  %-11s libre: alto %.4f  ancho %.4f  (IoU %.3f)"
            % (asignacion[v], sy, sx, iou)
        )
    print("  alto comun a las cuatro: %.4f   (IoU medio %.3f)" % (sy_comun, iou_medio))

    print("")
    print("=== encaje por vista ===")
    escala = RES // BUSQUEDA
    encaje = {
        "centro": tuple(centro),
        "tam": tam,
        "ortho_scale": bpy.context.scene.camera.data.ortho_scale,
        "res": RES,
        "busqueda": BUSQUEDA,
        "alto_comun": sy_comun,
        "vistas": {},
    }
    for vista in sorted(asignacion):
        nom = asignacion[vista]
        sx, sy, tx, ty, iou = _con_altura_fija(siluetas[nom], refs[vista][0], sy_comun)
        encaje["vistas"][vista] = {
            "camara": nom,
            "sx": sx,
            "sy": sy,
            "tx": tx,
            "ty": ty,
            "iou": iou,
        }
        print(
            "  vista %d -> %-11s IoU %.3f   alto %.4f  ancho %.4f   desplaz %+7.1f, %+7.1f px"
            % (vista, nom, iou, sy, sx, tx * escala, ty * escala)
        )
        if not solapados:
            continue
        _, puesto = _iou(siluetas[nom], refs[vista][0], sx, sy, tx, ty)
        for a, b, izq, der in _desfase_por_franjas(puesto, refs[vista][0]):
            if izq is None:
                continue
            print(
                "       franja y %4d-%4d  borde izq %+5d px   borde der %+5d px"
                % (a * escala, b * escala, izq * escala, der * escala)
            )
        ruta = os.path.join(destino, "encaje_vista%d_%s.png" % (vista, nom))
        _guardar_solapado(ruta, refs[vista][1], puesto, escala)
        print("       solapado -> %s" % ruta)

    if os.path.exists(tmp):
        os.remove(tmp)
    return encaje


if __name__ == "__main__":
    main(sys.argv[-1])
