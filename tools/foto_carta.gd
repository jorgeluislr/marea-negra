extends Node
## Abre la carta en el mundo de verdad (con la tecla, como el jugador) y la fotografía.
##
##     godot --path . tools/foto_carta.tscn -- <png de salida> [pasos de rueda para alejar]

func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(get_tree().quit.bind(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(6.0).timeout
	for pulsada in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_M
		e.physical_keycode = KEY_M
		e.pressed = pulsada
		Input.parse_input_event(e)
		await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var carta := get_tree().get_first_node_in_group("carta")
	for k in int(args[1]) if args.size() > 1 else 0:
		for pulsada in [true, false]:
			var r := InputEventMouseButton.new()
			r.button_index = MOUSE_BUTTON_WHEEL_DOWN
			r.pressed = pulsada
			r.position = (carta.call("interior") as Rect2).get_center()
			r.global_position = r.position
			Input.parse_input_event(r)
		await get_tree().process_frame
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(args[0] if not args.is_empty() else "user://carta.png")
	get_tree().quit()
