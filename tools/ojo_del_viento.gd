extends Node

## Qué hace el barco PARADO de proa al viento con la caña metida: si cía, cuánto tarda, y si sale
## de la zona muerta por la banda que pide el timón. Es el bloqueo "se queda mirando al viento y no
## gira hacia ningún lado".
##
##     godot --path . tools/ojo_del_viento.tscn
##
## Se parte de PARADO (velocidad 0, sin guiñada) y con todo el trapo, que es como queda el barco
## cuando entra en el ojo sin arrancada. Con las TECLAS: el mando reescribe `orden_timon` cada paso.

const MEDIR := 30.0


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func():
		push_error("se acabo el tiempo"); get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	await get_tree().create_timer(6.0).timeout
	Oleaje.asentar()
	var b := UtilesPruebas.barco(get_tree())
	if b == null:
		get_tree().quit(1)
		return
	await UtilesPruebas.al_timon(get_tree())
	b.call("set_vela_delantera", true)
	b.call("set_vela_trasera", true)
	print("\n─── ojo del viento (%s) ───" % b.get("nombre"))
	print("v_max %.1f  a %.2f  giro %.2f  cía %.2f  muerto %.0f°  time_scale %.1f  física %d Hz"
		% [b.get("velocidad_max"), b.get("aceleracion"), b.get("velocidad_giro"),
			b.get("cia_en_el_ojo"), b.get("angulo_muerto"), Engine.time_scale,
			Engine.physics_ticks_per_second])
	for caso in [[KEY_D, "estribor"], [KEY_A, "babor"], [0, "sin caña"]]:
		await _caso(b, caso[0], caso[1])
	get_tree().quit(0)


func _caso(b: Node3D, tecla: int, nombre: String) -> void:
	var dm := Vector2(Viento.direccion_base.x, Viento.direccion_base.z).normalized()
	b.global_rotation = Vector3(0.0, atan2(dm.x, dm.y), 0.0)
	b.set("velocidad", 0.0)
	b.set("velocity", Vector3.ZERO)
	b.set("_guinada", 0.0)
	var ev := InputEventKey.new()
	ev.keycode = tecla
	ev.physical_keycode = tecla
	ev.pressed = true
	if tecla != 0:
		Input.parse_input_event(ev)
	print("\ncaña a %s" % nombre)
	print("%6s %8s %10s %9s %8s %8s" % ["t s", "vel m/s", "al viento°", "giro °/s", "f_viento", "timón"])
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var previo: float = b.global_rotation.y
	var acum := 0.0
	var t := 0.0
	var siguiente := 0.0
	var salida := -1.0
	var al_viento := 0.0
	while t < MEDIR:
		await get_tree().physics_frame
		t += dt
		var paso := wrapf(b.global_rotation.y - previo, -PI, PI)
		previo = b.global_rotation.y
		acum += paso
		# Ángulo con signo de la proa respecto a de donde viene el viento (+ = cae a babor).
		al_viento = rad_to_deg(acum)
		if salida < 0.0 and float(b.call("factor_viento")) > 0.05:
			salida = t
		if t >= siguiente:
			siguiente += 2.0
			print("%6.1f %8.3f %10.1f %9.2f %8.3f %8.2f" % [t, float(b.get("velocidad")), al_viento,
				rad_to_deg(paso / dt), float(b.call("factor_viento")), float(b.get("orden_timon"))])
	if tecla != 0:
		ev.pressed = false
		Input.parse_input_event(ev)
	print("-> %s: %s, al viento %.1f°" % [nombre,
		"sale de la zona muerta a los %.1f s" % salida if salida >= 0.0 else "NO SALE en %.0f s" % MEDIR,
		al_viento])
