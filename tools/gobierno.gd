extends Node

## Cómo gobierna el barco: si el timón hace algo sin arrancada, cuánto gira según la velocidad, si
## se queda sin gobierno de proa al viento y si ciando el timón actúa al revés.
##
## La física es la del timón de verdad: **no mueve el barco, desvía el agua que pasa por él**. Sin
## arrancada no pasa agua y no hay gobierno; a poca velocidad, poco; y yendo hacia atrás el agua lo
## ataca por la otra cara, así que la caña obra al revés. De ahí sale lo que hace un velero cuando
## se queda de proa al viento: se para, empieza a garrear hacia atrás y se sale metiendo la caña al
## contrario.
##
##     godot --path . tools/gobierno.tscn
##
## Con ventana y con las TECLAS, no escribiendo `orden_timon`: el controlador del jugador lo
## reescribe desde el teclado en cada paso de física y un valor puesto a mano no dura ni un frame.

const MEDIR := 8.0


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	await get_tree().create_timer(6.0).timeout
	Oleaje.asentar()
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		get_tree().quit(1)
		return
	print("\n─── gobierno ───")
	print("velocidad_max %.1f m/s, velocidad_giro %.2f rad/s -> radio de giro %.1f m, cía %.2f"
		% [b.get("velocidad_max"), b.get("velocidad_giro"),
			float(b.get("velocidad_max")) / maxf(float(b.get("velocidad_giro")), 0.01),
			b.get("cia_en_el_ojo")])
	print("%-34s %9s %9s %11s" % ["situación", "vel m/s", "giro °/s", "veredicto"])

	# 1. PARADO: anclado no vale, porque anclado no gira por definición. Se arrían las velas y se
	#    espera a que pare sola, que es como se queda un barco sin arrancada.
	b.call("set_vela_delantera", false)
	b.call("set_vela_trasera", false)
	await _esperar(6.0)
	# A palo seco y con el viento de proa el barco no queda quieto del todo: garrea hacia atrás por
	# lo que el viento le hace a los palos, y entonces gobierna un poco, invertido. Lo que se
	# comprueba es que el giro va con la ARRANCADA, no que sea cero pase lo que pase.
	await _caso(b, "a palo seco, timón a estribor", KEY_D, "casi parado")

	# 2. NAVEGANDO a un largo, con todo el trapo.
	b.call("set_vela_delantera", true)
	b.call("set_vela_trasera", true)
	_rumbo(b, 90.0)
	await _esperar(10.0)
	await _caso(b, "navegando a un largo", KEY_D, "gira")

	# 3. DE PROA AL VIENTO: la zona muerta. Aquí no hay arrancada, así que no debería gobernar;
	#    y el viento en la arboladura debería empujarla hacia atrás.
	_rumbo(b, 0.0)
	await _esperar(10.0)
	# Aquí lo correcto NO es que no gire: es que gire AL REVÉS, porque está ciando. Es la maniobra
	# con la que un velero sale del ojo del viento.
	await _caso(b, "de proa al viento, timón a estribor", KEY_D, "cía y gira al revés")

	# 3 bis. LA DERIVA EN LA CURVA. Un barco no pivota: conserva su movimiento y la proa se le va
	#        adelantando, así que mientras vira hay un ángulo entre hacia dónde MIRA y hacia dónde
	#        VA, y la popa barre hacia fuera. Si ese ángulo es 0 el casco gira como una peonza y se
	#        ve como si el timón lo empujara de lado.
	b.call("set_vela_delantera", true)
	b.call("set_vela_trasera", true)
	_rumbo(b, 90.0)
	await _esperar(10.0)
	await _deriva(b)

	# 4. CIANDO: con arrancada hacia atrás la caña obra al revés.
	_rumbo(b, 0.0)
	await _esperar(6.0)
	print("%-34s %9.2f %9s %11s" % ["  (velocidad de proa al viento)",
		float(b.get("velocidad")), "-", "negativa = cía"])
	get_tree().quit(0)


## Mete el timón a una banda navegando y mide el ángulo entre la proa y el movimiento real.
func _deriva(b: Node3D) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_D
	ev.physical_keycode = KEY_D
	ev.pressed = true
	Input.parse_input_event(ev)
	var peor := 0.0
	var suma := 0.0
	var n := 0
	var t := 0.0
	while t < 6.0:
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		var v: Vector3 = b.get("velocity")
		var vh := Vector2(v.x, v.z)
		if vh.length() < 0.2:
			continue
		var proa := -b.global_transform.basis.z
		var ph := Vector2(proa.x, proa.z).normalized()
		var ang: float = absf(rad_to_deg(ph.angle_to(vh.normalized())))
		peor = maxf(peor, ang)
		suma += ang
		n += 1
	ev.pressed = false
	Input.parse_input_event(ev)
	print("%-34s %9s %9s %11s" % ["virando: proa contra movimiento",
		"%.1f°" % (suma / float(maxi(n, 1))), "%.1f° máx" % peor, "0 = pivota"])
	await _esperar(1.0)


## Pone la proa a `grados` del viento (0 = de cara).
func _rumbo(b: Node3D, grados: float) -> void:
	var d := Vector2(Viento.direccion_base.x, Viento.direccion_base.z).normalized()
	var dir := -d.rotated(deg_to_rad(grados))
	b.set("global_rotation", Vector3(0.0, atan2(-dir.x, -dir.y), 0.0))


func _esperar(seg: float) -> void:
	var t := 0.0
	while t < seg:
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)


func _caso(b: Node3D, nombre: String, tecla: int, espera: String) -> void:
	var ev := InputEventKey.new()
	ev.keycode = tecla
	ev.physical_keycode = tecla
	ev.pressed = true
	Input.parse_input_event(ev)
	# El giro se ACUMULA paso a paso, no se saca de la diferencia entre el rumbo final y el
	# inicial: en ocho segundos el barco puede dar más de media vuelta, y entonces la diferencia
	# envuelve y sale un número pequeño o de signo contrario. Con 25 °/s daba −2,25.
	var previo: float = b.global_rotation.y
	var giro_total := 0.0
	var vel := 0.0
	var n := 0
	var t := 0.0
	while t < MEDIR:
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		giro_total += wrapf(b.global_rotation.y - previo, -PI, PI)
		previo = b.global_rotation.y
		vel += float(b.get("velocidad"))
		n += 1
	ev.pressed = false
	Input.parse_input_event(ev)
	var giro := rad_to_deg(giro_total) / MEDIR
	print("%-34s %9.2f %9.2f %11s" % [nombre, vel / float(maxi(n, 1)), giro, espera])
	await _esperar(1.0)
