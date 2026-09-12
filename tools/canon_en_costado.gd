extends Node

## Cuánto se sale cada pieza por fuera del costado, medido con rayos contra el CASCO y no
## contra las cifras con que se colocó.
##
## Lo que se busca no es la boca —esa TIENE que salir fuera— sino la CUREÑA: si sus ruedas
## quedan fuera del forro, el cañón está montado en el aire y atraviesa la madera. Se mira
## además a dos alturas, porque el casco se abre hacia arriba y la sección que importa es la
## de la rueda, no la de la regala.

var _barco: Node3D


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_barco = esc.instantiate() as Node3D
	add_child(_barco)
	_barco.set("anclado", true)
	await get_tree().create_timer(4.0).timeout
	var espacio := _barco.get_world_3d().direct_space_state

	print("%-22s %7s %8s %8s %8s" % ["pieza", "lado", "rueda", "costado", "margen"])
	for c in _barco.find_children("*", "", true, false):
		if not (c.has_method("disparar") and c is Node3D):
			continue
		var n3 := c as Node3D
		var signo := 1.0 if String(c.call("banda")) == "estribor" else -1.0
		# La rueda de fuera está a 0,2185 del centro, hacia la banda.
		var rueda_x: float = n3.position.x + signo * 0.2185
		# Rayo desde crujía hacia la banda, a la altura del EJE de las ruedas.
		var y_rueda: float = n3.position.y - 0.3575 + 0.13
		var desde: Vector3 = _barco.to_global(Vector3(0.0, y_rueda, n3.position.z))
		var hacia: Vector3 = _barco.to_global(Vector3(signo * 4.0, y_rueda, n3.position.z))
		var par := PhysicsRayQueryParameters3D.create(desde, hacia)
		par.collision_mask = 4
		var g := espacio.intersect_ray(par)
		var costado := INF
		if not g.is_empty():
			costado = absf(_barco.to_local(g["position"]).x)
		var margen: float = costado - absf(rueda_x)
		print("%-22s %7s %8.3f %8.3f %+8.3f  %s"
			% [n3.name, String(c.call("banda")), absf(rueda_x), costado, margen,
				"OK" if margen > 0.0 else "SE SALE"])
	get_tree().quit(0)
