extends Node

## Fotografía el HUD en una escena del juego: navegando, y en modo batalla recién disparada una
## banda, con dos zonas tocadas a mano para ver los tres colores de la silueta de daños.
##
##     godot --path . tools/foto_hud.tscn -- res://scenes/world/combate.tscn C:\ruta\fotos

var escena := "res://scenes/world/main_world.tscn"
var carpeta := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("res://"):
			escena = String(a)
		else:
			carpeta = String(a)
	if carpeta == "":
		carpeta = OS.get_user_data_dir()
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load(escena) as PackedScene).instantiate())
	await get_tree().create_timer(7.0).timeout
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		get_tree().quit(1)
		return
	b.set("anclado", false)
	await get_tree().create_timer(4.0).timeout
	var base := escena.get_file().get_basename()
	await _foto("hud_%s_navegando.png" % base)
	# La travesía a ×2 y ×4 con su tecla, y de vuelta a ×1.
	for veces in ["x2", "x4"]:
		await _tecla(KEY_T)
		await _foto("hud_%s_travesia_%s.png" % [base, veces])
	await _tecla(KEY_T)

	b.get("integridad")["estribor"] = 0.5
	b.get("integridad")["popa"] = 0.2
	await _tecla(KEY_B)
	var clic := InputEventMouseButton.new()
	clic.button_index = MOUSE_BUTTON_LEFT
	clic.pressed = true
	Input.parse_input_event(clic)
	await get_tree().create_timer(2.0).timeout
	await _foto("hud_%s_batalla.png" % base)
	get_tree().quit(0)


func _tecla(k: int) -> void:
	for p in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = p
		Input.parse_input_event(e)
		await get_tree().process_frame


func _foto(nombre: String) -> void:
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
	print("FOTO %s" % nombre)
