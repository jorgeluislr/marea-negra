extends Node
## ¿Cambian de verdad los controles al cambiar de cámara? Comprueba que en modo paseo las
## teclas del barco (W vela, S vela, ESPACIO ancla, A/D timón) no le hacen nada, y que al
## volver a navegar sí.
func _ready() -> void: _correr()

func _pulsar(k: int) -> void:
	var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var u := InputEventKey.new(); u.keycode = k; u.physical_keycode = k; u.pressed = false
	Input.parse_input_event(u)
	await get_tree().process_frame

func _mantener(k: int, frames: int) -> void:
	var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = true
	Input.parse_input_event(e)
	for i in frames: await get_tree().physics_frame
	var u := InputEventKey.new(); u.keycode = k; u.physical_keycode = k; u.pressed = false
	Input.parse_input_event(u)
	await get_tree().physics_frame

func _estado(b: Node3D) -> Array:
	return [b.get("vela_delantera"), b.get("vela_trasera"), b.get("anclado"), snappedf(b.rotation.y, 0.0001)]

func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	print("navegando, antes: velas=%s/%s ancla=%s yaw=%.4f" % _estado(b))
	await _pulsar(KEY_W)
	await _mantener(KEY_A, 60)
	print("navegando, tras W y A: velas=%s/%s ancla=%s yaw=%.4f  <- deben haber cambiado" % _estado(b))
	await _pulsar(KEY_W)   # deja la vela como estaba
	await _pulsar(KEY_F)   # a cubierta
	await get_tree().create_timer(1.5).timeout
	var e0 := _estado(b)
	print("en cubierta: gobierno=%s  velas=%s/%s ancla=%s yaw=%.4f" % [b.get("gobierno"), e0[0], e0[1], e0[2], e0[3]])
	await _pulsar(KEY_W)
	await _pulsar(KEY_S)
	await _pulsar(KEY_SPACE)
	await _mantener(KEY_A, 60)
	var e1 := _estado(b)
	print("en cubierta, tras W S ESPACIO y A: velas=%s/%s ancla=%s yaw=%.4f" % e1)
	var igual: bool = e0[0] == e1[0] and e0[1] == e1[1] and e0[2] == e1[2] and absf(float(e0[3]) - float(e1[3])) < 0.0002
	print("  el barco NO reaccionó: %s" % igual)
	# y el personaje sí se mueve
	var jug := b.find_child("Player", false, false) as CharacterBody3D
	var p0: Vector3 = jug.position
	await _mantener(KEY_W, 60)
	print("  el personaje se movió %.2f m" % (jug.position - p0).length())
	await _pulsar(KEY_F)
	await get_tree().create_timer(1.0).timeout
	var e2 := _estado(b)
	await _pulsar(KEY_W)
	var e3 := _estado(b)
	print("de vuelta al timón: la W vuelve a mover la vela: %s -> %s" % [e2[0], e3[0]])
	# ¿y TAB mientras paseas?
	await _pulsar(KEY_F)
	await get_tree().create_timer(1.0).timeout
	await _pulsar(KEY_TAB)
	await get_tree().create_timer(1.5).timeout
	var g := get_tree().get_nodes_in_group("barco_activo")
	print("TAB en cubierta: barco activo = %s | personaje = %s | camara = %s"
		% [(g[0] as Node).name if not g.is_empty() else "NINGUNO",
		   (g[0] as Node).find_child("Player", false, false) if not g.is_empty() else null,
		   get_viewport().get_camera_3d().name])
	get_tree().quit()
