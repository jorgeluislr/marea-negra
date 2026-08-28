# verificar_tela.py — Comprueba, ANTES de exportar, que la máscara de tela está bien.
# Selecciona la lancha y ejecútalo (pestaña Scripting). Mira los mensajes en consola.

import bpy

NOMBRE_CAPA = "Col"

def main():
    obj = bpy.context.active_object
    if obj is None or obj.type != 'MESH':
        print("verificar_tela: selecciona la malla (la lancha) y reejecuta.")
        return
    mesh = obj.data

    capas = [c.name for c in mesh.color_attributes]
    print("── VERIFICACIÓN DE TELA ─────────────────────────")
    print(f"Objeto: {obj.name}  |  vértices: {len(mesh.vertices)}")
    print(f"Capas de color: {capas}")

    if len(capas) != 1:
        print(f"  ⚠  Hay {len(capas)} capas. Debe quedar SOLO '{NOMBRE_CAPA}'.")
        print("     Borra las demás en Datos del objeto → Color Attributes (botón –).")
    if NOMBRE_CAPA not in capas:
        print(f"  ✗  No existe la capa '{NOMBRE_CAPA}'. Ejecuta marcar_tela.py.")
        return

    ca = mesh.color_attributes[NOMBRE_CAPA]
    n = len(ca.data)
    tela = sum(1 for d in ca.data if d.color[0] > 0.05)
    fuerte = sum(1 for d in ca.data if d.color[0] > 0.6)
    print(f"Máscara '{NOMBRE_CAPA}':")
    print(f"  tela (peso>0.05):   {tela:7d}  ({100*tela/n:.1f}%)")
    print(f"  estático (peso~0):  {n-tela:7d}  ({100*(n-tela)/n:.1f}%)")
    print(f"  ondeo fuerte (>0.6):{fuerte:7d}  ({100*fuerte/n:.1f}%)")

    # ¿es la capa activa de render? (la que exporta/lee Godot)
    try:
        activa = mesh.color_attributes.active_color.name
    except Exception:
        activa = "?"
    print(f"Capa activa (render): {activa}")

    if 5 < 100*tela/n < 60 and len(capas) == 1:
        print("✓  Pinta bien: una sola capa y una fracción parcial marcada como tela.")
    else:
        print("⚠  Revisa: esperaba UNA capa y ~5-60% de tela. Si no cuadra, re-marca.")
    print("─────────────────────────────────────────────────")
    print("Recuerda: al exportar, activa que se exporte el Vertex Color ACTIVO (ver instrucciones).")

main()
