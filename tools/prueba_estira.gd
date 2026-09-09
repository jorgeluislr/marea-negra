extends Node
## ¿La piel estira los triángulos del rincón del puño de amura al trimar? Compara las longitudes
## de arista de la malla (posición con piel) a trim 0 y trim máximo, en la zona del tack.
func _ready() -> void: _correr()
func _skin_pos(esq: Skeleton3D, tr: Transform3D, vs: PackedVector3Array, hu: PackedInt32Array, pe: PackedFloat32Array, k: int) -> Vector3:
	var p := tr * vs[k]
	var q := Vector3.ZERO; var tot := 0.0
	for j in 4:
		var w: float = pe[k*4+j]
		if w<=0: continue
		var bi := hu[k*4+j]
		var M := esq.get_bone_global_pose(bi) * esq.get_bone_global_rest(bi).affine_inverse()
		q += (M * p) * w; tot += w
	return q if tot>0 else p
func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	var esq: Skeleton3D = b.find_children("*","Skeleton3D",true,false)[0]
	var mi := b.find_children("vela_mayor","MeshInstance3D",true,false)[0] as MeshInstance3D
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var hu: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var pe: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var tr := Transform3D(); var x: Node = mi
	while x != null and x != esq:
		if x is Node3D: tr = (x as Node3D).transform * tr
		x = x.get_parent()
	# tack = vertice mas bajo y adelante
	var iv := esq.find_bone("vela")
	# trim 0
	Viento.direccion = Vector3(0,0,-1); Viento.fuerza = 0.0
	await get_tree().create_timer(2.0).timeout
	var p0 := PackedVector3Array(); p0.resize(vs.size())
	for k in vs.size(): p0[k] = _skin_pos(esq, tr, vs, hu, pe, k)
	# tack: vertice con menor y en p0
	var tack := 0; var ymin := 999.0
	for k in vs.size():
		if p0[k].y < ymin: ymin = p0[k].y; tack = k
	# trim maximo
	Viento.direccion = Vector3(1,0,1).normalized(); Viento.fuerza = 1.5
	await get_tree().create_timer(3.0).timeout
	print("trim = %.1f grados" % rad_to_deg(esq.get_bone_pose_rotation(iv).get_euler().y))
	var p1 := PackedVector3Array(); p1.resize(vs.size())
	for k in vs.size(): p1[k] = _skin_pos(esq, tr, vs, hu, pe, k)
	# aristas cerca del tack (< 2m) : comparar longitud trim0 vs trim
	var peor := 0.0; var suma := 0.0; var nn := 0; var lejos := 0.0; var nl := 0
	for t in range(0, idx.size(), 3):
		for e in [[idx[t],idx[t+1]],[idx[t+1],idx[t+2]],[idx[t+2],idx[t]]]:
			var a: int = e[0]; var c: int = e[1]
			var l0 := (p0[a]-p0[c]).length(); var l1 := (p1[a]-p1[c]).length()
			var estira := (l1-l0)/maxf(l0,0.001)
			var cerca := (p0[a].distance_to(p0[tack]) < 2.0)
			if cerca:
				peor = maxf(peor, absf(estira)); suma += absf(estira); nn += 1
			else:
				lejos += absf(estira); nl += 1
	print("cerca del tack: %d aristas, estiramiento medio %.1f%%, peor %.1f%%" % [nn, suma/maxf(nn,1)*100, peor*100])
	print("lejos del tack: %d aristas, estiramiento medio %.1f%%" % [nl, lejos/maxf(nl,1)*100])
	# pesos del tack y vecinos
	var s := "tack v%d pesos: " % tack
	for j in 4:
		if pe[tack*4+j]>0: s += "%s=%.2f " % [esq.get_bone_name(hu[tack*4+j]), pe[tack*4+j]]
	print(s)
	get_tree().quit()
