extends Node

## ¿De qué barco es la cámara con la que se juega? Sobre la escena real, con dos barcos dentro.
##
## Existe porque el fallo sólo aparece con más de un barco y no da ningún error: cada cámara
## hacía `current = true` en su `_ready`, el enemigo se instancia el último y su cámara ganaba
## el visor. Se veía como que la partida empieza mirando al barco que no gobiernas.
##
## Lista TODAS las cámaras de la escena y de quién cuelga cada una, no sólo la activa: con una
## sola línea de "la activa es X" no se distingue "está bien" de "hay una sola cámara".
##
##     godot --path . --headless tools/quien_tiene_camara.tscn

@export var escena := "res://scenes/world/escaramuza.tscn"
const ESPERA := 6.0


func _ready() -> void:
	var esc := load(escena) as PackedScene
	add_child(esc.instantiate())
	await get_tree().create_timer(ESPERA).timeout

	var jugador := get_tree().get_first_node_in_group("barco_activo")
	print("═══ Cámaras en %s ═══" % escena)
	print("barco del jugador: %s" % (jugador.name if jugador != null else "(ninguno)"))
	var activas := 0
	var mal := 0
	for c in get_tree().root.find_children("*", "Camera3D", true, false):
		var cam := c as Camera3D
		var barco := _barco_de(cam)
		var suyo := barco != null and barco.is_in_group("barco_activo")
		if cam.current:
			activas += 1
			if barco != null and not suyo:
				mal += 1
		print("  %-14s de %-12s  %s" % [cam.name,
			barco.name if barco != null else "(nadie)",
			"ACTIVA" if cam.current else "-"])
	print("\n%d cámara(s) activa(s); %d de un barco que no es el del jugador (debe ser 0)"
		% [activas, mal])
	get_tree().quit(1 if mal > 0 or activas != 1 else 0)


## De qué barco cuelga una cámara: se sube por los padres hasta encontrar algo que sepa navegar.
func _barco_de(n: Node) -> Node:
	var p := n.get_parent()
	while p != null:
		if p.has_method("factor_viento"):
			return p
		p = p.get_parent()
	return null
