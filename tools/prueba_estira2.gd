extends Node
## Mide el estiramiento REAL de los triángulos del SoftBody (posición renderizada) respecto a su
## longitud de reposo, navegando y trimado. Reporta dónde estira más.
func _ready() -> void: _correr()
func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	Viento.direccion = Vector3(1,0,1).normalized(); Viento.fuerza = 1.5
	var esq: Skeleton3D = b.find_children("*","Skeleton3D",true,false)[0]
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
	# longitud de reposo de cada arista (malla sin deformar, en espacio del cuerpo)
	await get_tree().create_timer(8.0).timeout
	print("trim = %.1f" % rad_to_deg(esq.get_bone_pose_rotation(esq.find_bone("vela")).get_euler().y))
	var g := b.global_transform.affine_inverse()
	# posicion renderizada por el softbody
	var rp := PackedVector3Array(); rp.resize(vs.size())
	for k in vs.size(): rp[k] = g * sb.get_point_transform(k)
	# tack = vertice renderizado mas bajo
	var tack := 0; var ymin := 999.0
	for k in vs.size():
		if rp[k].y < ymin: ymin = rp[k].y; tack = k
	# estiramiento: |rp[a]-rp[b]| / |rest[a]-rest[b]|
	var peor := 0.0; var suma := 0.0; var nn := 0; var lej := 0.0; var nl := 0; var kpeor := -1
	for t in range(0, idx.size(), 3):
		for e in [[idx[t],idx[t+1]],[idx[t+1],idx[t+2]],[idx[t+2],idx[t]]]:
			var a: int = e[0]; var c: int = e[1]
			var lr := (tr*vs[a] - tr*vs[c]).length()
			var ld := (rp[a] - rp[c]).length()
			var est := (ld-lr)/maxf(lr,0.001)
			if rp[a].distance_to(rp[tack]) < 2.5:
				suma += est; nn += 1
				if est > peor: peor = est; kpeor = a
			else:
				lej += est; nl += 1
	print("cerca del tack: estiramiento medio %+.1f%%, peor %+.1f%%" % [suma/maxf(nn,1)*100, peor*100])
	print("resto de la vela: estiramiento medio %+.1f%%" % [lej/maxf(nl,1)*100])
	print("rigidez del solver: %.2f" % sb.linear_stiffness)
	get_tree().quit()
