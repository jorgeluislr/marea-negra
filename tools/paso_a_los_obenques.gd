extends Node

## Si cabe un hombre entre la borda y los obenques, o si la barrera de la regala se lo come.
##
## Los obenques mueren en las mesas de guarnición, que sobresalen del costado, y por dentro de
## ellos van los flechastes. `Barco._montar_colisiones()` levanta sobre la regala una barrera
## invisible de 1,6 m para que no se caiga nadie por fuera, y esa barrera cae justo donde está la
## jarcia: no hay por dónde subir.
##
## Se imprime, sección a sección del casco, dónde está la barrera, dónde la jarcia y cuánto hueco
## libre queda para la cápsula del personaje (0,40 m de radio).
##
##     godot --path . tools/paso_a_los_obenques.tscn

const RADIO_JUGADOR := 0.40


func _ready() -> void:
	get_tree().create_timer(200.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(7.0).timeout
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	b.set("anclado", true)
	await get_tree().physics_frame

	# La jarcia, en ejes del barco: cada cabo por su banda y su franja de eslora.
	var al_barco := b.global_transform.affine_inverse()
	var zona := {}          # banda -> [z_min, z_max]
	print("\n─── paso a los obenques ───")
	print("%-16s %8s %8s %8s %8s %8s" % ["pieza", "x min", "x max", "z min", "z max", "y min"])
	for patron in ["obenque_*", "flechaste_*", "mesa_guarnicion_*"]:
		for n in b.find_children(patron, "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var caja := (al_barco * mi.global_transform) * mi.mesh.get_aabb()
			var banda: String = "e" if caja.get_center().x > 0.0 else "b"
			if not zona.has(banda):
				zona[banda] = [INF, -INF]
			zona[banda][0] = minf(zona[banda][0], caja.position.z)
			zona[banda][1] = maxf(zona[banda][1], caja.position.z + caja.size.z)
			if patron != "flechaste_*" or String(mi.name).ends_with("00"):
				print("%-16s %8.3f %8.3f %8.3f %8.3f %8.3f"
					% [mi.name, caja.position.x, caja.position.x + caja.size.x,
						caja.position.z, caja.position.z + caja.size.z, caja.position.y])
	for banda in zona:
		print("la jarcia de %s ocupa de z %.2f a %.2f"
			% ["estribor" if banda == "e" else "babor", zona[banda][0], zona[banda][1]])

	# Y las cajas de borda y barrera que caen en esa franja.
	var cuerpo := b.find_child("Colisiones", false, false) as StaticBody3D
	print("\n%-18s %9s %9s %9s %9s" % ["caja", "x centro", "grueso", "z centro", "alto"])
	for h in cuerpo.get_children():
		var cs := h as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var caja := cs.shape as BoxShape3D
		var p := cs.transform.origin
		var dentro := false
		for banda in zona:
			if p.z >= zona[banda][0] - 0.5 and p.z <= zona[banda][1] + 0.5:
				dentro = true
		if not dentro:
			continue
		print("%-18s %9.3f %9.3f %9.3f %9.3f" % [cs.name, p.x, caja.size.x, p.z, caja.size.y])
	get_tree().quit(0)
