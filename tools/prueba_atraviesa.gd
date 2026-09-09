extends Node
## ¿El paño atraviesa las perchas? Cuenta puntos del solver dentro del cilindro del mástil, de
## la botavara y del pico, y cuánto se meten.
func _ready() -> void: _correr()

func _eje(mi: MeshInstance3D, esq: Skeleton3D) -> Array:
	var tr := Transform3D(); var x: Node = mi
	while x != null and x != esq:
		if x is Node3D: tr = (x as Node3D).transform * tr
		x = x.get_parent()
	var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var c := Vector3.ZERO
	for v in vs: c += tr * v
	c /= vs.size()
	# eje: la dirección de mayor extensión, por muestreo grueso
	var mejor := Vector3.RIGHT; var largo := 0.0
	for d in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		var lo := INF; var hi := -INF
		for v in vs:
			var t: float = (tr * v - c).dot(d)
			lo = minf(lo, t); hi = maxf(hi, t)
		if hi - lo > largo: largo = hi - lo; mejor = d
	var r := 0.0
	for v in vs:
		var q := tr * v - c
		r = maxf(r, (q - mejor * q.dot(mejor)).length())
	return [c, mejor, r, largo * 0.5]

func _correr() -> void:
	await get_tree().create_timer(4.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	await get_tree().create_timer(2.0).timeout
	var esq: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("vela_mayor"): sb = x as SoftBody3D
	var n := (b.find_children("vela_mayor", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	var g := esq.global_transform
	for nombre in ["mastil_v3", "botavara", "pico"]:
		var mi := b.find_children(nombre, "MeshInstance3D", true, false)[0] as MeshInstance3D
		var e := _eje(mi, esq)
		var c: Vector3 = e[0]; var d: Vector3 = e[1]; var r: float = e[2]; var media: float = e[3]
		var dentro := 0; var hondo := 0.0
		for k in n:
			var p := g.affine_inverse() * sb.get_point_transform(k)
			var t := (p - c).dot(d)
			if absf(t) > media: continue
			var rad := (p - c - d * t).length()
			if rad < r:
				dentro += 1
				hondo = maxf(hondo, r - rad)
		print("%-12s radio %.3f m, medio largo %.2f  ->  %d de %d puntos DENTRO, hasta %.3f m adentro"
			% [nombre, r, media, dentro, n, hondo])
	get_tree().quit()
