extends SceneTree

## Reproduce el soldado y examina los vertices que salen en el visor como peores.
## Busca: islas sin anclaje, valencias raras, y a cuantos saltos esta cada uno de un anclaje.

const MIRAR := [115, 128, 129, 130, 131, 146, 147, 347, 411, 419, 893]

func _init() -> void:
	var ps: PackedScene = load("res://assets/models/balandra.glb")
	var raiz := ps.instantiate()
	get_root().add_child(raiz)
	await process_frame
	var mi := (raiz.find_children("vela_mayor", "MeshInstance3D", true, false)[0]) as MeshInstance3D
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]

	# mismo soldado que vela_fisica.gd
	var canon := PackedInt32Array(); canon.resize(vs.size())
	var mapa := {}
	var vs_s := PackedVector3Array()
	for k in vs.size():
		var v := vs[k]
		var clave := "%d_%d_%d" % [roundi(v.x * 2000.0), roundi(v.y * 2000.0), roundi(v.z * 2000.0)]
		if mapa.has(clave): canon[k] = mapa[clave]
		else:
			mapa[clave] = vs_s.size(); canon[k] = vs_s.size(); vs_s.append(v)
	var n := vs_s.size()
	var fijo := PackedByteArray(); fijo.resize(n)
	for k in vs.size():
		if cols[k].b > 0.5: fijo[canon[k]] = 1

	# grafo de aristas de la malla soldada
	var vec := {}
	for t in range(0, idx.size(), 3):
		for j in 3:
			var a: int = canon[idx[t + j]]
			var b: int = canon[idx[t + (j + 1) % 3]]
			if a == b: continue
			if not vec.has(a): vec[a] = {}
			if not vec.has(b): vec[b] = {}
			vec[a][b] = true
			vec[b][a] = true

	# islas
	var isla := PackedInt32Array(); isla.resize(n)
	for i in n: isla[i] = -1
	var n_islas := 0
	var info: Array = []
	for i in n:
		if isla[i] != -1: continue
		var pila: Array = [i]
		var tam := 0
		var anc := 0
		while not pila.is_empty():
			var x: int = pila.pop_back()
			if isla[x] != -1: continue
			isla[x] = n_islas
			tam += 1
			if fijo[x] == 1: anc += 1
			for y in vec.get(x, {}):
				if isla[y] == -1: pila.append(y)
		info.append([n_islas, tam, anc])
		n_islas += 1
	print("islas de la malla soldada: %d" % n_islas)
	for f in info:
		var marca := ""
		if f[2] == 0: marca = "   <<< SIN NINGUN ANCLAJE"
		print("   isla %d: %d vertices, %d anclados%s" % [f[0], f[1], f[2], marca])

	# BFS de distancias al anclaje mas cercano
	var dist := PackedInt32Array(); dist.resize(n)
	for i in n: dist[i] = -1
	var cola: Array = []
	for i in n:
		if fijo[i] == 1:
			dist[i] = 0; cola.append(i)
	var cab := 0
	while cab < cola.size():
		var x: int = cola[cab]; cab += 1
		for y in vec.get(x, {}):
			if dist[y] == -1:
				dist[y] = dist[x] + 1
				cola.append(y)
	var peor_d := 0
	var sin_alcance := 0
	for i in n:
		if dist[i] < 0: sin_alcance += 1
		elif dist[i] > peor_d: peor_d = dist[i]
	print("\nsaltos hasta el anclaje mas cercano: maximo %d ; vertices que NO alcanzan ninguno: %d"
		% [peor_d, sin_alcance])

	print("\nlos que salen en el visor:")
	for i in MIRAR:
		if i >= n: continue
		var vecinos: Array = vec.get(i, {}).keys()
		vecinos.sort()
		print("   v%-4d isla %d  %s  valencia %d  saltos a ancla %d  reposo (%.2f, %.2f, %.2f)"
			% [i, isla[i], "FIJO " if fijo[i] == 1 else "libre", vecinos.size(), dist[i],
			vs_s[i].x, vs_s[i].y, vs_s[i].z])
		print("        vecinos: %s" % str(vecinos))
	quit()
