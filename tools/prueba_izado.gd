extends Node
## Ciclo completo de izado con las teclas del juego, tras pasar el izado y el trimado de los
## nodos `control_*` sueltos a metodos de la vela (Aparejo).
##
## Comprueba lo que se veria en pantalla: que al cerrar la vela la driza recorre su camino, el
## pano se RECOGE (y con ello deja de afectarle el viento), y al abrirla vuelve a desplegarse.
@export var carpeta := ""

func _ready() -> void: _correr()

func _tecla(k: int) -> void:
	for p in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k; e.physical_keycode = k; e.pressed = p
		Input.parse_input_event(e)
		await get_tree().process_frame

func _estado(barco: Node) -> String:
	var s := ""
	for v in barco.get_children():
		if not v.has_method("izar"):
			continue
		var apa: Variant = v.get("aparejo")
		var arr: float = apa.arriado_medido() if apa != null else -1.0
		var dd: Dictionary = v.datos_depuracion() if v.has_method("datos_depuracion") else {}
		s += "  %-18s izada=%-5s arriado=%.3f  recogiendo=%s\n" % [
			v.name, v.esta_izada(), arr, dd.get("recogiendo", "-")]
	return s

func _foto(nombre: String) -> void:
	if carpeta == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))

func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0]
	b.set("anclado", true)
	await get_tree().create_timer(1.0).timeout
	print("--- de salida (las dos izadas) ---\n%s" % _estado(b))
	await _foto("izado_1_izadas.png")

	await _tecla(KEY_S)   # cierra la vela de POPA: la mayor
	await get_tree().create_timer(6.0).timeout
	print("--- tras S (mayor arriada) ---\n%s" % _estado(b))
	await _foto("izado_2_mayor_arriada.png")

	await _tecla(KEY_W)   # cierra la de PROA: el foque
	await get_tree().create_timer(6.0).timeout
	print("--- tras W (las dos arriadas) ---\n%s" % _estado(b))
	await _foto("izado_3_ambas_arriadas.png")

	await _tecla(KEY_S)
	await _tecla(KEY_W)
	await get_tree().create_timer(7.0).timeout
	print("--- tras S y W (izadas otra vez) ---\n%s" % _estado(b))
	await _foto("izado_4_izadas_otra_vez.png")
	get_tree().quit()
