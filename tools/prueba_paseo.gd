extends Node
## Pulsa F, comprueba que el personaje aparece en cubierta con su cámara, anda, y fotografía
## la vista en primera persona.
@export var carpeta := ""

func _ready() -> void: _correr()

func _tecla(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k; e.physical_keycode = k; e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var u := InputEventKey.new()
	u.keycode = k; u.physical_keycode = k; u.pressed = false
	Input.parse_input_event(u)

func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
	print("FOTO %s" % nombre)

func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	await get_tree().create_timer(1.0).timeout
	print("antes: camara actual = %s | gobierno = %s" % [get_viewport().get_camera_3d().name, b.get("gobierno")])
	await _tecla(KEY_F)
	await get_tree().create_timer(1.5).timeout
	var jug := b.find_child("Player", false, false) as CharacterBody3D
	if jug == null:
		print("NO APARECIO EL PERSONAJE"); get_tree().quit(1); return
	print("andando: camara = %s | gobierno = %s | y local %.3f | en el suelo %s"
		% [get_viewport().get_camera_3d().name, b.get("gobierno"), jug.position.y, jug.is_on_floor()])
	await _foto("paseo_timon.png")
	# camina hacia proa un rato, con la W de verdad pulsada
	var w := InputEventKey.new()
	w.keycode = KEY_W; w.physical_keycode = KEY_W; w.pressed = true
	Input.parse_input_event(w)
	var z0 := jug.position.z
	for i in 150:
		await get_tree().physics_frame
	var wu := InputEventKey.new()
	wu.keycode = KEY_W; wu.physical_keycode = KEY_W; wu.pressed = false
	Input.parse_input_event(wu)
	await get_tree().physics_frame
	print("  la W movio %.2f m" % (jug.position.z - z0))
	print("tras andar a proa: %v  en el suelo %s" % [jug.position, jug.is_on_floor()])
	await _foto("paseo_proa.png")
	# salta a la borda
	var a := InputEventKey.new()
	a.keycode = KEY_A; a.physical_keycode = KEY_A; a.pressed = true
	Input.parse_input_event(a)
	for i in 200:
		if i == 20 or i == 90:
			jug.velocity.y = 4.5
		await get_tree().physics_frame
	var au := InputEventKey.new()
	au.keycode = KEY_A; au.physical_keycode = KEY_A; au.pressed = false
	Input.parse_input_event(au)
	print("tras saltar a babor: %v  en el suelo %s" % [jug.position, jug.is_on_floor()])
	await _foto("paseo_borda.png")
	await _tecla(KEY_F)
	await get_tree().create_timer(1.0).timeout
	print("de vuelta: camara = %s | gobierno = %s | personaje = %s"
		% [get_viewport().get_camera_3d().name, b.get("gobierno"), b.find_child("Player", false, false)])
	get_tree().quit()
