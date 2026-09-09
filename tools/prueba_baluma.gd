extends Node
## Mide el borde libre (baluma) de la mayor: su estiramiento y su suavidad (cuánto se desvía cada
## vértice del borde de una curva suave por sus vecinos). Para distinguir estiramiento de pliegue.
func _ready() -> void: _correr()
func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	Viento.fuerza = 0.0
	var esq: Skeleton3D = b.find_children("*","Skeleton3D",true,false)[0]
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("vela_mayor"): sb = x as SoftBody3D
	var arr := sb.mesh.surface_get_arrays(0)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var n: int = arr[Mesh.ARRAY_VERTEX].size()
	# aristas de borde (una sola cara) y grado de cada vértice en el borde
	var cuenta := {}
	for t in range(0, idx.size(), 3):
		for e in [[idx[t],idx[t+1]],[idx[t+1],idx[t+2]],[idx[t+2],idx[t]]]:
			var a: int = e[0]; var c: int = e[1]
			var key := "%d_%d" % [min(a,c), max(a,c)]
			cuenta[key] = int(cuenta.get(key,0)) + 1
	var borde_aristas := []
	var vec_borde := {}
	for key in cuenta:
		if cuenta[key] == 1:
			var pr := (key as String).split("_")
			var a := int(pr[0]); var c := int(pr[1])
			borde_aristas.append([a,c])
			if not vec_borde.has(a): vec_borde[a]=[]
			if not vec_borde.has(c): vec_borde[c]=[]
			vec_borde[a].append(c); vec_borde[c].append(a)
	await get_tree().create_timer(3.0).timeout
	var rest := PackedVector3Array(); rest.resize(n)
	for k in n: rest[k] = sb.get_point_transform(k)
	Viento.direccion = Vector3(1,0,0.5).normalized(); Viento.fuerza = 1.3
	await get_tree().create_timer(8.0).timeout
	var now := PackedVector3Array(); now.resize(n)
	for k in n: now[k] = sb.get_point_transform(k)
	# estiramiento de las aristas de borde
	var est_max := 0.0; var est_sum := 0.0
	for e in borde_aristas:
		var lr := (rest[e[0]]-rest[e[1]]).length(); var ld := (now[e[0]]-now[e[1]]).length()
		var est := (ld-lr)/maxf(lr,0.001); est_max = maxf(est_max, est); est_sum += est
	# suavidad: para vértices de borde con 2 vecinos de borde, desviación del punto medio
	var jag_max := 0.0; var jag_sum := 0.0; var jn := 0
	for v in vec_borde:
		if vec_borde[v].size() == 2:
			var m := (now[vec_borde[v][0]] + now[vec_borde[v][1]]) * 0.5
			var d := (now[v] - m).length()
			jag_max = maxf(jag_max, d); jag_sum += d; jn += 1
	print("baluma/borde: %d aristas de borde, estiramiento medio %+.1f%% max %+.1f%%" % [borde_aristas.size(), est_sum/borde_aristas.size()*100, est_max*100])
	print("suavidad del borde: desviacion media %.3f m, peor %.3f m (%d vertices)" % [jag_sum/maxf(jn,1), jag_max, jn])
	get_tree().quit()
