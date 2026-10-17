extends Node

## Si se ve el mar DENTRO del barco, y si el recorte del agua hace falta o estorba.
##
## El recorte (`Barco.recorta_el_agua`) quita el agua dentro de una elipse en PLANTA, y nació
## para la lancha, que es un bote abierto sin cubierta. Desde que el casco cabecea y escora con
## la ola esa elipse deja de coincidir con la silueta: abre un hueco de mar por una banda
## mientras deja entrar el agua por la otra. Y un casco con cubierta y bodega, como la balandra,
## a lo mejor no lo necesita para nada porque su propia madera ya tapa la lámina.
##
## Retrata las dos opciones desde los tres sitios donde se notaría: dentro de la bodega, desde
## cubierta y desde fuera a ras de agua, con el barco navegando y escorado, que es cuando falla.
##
##     godot --path . tools/agua_dentro.tscn -- C:\ruta\donde\dejar\las\fotos
##
## Con ventana, no `--headless`: en headless no hay render y las capturas salen negras.

@export var carpeta := ""
## Cuántas veces se pulsa TAB antes de fotografiar, para retratar otro barco de la flota. La
## lancha es el caso que importa además de la balandra: es un bote ABIERTO y sin cubierta, y fue
## para ella para quien se inventó el recorte del agua.
@export var cambios := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).is_valid_int():
			cambios = String(a).to_int()
		else:
			carpeta = String(a)
	if carpeta == "":
		carpeta = OS.get_user_data_dir()
	get_tree().create_timer(180.0).timeout.connect(func(): get_tree().quit(1))

	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.direccion_base = Vector3(1, 0, 0.3)
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	await get_tree().create_timer(7.0).timeout
	Oleaje.asentar()

	for i in cambios:
		var e := InputEventKey.new()
		e.keycode = KEY_TAB
		e.physical_keycode = KEY_TAB
		e.pressed = true
		Input.parse_input_event(e)
		await get_tree().process_frame
		e.pressed = false
		Input.parse_input_event(e)
		await get_tree().create_timer(4.0).timeout

	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		print("no hay barco")
		get_tree().quit(1)
		return
	b.set("anclado", false)

	var cam := Camera3D.new()
	cam.far = 25000.0
	cam.fov = 70.0
	add_child(cam)

	for recorta in [true, false]:
		# La tapa se monta en el `_ready` del barco, así que aquí se enciende y se apaga por
		# visibilidad, no por la propiedad.
		var tapa := b.get_node_or_null(^"TapaSentina") as MeshInstance3D
		if tapa != null:
			tapa.visible = recorta
		# Se espera a pillar el barco ESCORADO, que es cuando el recorte en planta falla. Con el
		# casco adrizado las dos opciones salen casi iguales y la foto no decide nada.
		var esperando := 0.0
		while esperando < 6.0 and absf(b.global_transform.basis.get_euler().z) < 0.025:
			await get_tree().process_frame
			esperando += get_process_delta_time()
		var escora := rad_to_deg(b.global_transform.basis.get_euler().z)

		# La bodega se retrata VARIAS veces separadas en el tiempo: el agua no entra siempre,
		# entra cuando la ola sube, y una sola foto puede pillarla en el valle y decir que todo
		# está bien.
		var vistas := [
				{"n": "cubierta", "de": Vector3(0.0, 4.2, 6.0), "a": Vector3(0.0, 1.2, -2.0)},
				{"n": "costado", "de": Vector3(7.0, 0.35, 1.0), "a": Vector3(0.0, 0.2, 0.0)},
				# Mirando al SUELO de la bodega desde dentro: es donde se ven las manchas.
				{"n": "suelo", "de": Vector3(0.0, 3.0, -1.0), "a": Vector3(0.0, 0.4, -1.6)},
				{"n": "suelopopa", "de": Vector3(0.0, 3.0, 3.5), "a": Vector3(0.0, 0.4, 2.6)},
				# Desde DEBAJO del casco, mirando hacia arriba.
				{"n": "quilla", "de": Vector3(0.0, -3.5, 0.0), "a": Vector3(0.0, 0.5, -1.0)}]
		for k in 4:
			vistas.append({"n": "bodega%d" % k, "de": Vector3(0.0, 2.6, 2.0),
				"a": Vector3(0.0, 0.9, -3.0), "espera": 1.7})
		for vista in vistas:
			if vista.has("espera"):
				var e := 0.0
				while e < float(vista["espera"]):
					await get_tree().process_frame
					e += get_process_delta_time()
			cam.global_position = b.global_transform * (vista["de"] as Vector3)
			cam.look_at(b.global_transform * (vista["a"] as Vector3), Vector3.UP)
			# Sin esto las fotos salen desde la cámara del juego: la orbital del barco reclama
			# el visor en su `_ready` y se lo queda. Hay que pedirlo en cada toma.
			cam.make_current()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var nombre := "dentro_%s_%s_%s.png" % [str(b.get("nombre")).to_lower(),
				vista["n"], "tapa" if recorta else "sintapa"]
			get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
			print("FOTO %s   (escora %.2f°)" % [nombre, escora])
	get_tree().quit(0)
