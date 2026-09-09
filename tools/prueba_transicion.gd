extends Node
## Encuentra los vértices que saltan durante el izado/arriado del foque. Mide el desplazamiento
## frame-a-frame de cada vértice (en ejes del barco) y reporta el máximo y en qué fase ocurre.
func _ready() -> void: _correr()

func _pos(b: Node3D, esq: Skeleton3D, sb: SoftBody3D, n: int) -> PackedVector3Array:
	var g := b.global_transform.affine_inverse()
	var r := PackedVector3Array(); r.resize(n)
	for k in n: r[k] = g * sb.get_point_transform(k)
	return r

func _fase(b: Node3D, esq: Skeleton3D, sb: SoftBody3D, n: int, etiqueta: String, frames: int) -> void:
	var prev := _pos(b, esq, sb, n)
	var pico := 0.0; var kpico := -1; var fpico := -1
	var suma := 0.0
	for f in frames:
		await get_tree().physics_frame
		var cur := _pos(b, esq, sb, n)
		var mx := 0.0; var km := -1
		for k in n:
			var d := (cur[k] - prev[k]).length()
			if d > mx: mx = d; km = k
		suma += mx
		if mx > pico: pico = mx; kpico = km; fpico = f
		prev = cur
	print("%-10s salto max %.3f m (vertice %d, frame %d) | salto medio por frame %.4f m" % [etiqueta, pico, kpico, fpico, suma/frames])

func _correr() -> void:
	await get_tree().create_timer(4.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	var esq: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("foque"): sb = x as SoftBody3D
	var n := 253
	await get_tree().create_timer(2.0).timeout
	await _fase(b, esq, sb, n, "izada_quieta", 60)
	b.set("vela_delantera", false); b.emit_signal("vela_delantera_cambiada", false)
	await _fase(b, esq, sb, n, "ARRIANDO", 120)
	await get_tree().create_timer(3.0).timeout
	b.set("vela_delantera", true); b.emit_signal("vela_delantera_cambiada", true)
	await _fase(b, esq, sb, n, "IZANDO", 120)
	get_tree().quit()
