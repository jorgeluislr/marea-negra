extends Node
## ¿Se apoya el paño en las perchas o las atraviesa? Cuenta puntos del solver dentro de cada
## cápsula, leyendo la cápsula del propio colisionador.
func _ready() -> void: _correr()

func _dentro(esq: Skeleton3D, sb: SoftBody3D, n: int, cuerpo: StaticBody3D) -> Array:
	var cs := cuerpo.get_child(0) as CollisionShape3D
	var cap := cs.shape as CapsuleShape3D
	var t := cuerpo.transform * cs.transform
	var c := t.origin
	var eje := t.basis.y.normalized()
	var media := cap.height * 0.5 - cap.radius
	# (dentro del cilindro central de la cápsula, que es lo que importa aquí)
	var g := esq.global_transform
	var cuenta := 0
	var hondo := 0.0
	for k in n:
		var p := g.affine_inverse() * sb.get_point_transform(k)
		var u: float = (p - c).dot(eje)
		if absf(u) > media: continue
		var r := (p - c - eje * u).length()
		if r < cap.radius:
			cuenta += 1
			hondo = maxf(hondo, cap.radius - r)
	return [cuenta, hondo, cap.radius]

func _correr() -> void:
	await get_tree().create_timer(6.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	await get_tree().create_timer(4.0).timeout
	var esq: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
	for par in [["vela_mayor", 1347], ["foque", 253]]:
		var sb: SoftBody3D = null
		for x in b.find_children("*", "SoftBody3D", true, false):
			if (x as Node).name.ends_with(par[0]): sb = x as SoftBody3D
		if sb == null: continue
		print("%s (mask=%d):" % [par[0], sb.collision_mask])
		for c in esq.get_children():
			if not (c is StaticBody3D) or not (c as Node).name.begins_with("Percha_"): continue
			var r := _dentro(esq, sb, int(par[1]), c as StaticBody3D)
			print("   %-22s radio %.3f -> %d puntos dentro, hasta %.3f m" % [(c as Node).name, r[2], r[0], r[1]])
	get_tree().quit()
