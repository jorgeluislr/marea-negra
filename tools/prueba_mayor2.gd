extends Node
## ¿Por qué la mayor hace formas raras? Compara cada punto del SoftBody con su posición según
## la piel del modelo, y comprueba que los pesos de cada vértice sumen 1 (si suman menos, el
## destino sale escalado hacia el origen del esqueleto y el paño se va donde no debe).
func _ready() -> void: _correr()

func _analizar(b: Node3D, etiqueta: String) -> void:
	var esq: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
	var mi := b.find_children("vela_mayor", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("vela_mayor"): sb = x as SoftBody3D
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var hu: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var pe: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var tr := Transform3D()
	var x2: Node = mi
	while x2 != null and x2 != esq:
		if x2 is Node3D: tr = (x2 as Node3D).transform * tr
		x2 = x2.get_parent()
	var n := esq.get_bone_count()
	var mats: Array[Transform3D] = []
	mats.resize(n)
	for i in n: mats[i] = esq.get_bone_global_pose(i) * esq.get_bone_global_rest(i).affine_inverse()
	var g := esq.global_transform
	var err_max := 0.0; var err_med := 0.0
	var suma_min := INF; var suma_max := -INF; var malos := 0
	for k in vs.size():
		var s := 0.0
		var dest := Vector3.ZERO
		for j in 4:
			var w: float = pe[k * 4 + j]
			if w <= 0.0: continue
			dest += (mats[hu[k * 4 + j]] * (tr * vs[k])) * w
			s += w
		suma_min = minf(suma_min, s); suma_max = maxf(suma_max, s)
		if s < 0.999: malos += 1
		var real := g.affine_inverse() * sb.get_point_transform(k)
		var e := (real - dest).length()
		err_max = maxf(err_max, e); err_med += e
	print("%-10s pesos suman [%.4f, %.4f]  vertices con suma<1: %d | error contra la piel: medio %.3f m, max %.3f m"
		% [etiqueta, suma_min, suma_max, malos, err_med / vs.size(), err_max])

func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	await get_tree().create_timer(1.0).timeout
	_analizar(b, "izada")
	b.set("vela_trasera", false); b.emit_signal("vela_trasera_cambiada", false)
	for t in [1.0, 3.0, 8.0]:
		await get_tree().create_timer(t if t == 1.0 else t - 1.0).timeout
		_analizar(b, "arriando%d" % int(t))
	get_tree().quit()
