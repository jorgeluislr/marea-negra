extends Node
## Localiza el vértice que más se dispara en el tack y reporta si está anclado, cuántos vecinos
## tiene anclados, y a dónde vuela. Para saber si es un caso puntual o el rincón entero.
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
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var tr := Transform3D(); var x: Node = mi
	while x != null and x != esq:
		if x is Node3D: tr = (x as Node3D).transform * tr
		x = x.get_parent()
	# vecinos por aristas
	var vec := {}
	for t in range(0, idx.size(), 3):
		for e in [[idx[t],idx[t+1]],[idx[t+1],idx[t+2]],[idx[t+2],idx[t]]]:
			var a: int = e[0]; var c: int = e[1]
			if not vec.has(a): vec[a]=[]
			if not vec.has(c): vec[c]=[]
			if not (c in vec[a]): vec[a].append(c)
			if not (a in vec[c]): vec[c].append(a)
	await get_tree().create_timer(8.0).timeout
	var g := b.global_transform.affine_inverse()
	# el peor vertice: mayor desviacion respecto a la media de sus vecinos (deformada)
	var peor := 0.0; var kp := -1
	for k in vs.size():
		if not vec.has(k): continue
		var p := g * sb.get_point_transform(k)
		var media := Vector3.ZERO
		for n in vec[k]: media += g * sb.get_point_transform(n)
		media /= vec[k].size()
		var d := (p - media).length()
		if d > peor: peor = d; kp = k
	# ¿cuantos vertices se disparan asi (>0.4m de la media de sus vecinos)?
	var n_malos := 0
	for k in vs.size():
		if not vec.has(k): continue
		var p := g * sb.get_point_transform(k)
		var media := Vector3.ZERO
		for n in vec[k]: media += g * sb.get_point_transform(n)
		media /= vec[k].size()
		if (p-media).length() > 0.4: n_malos += 1
	var anc_vec := 0
	for n in vec[kp]:
		if cols[n].b > 0.5: anc_vec += 1
	print("peor vertice %d: se dispara %.2f m de sus vecinos | anclado=%s | vecinos=%d, de ellos anclados=%d" %
		[kp, peor, cols[kp].b>0.5, vec[kp].size(), anc_vec])
	print("vertices que se disparan >0.4m: %d de %d" % [n_malos, vs.size()])
	get_tree().quit()
