extends SceneTree

## Comprueba si ARRAY_BONES de la vela usa indices del Skeleton3D o del Skin.
## Si no coinciden, vela_fisica.gd esta aplicando la matriz de OTRO hueso a algunos vertices.

func _init() -> void:
	var ps: PackedScene = load("res://assets/models/balandra.glb")
	var raiz := ps.instantiate()
	get_root().add_child(raiz)
	await process_frame

	var skels := raiz.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		print("SIN ESQUELETO"); quit(); return
	var skel := skels[0] as Skeleton3D

	print("--- ESQUELETO: %d huesos ---" % skel.get_bone_count())
	for i in skel.get_bone_count():
		print("  [%d] %s  padre=%d" % [i, skel.get_bone_name(i), skel.get_bone_parent(i)])

	for nombre in ["vela_mayor", "foque"]:
		var l := raiz.find_children(nombre, "MeshInstance3D", true, false)
		if l.is_empty():
			print("\n### no encuentro %s" % nombre); continue
		var mi := l[0] as MeshInstance3D
		print("\n--- MALLA %s ---" % nombre)
		var sk: Skin = mi.skin
		if sk == null:
			print("  skin = NULL (usa indices de esqueleto directos)")
		else:
			print("  skin con %d binds:" % sk.get_bind_count())
			for i in sk.get_bind_count():
				var bn := sk.get_bind_name(i)
				var bb := sk.get_bind_bone(i)
				var enskel := skel.find_bone(bn) if bn != "" else bb
				print("    bind[%d] nombre='%s' bind_bone=%d  -> hueso esqueleto %d (%s)"
					% [i, bn, bb, enskel,
					skel.get_bone_name(enskel) if enskel >= 0 else "?"])

		var arr := mi.mesh.surface_get_arrays(0)
		var hu: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var pe: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var vistos := {}
		var sumas_mal := 0
		for k in vs.size():
			var s := 0.0
			for j in 4:
				var w: float = pe[k * 4 + j]
				s += w
				if w > 0.0:
					var b: int = hu[k * 4 + j]
					vistos[b] = int(vistos.get(b, 0)) + 1
			if absf(s - 1.0) > 0.01:
				sumas_mal += 1
		var ks := vistos.keys(); ks.sort()
		print("  vertices=%d  pesos que NO suman 1: %d" % [vs.size(), sumas_mal])
		print("  indices distintos en ARRAY_BONES: %s" % str(ks))
		for b in ks:
			var nom_skel := skel.get_bone_name(b) if b < skel.get_bone_count() else "FUERA DE RANGO"
			var nom_skin := "-"
			if sk != null and b < sk.get_bind_count():
				nom_skin = sk.get_bind_name(b)
				if nom_skin == "":
					var bb2 := sk.get_bind_bone(b)
					nom_skin = skel.get_bone_name(bb2) if bb2 >= 0 and bb2 < skel.get_bone_count() else "?"
			print("    idx %d -> como esqueleto:'%s'   como skin:'%s'   (%d vertices)"
				% [b, nom_skel, nom_skin, vistos[b]])
	quit()
