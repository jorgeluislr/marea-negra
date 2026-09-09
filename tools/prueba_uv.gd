extends SceneTree

## Cuanta informacion de UV y de NORMAL destruye el soldado de vela_fisica.gd.

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
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var nor: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	print("\n=== %s ===" % nombre)

	var canon := PackedInt32Array(); canon.resize(vs.size())
	var mapa := {}
	var rep := PackedInt32Array()
	for k in vs.size():
		var v := vs[k]
		var clave := "%d_%d_%d" % [roundi(v.x * 2000.0), roundi(v.y * 2000.0), roundi(v.z * 2000.0)]
		if mapa.has(clave): canon[k] = mapa[clave]
		else:
			mapa[clave] = rep.size(); canon[k] = rep.size(); rep.append(k)

	# grupos con mas de un miembro: cuantos difieren en UV / en normal
	var miembros := {}
	for k in vs.size():
		var c: int = canon[k]
		if not miembros.has(c): miembros[c] = PackedInt32Array()
		var a: PackedInt32Array = miembros[c]; a.append(k); miembros[c] = a
	var dobles := 0; var uv_dif := 0; var nor_dif := 0
	var salto_max := 0.0; var salto_sum := 0.0
	var ang_max := 0.0
	for c in miembros:
		var ms: PackedInt32Array = miembros[c]
		if ms.size() < 2: continue
		dobles += 1
		var k0: int = ms[0]
		var peor_uv := 0.0; var peor_ang := 0.0
		for i in range(1, ms.size()):
			var k1: int = ms[i]
			if not uvs.is_empty():
				peor_uv = maxf(peor_uv, uvs[k0].distance_to(uvs[k1]))
			if not nor.is_empty():
				peor_ang = maxf(peor_ang, rad_to_deg(nor[k0].angle_to(nor[k1])))
		if peor_uv > 0.0005: uv_dif += 1
		if peor_ang > 1.0: nor_dif += 1
		salto_max = maxf(salto_max, peor_uv); salto_sum += peor_uv
		ang_max = maxf(ang_max, peor_ang)
	print("  vertices dobles (soldados): %d" % dobles)
	print("  de esos, con UV DISTINTO:     %d   (salto UV medio %.4f, maximo %.4f)"
		% [uv_dif, salto_sum / maxf(dobles, 1), salto_max])
	print("  de esos, con NORMAL distinta: %d   (angulo maximo %.1f grados)" % [nor_dif, ang_max])

	# triangulos cuyo UV se deforma al soldar: comparo el perimetro UV antes/despues
	var peor_tri := 0.0; var n_tri_mal := 0; var tot := 0
	for t in range(0, idx.size(), 3):
		tot += 1
		var a0: int = idx[t]; var b0: int = idx[t + 1]; var c0: int = idx[t + 2]
		var per_o := uvs[a0].distance_to(uvs[b0]) + uvs[b0].distance_to(uvs[c0]) + uvs[c0].distance_to(uvs[a0])
		var a1: int = rep[canon[a0]]; var b1: int = rep[canon[b0]]; var c1: int = rep[canon[c0]]
		var per_s := uvs[a1].distance_to(uvs[b1]) + uvs[b1].distance_to(uvs[c1]) + uvs[c1].distance_to(uvs[a1])
		var f := per_s / maxf(per_o, 1e-6)
		if f > 1.5 or f < 0.667:
			n_tri_mal += 1
			peor_tri = maxf(peor_tri, f)
	print("  triangulos con el UV DEFORMADO al soldar: %d de %d (%.1f %%), peor factor x%.1f"
		% [n_tri_mal, tot, 100.0 * n_tri_mal / maxf(tot, 1), peor_tri])
