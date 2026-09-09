extends Node
## Barrido de parámetros del solver: para cada combinación mide a cuánto se queda el peor punto
## fijado de su anclaje (el "fleco") y el coste de física. Así se elige por número.
@export var malla := "foque"
@export var cuantos := 253

func _ready() -> void: _correr()

func _peor(esq: Skeleton3D, sb: SoftBody3D) -> float:
	var g := esq.global_transform
	var peor := 0.0
	for c in esq.get_children():
		var nm := (c as Node).name
		if not nm.begins_with("Ancla_" + malla + "_"): continue
		var k := int(nm.get_slice("_", 2))
		if k >= cuantos: continue
		peor = maxf(peor, (g.affine_inverse() * sb.get_point_transform(k)).distance_to((c as Node3D).position))
	return peor

func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	var esq: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with(malla): sb = x as SoftBody3D
	print("rigidez  amort  prec |  fleco   fisica")
	for rig in [0.5, 0.9, 1.0]:
		for amo in [0.01, 0.3]:
			for pre in [5, 10, 20]:
				sb.linear_stiffness = rig
				sb.damping_coefficient = amo
				sb.simulation_precision = pre
				for i in 100:
					await get_tree().physics_frame
				var peor := 0.0; var f := 0.0
				for i in 90:
					await get_tree().process_frame
					peor = maxf(peor, _peor(esq, sb))
					f += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
				print("  %.2f    %.2f   %2d  | %.3f m  %.3f ms" % [rig, amo, pre, peor, f / 90.0])
	get_tree().quit()
