extends SceneTree

## Reproduce el soldado de vela_fisica.gd y busca duplicados que NO se sueldan,
## grupos soldados con pesos distintos, y grupos con color de anclaje incoherente.

func _init() -> void:
	var ps: PackedScene = load("res://assets/models/balandra.glb")
	var raiz := ps.instantiate()
	get_root().add_child(raiz)
	await process_frame
	for nombre in ["vela_mayor", "foque"]:
		var l := raiz.find_children(nombre, "MeshInstance3D", true, false)
		if l.is_empty(): continue
		_revisar(nombre, l[0] as MeshInstance3D)
	quit()


func _revisar(nombre: String, mi: MeshInstance3D) -> void:
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var hu: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var pe: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	print("\n=== %s : %d vertices en el .glb ===" % [nombre, vs.size()])

	# 1) soldado tal cual lo hace el script (cuantizado a 0,5 mm)
	var canon := PackedInt32Array(); canon.resize(vs.size())
	var mapa := {}
	var n_sold := 0
	for k in vs.size():
		var v := vs[k]
		var clave := "%d_%d_%d" % [roundi(v.x * 2000.0), roundi(v.y * 2000.0), roundi(v.z * 2000.0)]
		if mapa.has(clave): canon[k] = mapa[clave]
		else:
			mapa[clave] = n_sold; canon[k] = n_sold; n_sold += 1
	print("  soldado cuantizado 0,5 mm -> %d vertices (junta %d)" % [n_sold, vs.size() - n_sold])

	# 2) soldado por posicion EXACTA (los duplicados de glTF son copias bit a bit)
	var mapa_ex := {}
	var n_ex := 0
	for k in vs.size():
		var c2 := vs[k]
		if mapa_ex.has(c2): pass
		else:
			mapa_ex[c2] = n_ex; n_ex += 1
	print("  soldado por posicion EXACTA  -> %d vertices (junta %d)" % [n_ex, vs.size() - n_ex])

	# 3) pares realmente coincidentes (< 1 mm) que el cuantizado dejo SEPARADOS
	#    rejilla espacial de 5 cm para no comparar todos contra todos
	var rejilla := {}
	for k in vs.size():
		var v := vs[k]
		var ck := "%d_%d_%d" % [floori(v.x / 0.05), floori(v.y / 0.05), floori(v.z / 0.05)]
		if not rejilla.has(ck): rejilla[ck] = PackedInt32Array()
		var a: PackedInt32Array = rejilla[ck]; a.append(k); rejilla[ck] = a
	var fallos := 0
	var ejemplos: Array = []
	for k in vs.size():
		var v := vs[k]
		var bx := floori(v.x / 0.05); var by := floori(v.y / 0.05); var bz := floori(v.z / 0.05)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var ck2 := "%d_%d_%d" % [bx + dx, by + dy, bz + dz]
					if not rejilla.has(ck2): continue
					for m in (rejilla[ck2] as PackedInt32Array):
						if m <= k: continue
						if vs[k].distance_to(vs[m]) > 0.001: continue
						if canon[k] != canon[m]:
							fallos += 1
							if ejemplos.size() < 8:
								ejemplos.append("v%d~v%d d=%.6f mm" % [k, m, vs[k].distance_to(vs[m]) * 1000.0])
	print("  pares a <1 mm que el soldado dejo SEPARADOS: %d %s" % [fallos, str(ejemplos)])

	# 4) grupos soldados con pesos o color de anclaje incoherentes
	var miembros := {}
	for k in vs.size():
		var c3: int = canon[k]
		if not miembros.has(c3): miembros[c3] = PackedInt32Array()
		var a2: PackedInt32Array = miembros[c3]; a2.append(k); miembros[c3] = a2
	var peso_mal := 0; var color_mal := 0; var peor := 0.0
	for c4 in miembros:
		var ms: PackedInt32Array = miembros[c4]
		if ms.size() < 2: continue
		var k0: int = ms[0]
		for i in range(1, ms.size()):
			var k1: int = ms[i]
			for j in 4:
				if hu[k0 * 4 + j] != hu[k1 * 4 + j]:
					peso_mal += 1; break
				var d := absf(pe[k0 * 4 + j] - pe[k1 * 4 + j])
				peor = maxf(peor, d)
				if d > 0.01: peso_mal += 1; break
			if not cols.is_empty() and (cols[k0].b > 0.5) != (cols[k1].b > 0.5):
				color_mal += 1
	print("  grupos con pesos incoherentes: %d (peor dif %.4f) | con color de anclaje incoherente: %d"
		% [peso_mal, peor, color_mal])
	var anc := 0
	if not cols.is_empty():
		var vistos := {}
		for k in vs.size():
			if cols[k].b > 0.5: vistos[canon[k]] = true
		anc = vistos.size()
	print("  anclados tras soldar: %d de %d" % [anc, n_sold])
