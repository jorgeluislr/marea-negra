extends Node

## Cómo LLEGA el barco a su escora, no cuánta tiene de media — eso ya lo mide `tools/escora.tscn`.
##
## Dos escenas, y en las dos se apaga el balance de la ola (`obediencia_escora` 0), porque lo que
## se busca es lo que hacen el viento y el timón y la ola mete ±3° que lo taparían:
##
## - **rachas de través**: el viento de costado CON sus rachas. Se lee cuánto pide el viento
##   (el objetivo, `_escora_de_navegacion()`), cuánto se tumba el casco de verdad y a qué
##   velocidad angular. Un casco con masa no puede seguir una racha de pocos segundos.
## - **meter la caña**: navegando derecho, timón a tope con la tecla y sin escora de viento. Se
##   lee la velocidad de giro a los 0,1 / 0,25 / 0,5 / 1 / 2 s: si a los 0,1 s ya está entera, el
##   barco no tiene inercia de guiñada y todo lo que cuelga de ella (la escora del giro) sale de
##   golpe.
##
##     godot --path . tools/escora_dinamica.tscn

const ASENTARSE := 8.0


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(7.0).timeout
	Oleaje.asentar()
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		print("no hay barco")
		get_tree().quit(1)
		return
	b.set("obediencia_escora", 0.0)
	print("\n─── escora dinámica ───  periodo_balance %.2f s"
		% float(b.call("periodo_balance")))
	await _rachas(b)
	await _cana(b)
	get_tree().quit(0)


func _rachas(b: Node3D) -> void:
	Viento.variacion_fuerza = 0.45
	Viento.bamboleo_dir = 0.12
	Viento.fuerza_base = 1.0
	Viento.direccion_base = Vector3(-1, 0, 0)
	await _esperar(b, ASENTARSE)
	var o_lo := INF
	var o_hi := -INF
	var e_lo := INF
	var e_hi := -INF
	var v_max := 0.0
	var prev := rad_to_deg(b.global_transform.basis.get_euler().z)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var t := 0.0
	while t < 30.0:
		await _paso(b)
		t += dt
		var o := rad_to_deg(float(b.call("_escora_de_navegacion")))
		var e := rad_to_deg(b.global_transform.basis.get_euler().z)
		o_lo = minf(o_lo, o)
		o_hi = maxf(o_hi, o)
		e_lo = minf(e_lo, e)
		e_hi = maxf(e_hi, e)
		v_max = maxf(v_max, absf(e - prev) / dt)
		prev = e
	print("rachas de través: objetivo %.2f..%.2f°  casco %.2f..%.2f° (pico a pico %.2f°)  "
		% [o_lo, o_hi, e_lo, e_hi, e_hi - e_lo]
		+ "balance máx %.2f °/s" % v_max)


func _cana(b: Node3D) -> void:
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	Viento.direccion_base = Vector3(-0.7, 0, -0.7)
	var brazo: float = b.get("brazo_velico")
	b.set("brazo_velico", 0.0)
	await _esperar(b, ASENTARSE)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var marcas := [0.1, 0.25, 0.5, 1.0, 2.0, 4.0]
	var lecturas: Array[String] = []
	var rumbo_prev := _rumbo(b)
	var e_prev := rad_to_deg(b.global_transform.basis.get_euler().z)
	var v_max := 0.0
	var e_pico := 0.0
	var t_pico := 0.0
	var vel: float = b.get("velocidad")
	_tecla(KEY_D, true)
	var t := 0.0
	var k := 0
	while t < 6.0:
		await _paso(b)
		t += dt
		var r := _rumbo(b)
		var w := rad_to_deg(wrapf(r - rumbo_prev, -PI, PI)) / dt
		rumbo_prev = r
		var e := rad_to_deg(b.global_transform.basis.get_euler().z)
		v_max = maxf(v_max, absf(e - e_prev) / dt)
		e_prev = e
		if absf(e) > absf(e_pico):
			e_pico = e
			t_pico = t
		if k < marcas.size() and t >= marcas[k]:
			lecturas.append("%.2fs %.1f°/s" % [marcas[k], absf(w)])
			k += 1
	_tecla(KEY_D, false)
	b.set("brazo_velico", brazo)
	print("meter la caña (a %.2f m/s): giro %s" % [vel, ", ".join(lecturas)])
	print("   escora del giro: pico %.2f° a los %.2f s, balance máx %.2f °/s"
		% [e_pico, t_pico, v_max])


func _rumbo(b: Node3D) -> float:
	var p := -b.global_transform.basis.z
	return atan2(p.x, p.z)


func _esperar(b: Node3D, s: float) -> void:
	var t := 0.0
	while t < s:
		await _paso(b)
		t += 1.0 / float(Engine.physics_ticks_per_second)


func _paso(b: Node3D) -> void:
	b.set("anclado", false)
	b.set("gobierno", true)
	await get_tree().physics_frame


func _tecla(k: int, pulsada: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = pulsada
	Input.parse_input_event(e)
