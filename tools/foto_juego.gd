extends Node

## Fotografía el juego con SU cámara, la orbital, en varias posiciones de órbita y zoom.
##
## Las demás herramientas colocan una cámara propia donde interesa medir, y eso tiene un
## problema: enseñan lo que el que mide quiere mirar, no lo que el jugador ve. Cuando el usuario
## describe algo raro —una mancha, una sombra, un borde— hay que reproducir SU vista, y su vista
## es la cámara del juego.
##
## Gira alrededor del barco y hace una toma por posición, con el barco navegando y escorado.
##
##     godot --path . tools/foto_juego.tscn -- C:\ruta\donde\dejar\las\fotos

@export var carpeta := ""
## Ángulos de órbita, en grados, y distancia de zoom.
@export var angulos: Array[float] = [0.0, 60.0, 130.0, 200.0, 280.0]


func _ready() -> void:
	var viento := 1.0
	for a in OS.get_cmdline_user_args():
		if String(a).is_valid_float():
			viento = String(a).to_float()
		else:
			carpeta = String(a)
	if carpeta == "":
		carpeta = OS.get_user_data_dir()
	get_tree().create_timer(180.0).timeout.connect(func(): get_tree().quit(1))

	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.direccion_base = Vector3(1, 0, 0.3)
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = viento
	await get_tree().create_timer(7.0).timeout
	Oleaje.asentar()
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b != null:
		b.set("anclado", false)

	# Con el RECORTE del agua y sin él, para poder decir si una mancha en el agua la pone el
	# recorte o es otra cosa —una sombra, un reflejo—. Es la misma técnica de antes, cuando lo que
	# se encendía y apagaba era la tapa de sentina.
	for con_tapa in [true, false]:
		if b != null:
			b.set("recorta_el_agua", con_tapa)
		await _tanda(con_tapa)
	get_tree().quit(0)


func _tanda(con_tapa: bool) -> void:
	for i in angulos.size():
		# Se gobierna la cámara como el jugador: botón derecho y arrastrar.
		var giro := deg_to_rad(angulos[i] if i == 0 else angulos[i] - angulos[i - 1])
		_arrastrar(giro / 0.007)
		for j in 90:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var nombre := "juego_%03d_%s.png" % [int(angulos[i]),
			"recorte" if con_tapa else "sinrecorte"]
		get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
		print("FOTO %s" % nombre)


## Clic derecho y arrastre horizontal de `px` píxeles, que es como se orbita en el juego.
func _arrastrar(px: float) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_RIGHT
	b.pressed = true
	Input.parse_input_event(b)
	var m := InputEventMouseMotion.new()
	m.relative = Vector2(px, 0.0)
	Input.parse_input_event(m)
	b.pressed = false
	Input.parse_input_event(b)
