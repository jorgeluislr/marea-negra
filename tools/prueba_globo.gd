extends Node
## ¿Cuánto se hincha la mayor izada y hasta dónde llega? Mide la excursión del paño respecto a
## su forma de reposo, y si pasa por delante del mástil o por encima del pico.
func _ready() -> void: _correr()

func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	var esq: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
	var mi := b.find_children("vela_mayor", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("vela_mayor"): sb = x as SoftBody3D
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var tr := Transform3D(); var x2: Node = mi
	while x2 != null and x2 != esq:
		if x2 is Node3D: tr = (x2 as Node3D).transform * tr
		x2 = x2.get_parent()
	# el mástil y el pico, en espacio del esqueleto
	var pm := (b.find_children("mastil_v3", "MeshInstance3D", true, false)[0] as MeshInstance3D)
	var abm := mi.mesh.get_aabb()
	print("viento: fuerza %.2f -> empuje %.1f m/s2 contra peso propio 3.0" % [Viento.fuerza, Viento.fuerza * 7.0])
	for paso in 5:
		await get_tree().create_timer(2.0).timeout
		var g := esq.global_transform
		var exc := 0.0; var exc_med := 0.0
		var lo := Vector3.INF; var hi := -Vector3.INF
		for k in vs.size():
			var real := g.affine_inverse() * sb.get_point_transform(k)
			var rep := tr * vs[k]
			var e := (real - rep).length()
			exc = maxf(exc, e); exc_med += e
			lo = Vector3(minf(lo.x, real.x), minf(lo.y, real.y), minf(lo.z, real.z))
			hi = Vector3(maxf(hi.x, real.x), maxf(hi.y, real.y), maxf(hi.z, real.z))
		print("  t=%2ds  excursion media %.2f m, max %.2f m | caja del pano %.2f x %.2f x %.2f | tope y=%.2f (el palo llega a %.2f)"
			% [(paso + 1) * 2, exc_med / vs.size(), exc, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, hi.y, 10.25])
	get_tree().quit()
