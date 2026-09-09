extends Node
## Cambia de barco con TAB y fotografia cada uno. Sirve para comprobar que TelaShader sigue
## animando la vela de la lancha ahora que se le dice que malla anima en vez de escanearlas.
@export var carpeta := ""

func _ready() -> void: _correr()

func _tab() -> void:
	for p in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_TAB; e.physical_keycode = KEY_TAB; e.pressed = p
		Input.parse_input_event(e)
		await get_tree().process_frame

func _correr() -> void:
	await get_tree().create_timer(2.0).timeout
	for nombre in ["balandra", "lancha", "barca", "goleta"]:
		var b := get_tree().get_nodes_in_group("barco_activo")
		if not b.is_empty():
			b[0].set("anclado", true)
		await get_tree().create_timer(2.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(carpeta.path_join("barco_%s.png" % nombre))
		print("FOTO %s (barco en escena: %s)" % [nombre, b[0].name if not b.is_empty() else "?"])
		await _tab()
	get_tree().quit()
