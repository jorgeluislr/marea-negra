# limpiar_color.py — Lista TODOS los atributos de la malla y borra cualquier atributo
# de tipo COLOR que no sea 'Col'. Útil cuando el .glb sale con una capa de color
# blanca sobrante (COLOR_0) que no aparece en el panel "Atributos de color".
#
# USO: selecciona la malla (la balandra), pestaña Scripting -> pega -> Run.
# Luego re-exporta el .glb.

import bpy

NOMBRE_CAPA = "Col"

def main():
    obj = bpy.context.active_object
    if obj is None or obj.type != 'MESH':
        print("limpiar_color: selecciona la malla (la balandra) y reejecuta.")
        return
    if bpy.context.mode != 'OBJECT':
        try:
            bpy.ops.object.mode_set(mode='OBJECT')
        except RuntimeError:
            print("Ponte en MODO OBJETO (Tab) y reejecuta.")
            return

    mesh = obj.data
    print("── TODOS LOS ATRIBUTOS de '%s' ──" % obj.name)
    for a in mesh.attributes:
        print("   '%s'  tipo=%s  dominio=%s" % (a.name, a.data_type, a.domain))

    # Borrar los de tipo color que no sean 'Col'.
    colores = ('FLOAT_COLOR', 'BYTE_COLOR')
    a_borrar = [a.name for a in mesh.attributes
                if a.data_type in colores and a.name != NOMBRE_CAPA]
    for nombre in a_borrar:
        try:
            mesh.attributes.remove(mesh.attributes[nombre])
            print("   [borrado] capa de color sobrante: '%s'" % nombre)
        except Exception as e:
            print("   [no se pudo borrar] '%s': %s" % (nombre, e))

    quedan = [a.name for a in mesh.attributes if a.data_type in colores]
    print("Capas de color que quedan:", quedan)
    if quedan == [NOMBRE_CAPA]:
        # Dejar 'Col' como activa y de render.
        try:
            mesh.color_attributes.active_color = mesh.color_attributes[NOMBRE_CAPA]
        except Exception:
            pass
        print("OK: solo queda '%s'. Re-exporta el .glb con Colores de vértices activado." % NOMBRE_CAPA)
    else:
        print("⚠ Revisa: deberían quedar solo ['%s'] de color." % NOMBRE_CAPA)

main()
