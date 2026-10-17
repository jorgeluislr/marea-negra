extends Node

## Fotografía la estela del barco NAVEGANDO, desde popa y desde arriba.
##
## La forma de la estela la mide la batería (`mundo` / estela) con un rastro sintético; esto es
## para verla de verdad: con el barco moviéndose, la mar debajo y la luz del juego. Deja navegar
## al barco con el viento de través y dispara cuando ya tiene arrancada y una estela entera.
##
## **Con ventana, no `--headless`**: en headless no hay render y las capturas salen en negro.
##
##     godot --path . tools/foto_estela.tscn -- C:\ruta\donde\dejar\las\fotos

@export var carpeta := ""
@export var segundos_navegando := 25.0


func _ready() -> void:
	var giro := false
	for a in OS.get_cmdline_user_args():
		if String(a) == "giro":
			giro = true
		else:
			carpeta = String(a)
	if carpeta == "":
		carpeta = OS.get_user_data_dir()
	get_tree().create_timer(180.0).timeout.connect(func(): get_tree().quit(1))

	var esc := load("res://scenes/world/main_world.tscn") as PackedScene
	add_child(esc.instantiate())
	await get_tree().create_timer(3.0).timeout

	var barco := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if barco == null:
		push_error("no hay barco activo")
		get_tree().quit(1)
		return
	# Viento de través respecto a la proa, constante: así navega derecho y a buena velocidad.
	var proa := -barco.global_transform.basis.z
	proa.y = 0.0
	proa = proa.normalized()
	Viento.direccion_base = proa.cross(Vector3.UP).normalized()
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	barco.set("anclado", false)
	await get_tree().create_timer(segundos_navegando).timeout
	print("velocidad %.2f m/s" % float(barco.get("velocidad")))
	if giro:
		await _giro(barco)
		get_tree().quit(0)
		return

	var g := barco.global_transform
	var adelante := -g.basis.z
	adelante.y = 0.0
	adelante = adelante.normalized()
	var lado := adelante.cross(Vector3.UP).normalized()
	var c := g.origin
	for vista in [
			{"n": "popa", "pos": c - adelante * 22.0 + Vector3.UP * 7.0 + lado * 4.0, "mira": c - adelante * 4.0},
			{"n": "alto", "pos": c - adelante * 10.0 + Vector3.UP * 45.0 + lado * 12.0, "mira": c - adelante * 18.0},
			{"n": "costado", "pos": c + lado * 14.0 + adelante * 6.0 + Vector3.UP * 4.0, "mira": c + adelante * 2.0}]:
		var cam := Camera3D.new()
		add_child(cam)
		cam.fov = 60.0
		cam.far = 25000.0
		cam.make_current()
		cam.global_position = vista["pos"]
		cam.look_at(vista["mira"], Vector3.UP)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var nombre := "estela_%s.png" % vista["n"]
		img.save_png(carpeta.path_join(nombre))
		print("FOTO %s" % nombre)
		cam.queue_free()
	get_tree().quit(0)


func _tecla(k: Key, pulsada: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = pulsada
	Input.parse_input_event(ev)


## Vista cenital fija en el MUNDO sobre el punto donde empezó el giro, para que las tres fotos
## sean comparables entre sí.
func _giro(barco: Node3D) -> void:
	var inicio := barco.global_position
	_tecla(KEY_D, true)
	await get_tree().create_timer(8.0).timeout
	_tecla(KEY_D, false)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 60.0
	cam.far = 25000.0
	cam.make_current()
	cam.global_position = inicio + Vector3.UP * 70.0
	cam.look_at(inicio + Vector3(0.01, 0.0, 0.0), Vector3(0, 0, -1))
	for i in 3:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var nombre := "estela_giro_%d.png" % i
		img.save_png(carpeta.path_join(nombre))
		print("FOTO %s" % nombre)
		_informe_rastro()
		await get_tree().create_timer(4.0).timeout


## Lo que lleva el rastro: cuántas muestras, cuánto mide de punta a punta siguiéndolo, y la
## edad de la más vieja. Si mide más de lo que el barco ha podido andar en esa edad, el rastro
## miente.
func _informe_rastro() -> void:
	var mar := get_tree().get_first_node_in_group("mar")
	var r: Estela = mar.get("_rastro") if mar != null else null
	if r == null:
		print("  sin rastro")
		return
	var n := 0
	var largo := 0.0
	var edad := 0.0
	for i in r.traza.size():
		var m: Vector4 = r.traza[i]
		if m.z < 0.0:
			break
		if i > 0:
			largo += Vector2(m.x, m.y).distance_to(Vector2(r.traza[i - 1].x, r.traza[i - 1].y))
		edad = m.z
		n += 1
	print("  rastro: %d muestras, %.1f m siguiéndolo, la más vieja de %.2f s, vel %.2f"
		% [n, largo, edad, r.traza[0].w])
