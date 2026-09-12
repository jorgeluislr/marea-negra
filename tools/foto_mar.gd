extends Node

## Fotografía el mar con varios estados de la mar, para juzgarlo por el ojo.
##
## Hace falta mirarlo además de medirlo: los números dicen que la ola tiene 1,6 m y que la
## malla la resuelve con 8,9 puntos, y ninguno de los dos dice si el mar parece agua o parece
## una sábana sacudida. Lo que se busca en las fotos es la cresta afilada y el valle ancho de
## Gerstner (un seno da las dos cosas iguales y se nota), que las crestas se corten entre sí en
## vez de correr en líneas paralelas, y que no haya serrucho en el horizonte.
##
## Tres estados a propósito: la calma es donde se ve si el mar de fondo basta, y el temporal
## donde se ve si las crestas se pliegan.
##
## **Con ventana, no `--headless`**: en headless no hay render y las capturas salen en negro.
##
##     godot --path . tools/foto_mar.tscn -- C:\ruta\donde\dejar\las\fotos

@export var carpeta := ""
## Fuerza del viento de cada toma, y cómo se llama.
@export var estados: Array = [
	{"fuerza": 0.15, "nombre": "calma"},
	{"fuerza": 1.0, "nombre": "brisa"},
	{"fuerza": 1.8, "nombre": "duro"},
]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		carpeta = String(a)
	if carpeta == "":
		carpeta = OS.get_user_data_dir()
	get_tree().create_timer(180.0).timeout.connect(func(): get_tree().quit(1))

	var esc := load("res://scenes/world/main_world.tscn") as PackedScene
	add_child(esc.instantiate())
	await get_tree().create_timer(5.0).timeout

	Viento.direccion_base = Vector3(1, 0, 0.3)
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0

	var barco := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if barco != null:
		barco.set("anclado", true)

	for e in estados:
		Viento.fuerza_base = float(e["fuerza"])
		# Dos vueltas de _process para que el viento recalcule su fuerza antes de asentarla.
		await get_tree().process_frame
		await get_tree().process_frame
		Oleaje.asentar()
		for i in 30:
			await get_tree().process_frame
		# Dos encuadres: uno a ras de agua, que es como se ve desde cubierta y donde el perfil
		# de la ola se lee de canto; y otro alto, que es donde se ve el dibujo de las crestas.
		# La tercera es el caso que destapó el borde del agua: la cámara orbital sube hasta unos
		# 80 m con el zoom al máximo, y desde ahí se veía acabarse el mar.
		for vista in [{"n": "ras", "alt": 2.2, "dist": 26.0, "mira": 1.0, "lejos": 0.0},
				{"n": "alto", "alt": 30.0, "dist": 45.0, "mira": -2.0, "lejos": 0.0},
				{"n": "muyalto", "alt": 80.0, "dist": 80.0, "mira": 0.0, "lejos": 3000.0}]:
			var cam := Camera3D.new()
			add_child(cam)
			cam.fov = 60.0
			cam.far = 25000.0
			cam.make_current()
			var centro := barco.global_position if barco != null else Vector3.ZERO
			cam.global_position = centro + Vector3(-float(vista["dist"]), float(vista["alt"]), 0)
			# Con `lejos` la cámara apunta al HORIZONTE y no al barco: el borde del agua solo se
			# juzga mirando allí, y apuntando al barco desde 80 m lo que sale es el suelo.
			cam.look_at(centro + Vector3(float(vista["lejos"]), float(vista["mira"]), 0),
				Vector3.UP)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var nombre := "mar_%s_%s.png" % [e["nombre"], vista["n"]]
			img.save_png(carpeta.path_join(nombre))
			print("FOTO %s   (mar %.2f m pico a pico, viento %.2f)"
				% [nombre, Oleaje.altura, Viento.fuerza])
			cam.queue_free()
	get_tree().quit(0)
