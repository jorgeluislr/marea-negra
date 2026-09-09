extends Node
## La vela de la lancha por el camino del shader: cambia a ella con TAB, la arria con S y la
## vuelve a izar, fotografiando cada paso. Es la rama VelaShader del refactor.
@export var carpeta := ""

func _ready() -> void: _correr()

func _tecla(k: int) -> void:
	for p in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k; e.physical_keycode = k; e.pressed = p
		Input.parse_input_event(e)
		await get_tree().process_frame

func _foto(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(n))

func _correr() -> void:
	await get_tree().create_timer(2.0).timeout
	await _tecla(KEY_TAB)                       # balandra -> lancha
	await get_tree().create_timer(2.5).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0]
	b.set("anclado", true)
	await get_tree().create_timer(1.5).timeout
	for v in b.get_children():
		if v.has_method("izar"):
			var apa: Variant = v.get("aparejo")
			print("%s en %s: izada=%s arriado=%.3f" % [v.name, b.name, v.esta_izada(),
				apa.arriado_medido() if apa != null else -1.0])
	await _foto("lancha_1_izada.png")
	await _tecla(KEY_S)
	await get_tree().create_timer(4.0).timeout
	for v in b.get_children():
		if v.has_method("izar"):
			var apa: Variant = v.get("aparejo")
			print("tras S -> %s: izada=%s arriado=%.3f" % [v.name, v.esta_izada(),
				apa.arriado_medido() if apa != null else -1.0])
	await _foto("lancha_2_arriada.png")
	await _tecla(KEY_S)
	await get_tree().create_timer(4.0).timeout
	await _foto("lancha_3_izada_otra_vez.png")
	get_tree().quit()
