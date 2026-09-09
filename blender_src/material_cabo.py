"""El material de los cabos, construido igual en el barco y en la biblioteca.

Estaba escrito a mano en `balandra_piezas.blend` y NO en `biblioteca/cabo.blend`, asi que los
cabos de la biblioteca salian con la fuerza de normal en 1,0 y sin envejecer. Aqui esta una vez.

OJO, y es lo que mas importa saber: **glTF no exporta nodos procedurales**. De esta cadena solo
viajan al `.glb` las tres texturas y la FUERZA del mapa de normales (1,25). El ruido, el
`env_hsv` y el multiplicado se quedan en Blender, asi que en Godot el cabo sale con la cuerda
cruda de `Rope001`, no alquitranada. Si el tono envejecido tiene que llegar al juego hay que
HORNEARLO a una textura de color; mientras no se haga, esta cadena solo sirve para los renders
y las vistas de Blender.
"""
import bpy

# Valores medidos en `cabo_alquitranado` de balandra_piezas.blend, que es el que dio por bueno
# el usuario. No los toques a ojo: son los que hacen que los 61 cabos del barco casen entre si.
RUIDO = {"Scale": 2.6, "Detail": 6.0, "Roughness": 0.62}
VALOR = {"From Min": 0.25, "From Max": 0.75, "To Min": 0.17, "To Max": 0.38}
HSV = {"Hue": 0.495, "Saturation": 1.3, "Fac": 1.0}
RUGOSIDAD = {"To Min": 0.66, "To Max": 0.98}
FUERZA_NORMAL = 1.25
TINTE_ALQUITRAN = (0.42, 0.37, 0.32, 1.0)
ESPECULAR = 0.2
SHEEN = 0.25


def material_cabo(nombre, col, rug, nor, envejecido=True, alquitranado=False):
    """Crea (o rehace) el material `nombre` con las tres imagenes dadas.

    `envejecido=True` mete la cadena de ruido + HSV + rugosidad remapeada; con `False` las tres
    texturas van directas al BSDF. **La biblioteca usa el limpio**: envejecer o alquitranar es
    una decision de CADA BARCO, no de la pieza prefabricada, asi que una pieza de biblioteca no
    debe traer el tono puesto (decision del usuario, 6 de septiembre de 2026).

    `alquitranado=True` anade el multiplicado que oscurece: es la diferencia entre
    `cabo_alquitranado` y `cabo_envejecido`, que por dentro son el mismo material.
    """
    m = bpy.data.materials.get(nombre) or bpy.data.materials.new(nombre)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    sal = nt.nodes.new("ShaderNodeOutputMaterial"); sal.location = (600, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled"); bsdf.location = (300, 0)
    bsdf.inputs["Specular IOR Level"].default_value = ESPECULAR
    bsdf.inputs["Sheen Weight"].default_value = SHEEN
    nt.links.new(bsdf.outputs["BSDF"], sal.inputs["Surface"])

    def imagen(im, y, no_color):
        n = nt.nodes.new("ShaderNodeTexImage"); n.location = (-600, y)
        n.image = im
        if no_color:
            im.colorspace_settings.name = 'Non-Color'
        return n

    n_col = imagen(col, 200, False)
    n_rug = imagen(rug, -100, True)
    n_nor = imagen(nor, -400, True)

    if not envejecido:
        # Limpio: las tres texturas directas. La fuerza del normal se mantiene en 1,25 porque
        # es la intensidad del relieve, no un tono, y es lo unico de este material que llega
        # al `.glb` (ver la nota de glTF arriba).
        nt.links.new(n_col.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(n_rug.outputs["Color"], bsdf.inputs["Roughness"])
        nmap = nt.nodes.new("ShaderNodeNormalMap"); nmap.location = (-300, -400)
        nmap.space = 'TANGENT'
        nmap.inputs["Strength"].default_value = FUERZA_NORMAL
        nt.links.new(n_nor.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        return m

    # Color: ruido -> rango -> valor del HSV, sobre la textura de color.
    ruido = nt.nodes.new("ShaderNodeTexNoise"); ruido.location = (-900, 500)
    ruido.name = "env_ruido"
    for k, v in RUIDO.items():
        ruido.inputs[k].default_value = v
    val = nt.nodes.new("ShaderNodeMapRange"); val.location = (-600, 500)
    val.name = "env_valor"
    for k, v in VALOR.items():
        val.inputs[k].default_value = v
    nt.links.new(ruido.outputs["Fac"], val.inputs["Value"])
    hsv = nt.nodes.new("ShaderNodeHueSaturation"); hsv.location = (-300, 200)
    hsv.name = "env_hsv"
    for k, v in HSV.items():
        hsv.inputs[k].default_value = v
    nt.links.new(val.outputs["Result"], hsv.inputs["Value"])
    nt.links.new(n_col.outputs["Color"], hsv.inputs["Color"])

    if alquitranado:
        mez = nt.nodes.new("ShaderNodeMix"); mez.location = (0, 200)
        mez.data_type = 'RGBA'; mez.blend_type = 'MULTIPLY'
        mez.inputs["Factor"].default_value = 1.0
        mez.inputs[7].default_value = TINTE_ALQUITRAN      # B, en RGBA
        nt.links.new(hsv.outputs["Color"], mez.inputs[6])  # A
        nt.links.new(mez.outputs[2], bsdf.inputs["Base Color"])
    else:
        nt.links.new(hsv.outputs["Color"], bsdf.inputs["Base Color"])

    rugo = nt.nodes.new("ShaderNodeMapRange"); rugo.location = (-300, -100)
    rugo.name = "env_rug"
    for k, v in RUGOSIDAD.items():
        rugo.inputs[k].default_value = v
    nt.links.new(n_rug.outputs["Color"], rugo.inputs["Value"])
    nt.links.new(rugo.outputs["Result"], bsdf.inputs["Roughness"])

    nmap = nt.nodes.new("ShaderNodeNormalMap"); nmap.location = (-300, -400)
    nmap.space = 'TANGENT'
    nmap.inputs["Strength"].default_value = FUERZA_NORMAL
    nt.links.new(n_nor.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return m
