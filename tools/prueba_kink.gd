extends Node
## Localiza el vértice del borde que se desvía 69cm y lo caracteriza: ¿índice alto (duplicado sin
## soldar)? ¿anclado? ¿cuántos vecinos? ¿tiene gemelo coincidente en reposo?
func _ready() -> void: _correr()
func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	Viento.direccion = Vector3(1,0,0.5).normalized(); Viento.fuerza = 1.3
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("vela_mayor"): sb = x as SoftBody3D
	var arr := sb.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var n := vs.size()
	var cuenta := {}
	for t in range(0, idx.size(), 3):
		for e in [[idx[t],idx[t+1]],[idx[t+1],idx[t+2]],[idx[t+2],idx[t]]]:
			var a: int = e[0]; var c: int = e[1]
			var key := "%d_%d" % [min(a,c), max(a,c)]
			cuenta[key] = int(cuenta.get(key,0)) + 1
	var vec_borde := {}
	for key in cuenta:
		if cuenta[key] == 1:
			var pr := (key as String).split("_"); var a := int(pr[0]); var c := int(pr[1])
			if not vec_borde.has(a): vec_borde[a]=[]
			if not vec_borde.has(c): vec_borde[c]=[]
			vec_borde[a].append(c); vec_borde[c].append(a)
	await get_tree().create_timer(8.0).timeout
	var kv := -1; var kd := 0.0
	for v in vec_borde:
		if vec_borde[v].size() == 2:
			var m := (sb.get_point_transform(vec_borde[v][0]) + sb.get_point_transform(vec_borde[v][1])) * 0.5
			var d := (sb.get_point_transform(v) - m).length()
			if d > kd: kd = d; kv = v
	# vecinos totales del kink (grado en toda la malla)
	var grado := 0
	for t in range(0, idx.size(), 3):
		for e in [[idx[t],idx[t+1]],[idx[t+1],idx[t+2]],[idx[t+2],idx[t]]]:
			if e[0]==kv or e[1]==kv: grado += 1
	# ¿gemelo coincidente en reposo?
	var gemelo := -1
	for k in n:
		if k != kv and (vs[k]-vs[kv]).length() < 0.002: gemelo = k
	print("kink en v%d (de %d): desviacion %.2f m, vecinos de borde=%d, grado total=%d, gemelo coincidente=%d, rest_y=%.2f" %
		[kv, n, kd, vec_borde[kv].size(), grado/2, gemelo, vs[kv].y])
	get_tree().quit()
