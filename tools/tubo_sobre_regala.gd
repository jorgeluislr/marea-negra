extends Node

## ¿Pasa el TUBO por encima de la regala, o solo su eje?
##
## La comprobación que hice primero miraba el eje del ánima, y eso no basta: el tubo tiene
## radio, así que su generatriz inferior va ~9 cm por debajo del eje y puede estar metida en la
## tabla mientras el eje pasa limpio. Es lo que se ve desde fuera como un cañón que "atraviesa
## el casco".
##
## Se mide donde el tubo cruza el costado: rayo hacia abajo desde el eje, y se compara el hueco
## que hay hasta la madera con el radio del tubo en esa sección.

var _barco: Node3D


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_barco = esc.instantiate() as Node3D
	add_child(_barco)
	_barco.set("anclado", true)
	await get_tree().create_timer(4.0).timeout
	var espacio := _barco.get_world_3d().direct_space_state
	print("%-22s %8s %8s %8s %8s" % ["pieza", "x_cruce", "hueco", "r_tubo", "margen"])
	for c in _barco.find_children("*", "", true, false):
		if not (c.has_method("disparar") and c is Node3D):
			continue
		var n3 := c as Node3D
		var signo := 1.0 if String(c.call("banda")) == "estribor" else -1.0
		var boca: Vector3 = n3.call("boca_global")
		var dir: Vector3 = n3.call("direccion_global")
		# Punto del eje justo sobre el borde de la cubierta pisable (x = 1,56 local).
		var t := 0.0
		var mejor := boca
		while t < 1.2:
			var p := boca - dir * t
			if absf(_barco.to_local(p).x) <= 1.56:
				mejor = p
				break
			t += 0.01
		var par := PhysicsRayQueryParameters3D.create(mejor, mejor + Vector3.DOWN * 1.0)
		par.collision_mask = 4
		var g := espacio.intersect_ray(par)
		var hueco: float = (mejor.y - float(g["position"].y)) if not g.is_empty() else INF
		# Radio exterior del tubo en esa sección, del modelo a 3 libras: la caña ronda 0,098 y
		# las fajas 0,107; se toma la mayor, que es la que topa.
		var r_tubo := 0.107
		print("%-22s %8.3f %8.3f %8.3f %+8.3f  %s"
			% [n3.name, absf(_barco.to_local(mejor).x), hueco, r_tubo, hueco - r_tubo,
				"OK" if hueco - r_tubo > 0.0 else "EL TUBO ENTRA EN LA MADERA"])
	get_tree().quit(0)
