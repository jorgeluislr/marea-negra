extends Node

## Fotografía la humareda de un disparo a lo largo de su vida, para juzgar el efecto por el ojo.
##
## Hace falta una herramienta propia porque el humo **no se puede medir con un número**: no es
## una cota como la altura de la regala ni un tiempo como la recarga. Lo que decide si vale es
## si el borde se ve marcado, y eso se mira.
##
## Dispara UNA pieza y saca varias tomas repartidas por el 1,6 s que vive el fogonazo: la
## primera con el destello, las siguientes con las bocanadas ya abiertas, que es cuando se veían
## los discos de contorno duro.
##
## **Con ventana, no `--headless`**: en headless no hay render y las capturas salen en negro.
##
##     godot --path . tools/foto_humo.tscn -- C:\ruta\donde\dejar\las\fotos

@export var carpeta := ""
@export var espera := 5.0
## Instantes, en segundos desde el disparo, en los que se retrata. `Fogonazo.vida` es 1,6.
@export var instantes: Array[float] = [0.05, 0.25, 0.6, 1.1]

var _barco: Node3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		carpeta = String(a)
	if carpeta == "":
		carpeta = OS.get_user_data_dir()

	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_barco = esc.instantiate() as Node3D
	add_child(_barco)
	_barco.set("anclado", true)
	(_barco as Barco).altura_mar = -0.882
	(_barco as Barco).tomar_mando_jugador()

	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-52, 38, 0)
	luz.light_energy = 2.2
	add_child(luz)
	var ent := WorldEnvironment.new()
	var e := Environment.new()
	# Fondo OSCURO y liso a propósito: contra un cielo claro el borde del humo se disimula, y
	# lo que se quiere ver aquí es justo el borde.
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.12, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.50, 0.58)
	e.ambient_light_energy = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	ent.environment = e
	add_child(ent)

	await get_tree().create_timer(espera).timeout

	var pieza: Node3D = null
	for h in _barco.find_children("*", "", true, false):
		if h.has_method("disparar") and String(h.call("banda")) == "estribor":
			pieza = h as Node3D
			break
	if pieza == null:
		print("no hay pieza a estribor")
		get_tree().quit(1)
		return

	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50.0
	cam.make_current()
	# Desde fuera del costado y un poco por delante: el humo sale hacia la banda, así que desde
	# ahí se ve de perfil y entero.
	var boca: Vector3 = pieza.call("boca_global")
	cam.global_position = boca + Vector3(7.0, 1.6, -5.0)
	cam.look_at(boca + Vector3(2.5, 0.4, 0.0), Vector3.UP)

	pieza.call("disparar")
	var t := 0.0
	for i in instantes.size():
		while t < instantes[i]:
			t += get_process_delta_time()
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var nombre := "humo_%d_%03dms.png" % [i + 1, int(instantes[i] * 1000.0)]
		img.save_png(carpeta.path_join(nombre))
		print("FOTO %s" % nombre)
	get_tree().quit(0)
