extends Node

## Hasta dónde llega la CUBIERTA pisable antes de que empiece la borda, en las secciones donde
## van las piezas. Es el límite real para la rueda de fuera de una cureña.
##
## Se busca con rayos hacia ABAJO barriendo de crujía hacia la banda: mientras caen sobre la
## cubierta dan una altura; en cuanto uno vuelve mucho más alto, ha pegado en la regala. Ese
## salto es el borde. Medirlo con un rayo LATERAL, como hice primero, engaña: los
## colisionadores de borda son cajas por secciones de 0,75 m, más anchas que la tabla real.

var _barco: Node3D


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_barco = esc.instantiate() as Node3D
	add_child(_barco)
	_barco.set("anclado", true)
	await get_tree().create_timer(4.0).timeout
	var espacio := _barco.get_world_3d().direct_space_state
	for z in [-3.0, -2.0, 0.0, 0.6, 1.5, 2.0, 2.5, 3.0]:
		var borde := 0.0
		var alt_cub := 0.0
		var x := 0.4
		while x < 1.95:
			var arriba: Vector3 = _barco.to_global(Vector3(x, 3.2, z))
			var par := PhysicsRayQueryParameters3D.create(arriba, arriba + Vector3.DOWN * 3.0)
			par.collision_mask = 4
			var g := espacio.intersect_ray(par)
			if g.is_empty():
				break
			var y: float = _barco.to_local(g["position"]).y
			if alt_cub == 0.0:
				alt_cub = y
			if y > alt_cub + 0.12:
				break            # ha pegado en la regala: aquí acaba la cubierta
			borde = x
			x += 0.02
		print("z=%+5.2f  cubierta a %.3f, borde pisable hasta x=%.3f" % [z, alt_cub, borde])
	get_tree().quit(0)
