extends Node
## ¿La cápsula de la botavara sostiene el pie? Mide, con el pie SUELTO actual, dónde queda cada
## vértice del pie respecto a la cápsula: ¿encima, al lado, o cayéndose?
func _ready() -> void: _correr()
func _correr() -> void:
	await get_tree().create_timer(6.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	await get_tree().create_timer(4.0).timeout
	var esq: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("vela_mayor"): sb = x as SoftBody3D
	print("mayor collision_mask = %d (perchas van en capa 16 = bit 5)" % sb.collision_mask)
	var perc: StaticBody3D = null
	for c in esq.get_children():
		if (c as Node).name == "Percha_botavara": perc = c as StaticBody3D
	if perc == null: print("SIN cápsula botavara"); get_tree().quit(1); return
	var cs := perc.get_child(0) as CollisionShape3D
	var cap := cs.shape as CapsuleShape3D
	var t := perc.global_transform * cs.transform
	var cen := t.origin; var eje := t.basis.y.normalized()
	print("cápsula botavara: radio %.3f, mask perc layer=%d" % [cap.radius, perc.collision_layer])
	# distancia de cada vértice del pie al eje de la cápsula
	var g := esq.global_transform
	var vs: PackedVector3Array = (b.find_children("vela_mayor","MeshInstance3D",true,false)[0] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var cerca := 0; var dmin := 999.0; var dmax := 0.0
	for k in vs.size():
		var p := g.affine_inverse() * sb.get_point_transform(k)
		var u := (p - cen).dot(eje)
		if absf(u) > cap.height*0.5: continue
		var d := (p - cen - eje*u).length()
		if d < cap.radius + 0.25:
			cerca += 1; dmin = minf(dmin, d); dmax = maxf(dmax, d)
	print("vértices a menos de 25cm del eje de la botavara: %d, distancia %.3f a %.3f (radio cápsula %.3f)" % [cerca, dmin, dmax, cap.radius])
	get_tree().quit()
