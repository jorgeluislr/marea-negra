extends Node
## Fotos del relieve en sitios reales, para comparar el relieve sintético con el de los mapas de
## altura y las escalas verticales entre sí.
##
##     godot --path . --max-fps 150 --windowed --resolution 1600x900 tools/foto_relieve.tscn -- <carpeta> [escala]
##
## `escala` es la vertical (metros de juego por metro real, p. ej. 0.04 = 1/25); sin ella, la del
## recurso. Se pone en el `Relieve` ANTES de montar el mundo, para que todas las celdas se construyan
## con ella. Guarda `<carpeta>/<sitio>.png`.

## [nombre, cámara (lat, lon, altura m de juego), mira (lat, lon, altura)]
const SITIOS := [
	["jamaica_sur", Vector3(17.86, -76.66, 15.0), Vector3(18.05, -76.60, 60.0)],
	["jamaica_norte", Vector3(18.52, -77.12, 15.0), Vector3(18.25, -77.10, 40.0)],
	["virgenes_tortola", Vector3(18.36, -64.60, 12.0), Vector3(18.41, -64.65, 15.0)],
	# Pico Turquino (1.974 m) desde el mar del sur: con el cerro sintético Cuba era una meseta.
	["cuba_sierra_maestra", Vector3(19.80, -76.84, 15.0), Vector3(19.99, -76.84, 60.0)],
	["espanola_pico_duarte", Vector3(19.90, -70.75, 15.0), Vector3(19.02, -70.98, 80.0)],
]


func _ready() -> void:
	get_tree().create_timer(400.0).timeout.connect(func():
		push_error("foto_relieve: se acabó el tiempo"); get_tree().quit(1))
	var args := OS.get_cmdline_user_args()
	var carpeta := args[0] if args.size() > 0 else "user://"
	var rel := load("res://assets/islas/relieve_caribe.tres") as Relieve
	if args.size() > 1:
		rel.poner_escala_vertical(float(args[1]))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(7.0).timeout
	var g := get_tree().get_first_node_in_group("tierra") as GestorTierra
	var o := get_node("/root/Origen")
	var arch: Archipielago = g.archipielago
	var cam := Camera3D.new()
	cam.far = 25000.0
	cam.fov = 55.0
	add_child(cam)
	for s in SITIOS:
		var desde: Vector3 = s[1]
		var hacia: Vector3 = s[2]
		var p := arch.de_lat_lon(desde.x, desde.y)
		var q := arch.de_lat_lon(hacia.x, hacia.y)
		o.llevar_a(p)
		await get_tree().process_frame
		await _hasta_quieto(g, 40.0)
		cam.global_position = o.a_local(Vector3(p.x, Oleaje.nivel + desde.z, p.y))
		cam.look_at(o.a_local(Vector3(q.x, Oleaje.nivel + hacia.z, q.y)))
		# Las cámaras del barco se hacen `current` cada frame: quietas, y sin HUD en la foto.
		for c in get_tree().root.find_children("*", "Camera3D", true, false):
			if c != cam:
				c.process_mode = Node.PROCESS_MODE_DISABLED
		for capa in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(capa as CanvasLayer).visible = false
		cam.current = true
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(carpeta.path_join(s[0] + ".png"))
	print("foto_relieve: %d fotos en %s (escala %.4f)" % [SITIOS.size(), carpeta, rel.escala_vertical])
	get_tree().quit()


func _hasta_quieto(g: GestorTierra, tope: float) -> void:
	var t := 0.0
	while t < tope:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > 2.0 and g.al_dia():
			return
