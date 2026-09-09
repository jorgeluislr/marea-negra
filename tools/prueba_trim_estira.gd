extends Node
## ¿El estiramiento de la mayor lo causa el TRIM (hueso vela)? Mide el estiramiento con viento de
## frente (sin trim) y de costado (trim máximo).
func _ready() -> void: _correr()
func _mide(b: Node3D, esq: Skeleton3D) -> Array:
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("vela_mayor"): sb = x as SoftBody3D
	var mi := b.find_children("vela_mayor","MeshInstance3D",true,false)[0] as MeshInstance3D
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var tr := Transform3D(); var x: Node = mi
	while x != null and x != esq:
		if x is Node3D: tr = (x as Node3D).transform * tr
		x = x.get_parent()
	var g := b.global_transform.affine_inverse()
	var rp := PackedVector3Array(); rp.resize(vs.size())
	for k in vs.size(): rp[k] = g * sb.get_point_transform(k)
	var suma := 0.0; var nn := 0; var peor := 0.0
	for t in range(0, idx.size(), 3):
		for e in [[idx[t],idx[t+1]],[idx[t+1],idx[t+2]],[idx[t+2],idx[t]]]:
			var a: int = e[0]; var c: int = e[1]
			var lr := (tr*vs[a]-tr*vs[c]).length(); var ld := (rp[a]-rp[c]).length()
			var est := (ld-lr)/maxf(lr,0.001); suma += est; nn += 1
			peor = maxf(peor, est)
	return [suma/nn*100, peor*100, rad_to_deg(esq.get_bone_pose_rotation(esq.find_bone("vela")).get_euler().y)]
func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	var esq: Skeleton3D = b.find_children("*","Skeleton3D",true,false)[0]
	# viento de frente (proa hacia -Z): sin componente lateral -> sin trim
	Viento.direccion = Vector3(0,0,-1); Viento.fuerza = 1.3
	await get_tree().create_timer(8.0).timeout
	var r0 := _mide(b, esq)
	print("SIN trim  (trim=%.1f): estiramiento medio %+.1f%%  peor %+.1f%%" % [r0[2], r0[0], r0[1]])
	# viento de costado -> trim máximo
	Viento.direccion = Vector3(1,0,0.2).normalized(); Viento.fuerza = 1.3
	await get_tree().create_timer(8.0).timeout
	var r1 := _mide(b, esq)
	print("CON trim  (trim=%.1f): estiramiento medio %+.1f%%  peor %+.1f%%" % [r1[2], r1[0], r1[1]])
	get_tree().quit()
