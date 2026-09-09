"""Normales personalizadas para un cabo entorchado: cada cara se ilumina como si perteneciera
al CILINDRO de su cordon, no al prisma que realmente es.

El problema que resuelve: con 9 lados y 3 caras por cordon, las normales de cara dan un patron
de luces y sombras a saltos —una cara brilla y la vecina de la misma linea queda en sombra—
porque cada una es un plano con su propia orientacion. Poniendo en cada esquina la normal
RADIAL respecto al eje de su cordon, la interpolacion entre esquinas hace que el cordon se
ilumine como un tubo redondo, con la misma geometria.

Se hace por LOOP y no por vertice porque los vertices del valle pertenecen a dos cordones y
necesitan una normal distinta en cada uno.

Esto SI se exporta: en glTF son normales de vertice, y se transforman con el esqueleto.
"""
import bmesh, math
import numpy as np


def normales_de_cordones(obj, cordones=3, anillos=None):
    me = obj.data
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    from uv_cabos import anillos_del_tubo
    anillos = anillos_del_tubo(bm)
    if anillos is None or len(anillos) < 2:
        bm.free(); return None
    lados = len(anillos[0])
    # A que cordon pertenece cada lado. No se exige que `lados` sea multiplo de `cordones`:
    # con 16 lados y 3 cordones el reparto sale 6/5/5, que es lo que hay, y es preferible a
    # dejar el cabo sin tratar (era lo que le pasaba a `comp_octagonos`).
    cordon_de = [(j * cordones) // lados for j in range(lados)]
    js_de_cordon = [[j for j in range(lados) if cordon_de[j] == k] for k in range(cordones)]
    if any(not x for x in js_de_cordon):
        bm.free(); return None
    por_cordon = [len(x) for x in js_de_cordon]

    pos = {}      # (anillo, j) -> posicion
    for a, an in enumerate(anillos):
        for j, v in enumerate(an):
            pos[(a, j)] = np.array([v.co.x, v.co.y, v.co.z])
    centro_tubo = {a: np.mean([pos[(a, j)] for j in range(lados)], axis=0)
                   for a in range(len(anillos))}
    # Eje del cordon: se toma el centro de sus vertices en cada anillo.
    centro_cordon = {}
    for a in range(len(anillos)):
        for k in range(cordones):
            centro_cordon[(a, k)] = np.mean([pos[(a, j)] for j in js_de_cordon[k]], axis=0)

    idx = {v.index: (a, j) for a, an in enumerate(anillos) for j, v in enumerate(an)}
    bm.free()

    # Normal por esquina: radial desde el eje del cordon al que pertenece la CARA.
    normales = [(0.0, 0.0, 1.0)] * len(me.loops)
    for poly in me.polygons:
        datos = [idx.get(me.loops[li].vertex_index) for li in poly.loop_indices]
        if any(d is None for d in datos):
            continue
        js = [d[1] for d in datos]
        # cordon de la cara: el de la arista que la genera (el menor j sin contar la costura)
        cruza = (0 in js) and (lados - 1 in js)
        j_base = (lados - 1) if cruza else min(js)
        k = cordon_de[j_base % lados]
        for li, (a, j) in zip(poly.loop_indices, datos):
            c = centro_cordon[(a, k)]
            r = pos[(a, j)] - c
            # quitar la componente a lo largo del cordon
            a2 = min(a + 1, len(anillos) - 1)
            a1 = max(a - 1, 0)
            eje = centro_cordon[(a2, k)] - centro_cordon[(a1, k)]
            n_eje = np.linalg.norm(eje)
            if n_eje > 1e-9:
                eje = eje / n_eje
                r = r - eje * float(r @ eje)
            m = np.linalg.norm(r)
            if m < 1e-9:
                r = pos[(a, j)] - centro_tubo[a]
                m = np.linalg.norm(r)
                if m < 1e-9:
                    continue
            r = r / m
            # que apunte hacia fuera del tubo
            fuera = pos[(a, j)] - centro_tubo[a]
            if float(r @ fuera) < 0:
                r = -r
            normales[li] = (float(r[0]), float(r[1]), float(r[2]))

    for p in me.polygons:
        p.use_smooth = True
    me.normals_split_custom_set(normales)
    me.update()
    return {"lados": lados, "cordones": cordones, "caras_por_cordon": por_cordon,
            "loops": len(me.loops), "anillos": len(anillos)}
