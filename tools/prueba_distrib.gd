extends Node
## ¿El estiramiento es uniforme o son pocos bordes disparados? Mide la mediana, p90, p99 y cuenta
## bordes muy estirados. Y caracteriza el peor borde: ¿es una costura UV (vértices duplicados)?
func _ready() -> void: _correr()
func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	Viento.direccion = Vector3(1,0,0.4).normalized(); Viento.fuerza = 1.3
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
	var g := b.global_transform.affine_inverse()
	var rp := PackedVector3Array(); rp.resize(vs.size())
	for k in vs.size(): rp[k] = g * sb.get_point_transform(k)
	await get_tree().create_timer(6.0).timeout
	for k in vs.size(): rp[k] = g * sb.get_point_transform(k)
	var ests: Array[float] = []
	var peor := 0.0; var pa := -1; var pc := -1
	for t in range(0, idx.size(), 3):
		for e in [[idx[t],idx[t+1]],[idx[t+1],idx[t+2]],[idx[t+2],idx[t]]]:
			var a: int = e[0]; var c: int = e[1]
			var lr := (tr*vs[a]-tr*vs[c]).length(); var ld := (rp[a]-rp[c]).length()
			var est := (ld-lr)/maxf(lr,0.001); ests.append(est)
			if est > peor: peor = est; pa = a; pc = c
	ests.sort()
	var n := ests.size()
	var may50 := 0; var may20 := 0
	for e in ests:
		if e > 0.5: may50 += 1
		if e > 0.2: may20 += 1
	print("estiramiento: mediana %+.1f%%  p90 %+.1f%%  p99 %+.1f%%  max %+.1f%%" %
		[ests[n/2]*100, ests[int(n*0.9)]*100, ests[int(n*0.99)]*100, ests[n-1]*100])
	print("bordes con >20%% estiramiento: %d de %d (%.1f%%) | >50%%: %d" % [may20, n, float(may20)/n*100, may50])
	# el peor borde: ¿vértices en la misma posición de reposo (costura)?
	print("peor borde: v%d-v%d, reposo separados %.3fm, ahora %.3fm" % [pa, pc, (tr*vs[pa]-tr*vs[pc]).length(), (rp[pa]-rp[pc]).length()])
	# ¿cuántos vértices comparten posición de reposo con otro (costuras UV)?
	var dup := 0
	for k in range(0, vs.size(), 1):
		pass
	get_tree().quit()
