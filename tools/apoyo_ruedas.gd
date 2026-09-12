extends Node

## A qué altura encuentra suelo cada una de las CUATRO ruedas de cada cureña.
##
## Un solo rayo desde el centro del cañón no vale: la pieza puede tener tres ruedas en la
## cubierta y la cuarta colgando sobre la regala, y el centro seguir dando bien. Eso es lo que
## se coló en la primera colocación.
##
## Posiciones de rueda medidas sobre el modelo (a 3 libras, factor 0,90476 sobre el original):
## ejes en x local −0,093 y +0,616, ruedas a z local ±0,287.

const RUEDAS := [Vector3(-0.0926, 0, 0.2873), Vector3(-0.0926, 0, -0.2873),
	Vector3(0.6159, 0, 0.2873), Vector3(0.6159, 0, -0.2873)]

var _barco: Node3D


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_barco = esc.instantiate() as Node3D
	add_child(_barco)
	_barco.set("anclado", true)
	await get_tree().create_timer(4.0).timeout
	var espacio := _barco.get_world_3d().direct_space_state
	for c in _barco.find_children("*", "", true, false):
		if not (c.has_method("disparar") and c is Node3D):
			continue
		var n3 := c as Node3D
		# Las ruedas están en el espacio del MODELO, y el de estribor va girado media vuelta:
		# usando el transform del NODO se buscan en el costado contrario, fuera del barco.
		var base := n3.get_node_or_null(^"Modelo") as Node3D
		if base == null:
			base = n3
		var alturas: Array[float] = []
		for r in RUEDAS:
			var mundo: Vector3 = base.global_transform * r
			var par := PhysicsRayQueryParameters3D.create(
				mundo + Vector3.UP * 1.2, mundo + Vector3.DOWN * 1.2)
			par.collision_mask = 4
			var g := espacio.intersect_ray(par)
			alturas.append(_barco.to_local(g["position"]).y if not g.is_empty() else NAN)
		var txt := ""
		for a in alturas:
			txt += ("  %7.3f" % a) if is_finite(a) else "    NADA"
		var malas := 0
		for a in alturas:
			if not is_finite(a) or absf(a - 1.640) > 0.03:
				malas += 1
		print("%-22s%s   %s" % [n3.name, txt, "OK" if malas == 0 else "%d RUEDA(S) MAL" % malas])
	get_tree().quit(0)
