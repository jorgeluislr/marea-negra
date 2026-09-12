extends Node

## ¿A qué ritmo cambia CADA cosa? El desfase de los anclajes escala con los FPS aunque el barco
## y las anclas se muevan en la física, así que hay que ver, paso a paso, quién se mueve cuándo.
##
## Se fijan 30 fps con la física a 120 —cuatro pasos por frame— y se anotan, en ocho pasos
## seguidos, la posición del BARCO, la del NODO de anclaje y la del PUNTO del `SoftBody`. Lo que
## se cuenta es cuántos VALORES DISTINTOS toma cada uno: si el punto solo cambia una vez cada
## cuatro pasos, es que `get_point_transform()` lee un buffer que se refresca por frame de
## render, y entonces el estirón es de sincronía, no de física.

func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	var barco := esc.instantiate() as Node3D
	add_child(barco)
	Viento.direccion_base = Vector3(1, 0, 0)
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	barco.set("anclado", false)
	await get_tree().create_timer(8.0).timeout

	var tela: Node = null
	for h in barco.get_children():
		if h.has_method("datos_depuracion") and str(h.get("nombre_malla")) == "bandera":
			tela = h
	var d: Dictionary = tela.datos_depuracion()
	var cuerpo: SoftBody3D = d["cuerpo"]
	var anclas: Array[Node3D] = d["anclas"]
	var fijo: PackedByteArray = d["fijo"]
	var k := 0
	for i in fijo.size():
		if fijo[i] == 1:
			k = i
			break

	Engine.physics_ticks_per_second = 120
	Engine.max_fps = 30
	await get_tree().create_timer(2.0).timeout

	print("\n8 pasos de fisica seguidos con 30 fps y la fisica a 120 (4 pasos por frame).")
	print("%-6s %-12s %-12s %-12s %s" % ["paso", "barco", "ancla", "punto", "punto-ancla"])
	var pb := []
	var pa := []
	var pp := []
	var pq := []
	for i in 8:
		await get_tree().physics_frame
		var b: Vector3 = (barco as Node3D).global_position
		var a: Vector3 = anclas[k].global_position
		var p: Vector3 = cuerpo.get_point_transform(k)
		var q: Vector3 = PhysicsServer3D.soft_body_get_point_global_position(cuerpo.get_physics_rid(), k)
		pq.append(q)
		pb.append(b); pa.append(a); pp.append(p)
		print("%-6d %-12.4f %-12.4f %-12.4f %6.1f mm   servidor %6.1f mm" % [i, b.x, a.x, p.x, (p - a).length() * 1000.0, (q - a).length() * 1000.0])
	print("valores distintos en 8 pasos -> barco %d, ancla %d, punto %d"
		% [_distintos(pb), _distintos(pa), _distintos(pp)])
	print("y el punto leido del SERVIDOR de fisica cambia %d veces" % _distintos(pq))
	Engine.max_fps = 0
	get_tree().quit()


func _distintos(l: Array) -> int:
	var n := 1
	for i in range(1, l.size()):
		if not (l[i] as Vector3).is_equal_approx(l[i - 1]):
			n += 1
	return n
