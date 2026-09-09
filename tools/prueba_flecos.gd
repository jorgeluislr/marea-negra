extends Node
## Los "flecos": mientras se recoge o se iza, cada punto está fijado a su nodo de anclaje, así
## que si se queda atrás es que el solver no lo sigue. Mide la distancia máxima punto-anclaje
## durante toda la maniobra, que es exactamente el fleco que se ve.
@export var malla := "foque"
@export var cuantos := 253

func _ready() -> void: _correr()

func _peor(b: Node3D, esq: Skeleton3D, sb: SoftBody3D) -> float:
	var g := esq.global_transform
	var peor := 0.0
	for c in esq.get_children():
		var nm := (c as Node).name
		if not nm.begins_with("Ancla_" + malla + "_"): continue
		var k := int(nm.get_slice("_", 2))
		if k >= cuantos: continue
		# SOLO los que están fijados: los libres están lejos de su reposo por definición.
		if not sb.is_point_pinned(k): continue
		var p := g.affine_inverse() * sb.get_point_transform(k)
		peor = maxf(peor, p.distance_to((c as Node3D).position))
	return peor

func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	var esq: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with(malla): sb = x as SoftBody3D
	var prop := "vela_delantera" if malla == "foque" else "vela_trasera"
	var sig := "vela_delantera_cambiada" if malla == "foque" else "vela_trasera_cambiada"
	print("%s: rigidez %.2f amortiguacion %.3f arrastre %.2f precision %d"
		% [malla, sb.linear_stiffness, sb.damping_coefficient, sb.drag_coefficient, sb.simulation_precision])
	await get_tree().create_timer(1.0).timeout
	var fij := 0
	for k in cuantos:
		if sb.is_point_pinned(k): fij += 1
	print("  izada quieta: %d puntos fijados, el peor a %.3f m de su anclaje" % [fij, _peor(b, esq, sb)])
	b.set(prop, false); b.emit_signal(sig, false)
	var peor := 0.0
	for i in 480:
		await get_tree().physics_frame
		peor = maxf(peor, _peor(b, esq, sb))
	var fij2 := 0
	for k in cuantos:
		if sb.is_point_pinned(k): fij2 += 1
	print("  RECOGIENDO: %d fijados, peor fleco %.3f m" % [fij2, peor])
	b.set(prop, true); b.emit_signal(sig, true)
	peor = 0.0
	for i in 480:
		await get_tree().physics_frame
		peor = maxf(peor, _peor(b, esq, sb))
	print("  IZANDO: peor fleco %.3f m" % peor)
	get_tree().quit()
