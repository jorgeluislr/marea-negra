extends Node

## Qué se ve por cada escotilla: la madera de la bodega, la TAPA de sentina o el mar.
##
## No se puede decidir por el color —el agua de sentina de la tapa y el mar son los dos azules
## oscuros—, así que se hace como ya se hizo una vez con esta misma tapa: **la misma toma con ella
## y sin ella**. Los píxeles que cambian son los que la están enseñando; y lo que aparece debajo
## al quitarla dice si estaba tapando mar (hace falta) o madera (sobra y encima se ve).
##
## Se mide FRAME A FRAME durante varios segundos porque el defecto es intermitente: la tapa sube
## y baja dentro de la bodega con la ola, y hay instantes en que asoma por encima del suelo de la
## bodega y otros en que no. Una foto suelta no decide nada.
##
##     godot --path . tools/por_la_rejilla.tscn -- C:\ruta\fotos
##     godot --path . tools/por_la_rejilla.tscn -- C:\ruta\fotos 1.9    # en temporal
##
## Guarda la peor toma de cada escotilla, con tapa y sin ella.

## Cuántas veces se mira por cada escotilla, y cada cuánto.
const TOMAS := 24
const ENTRE_TOMAS := 0.45

@export var carpeta := ""


func _ready() -> void:
	var viento := 1.0
	# "sinrecorte" apaga el recorte del agua: es el CONTROL del instrumento. Si con el agujero
	# quitado la cifra de mar no se dispara, es que la cifra no distingue el mar del herraje de la
	# rejilla y no vale para nada.
	var sin_recorte := false
	for a in OS.get_cmdline_user_args():
		if String(a) == "sinrecorte":
			sin_recorte = true
		elif String(a).is_valid_float():
			viento = String(a).to_float()
		else:
			carpeta = String(a)
	if carpeta == "":
		carpeta = OS.get_user_data_dir()
	get_tree().create_timer(400.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = viento
	await get_tree().create_timer(7.0).timeout
	Oleaje.asentar()

	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		get_tree().quit(1)
		return
	b.set("anclado", false)
	if sin_recorte:
		b.set("recorta_el_agua", false)
	var tapa := b.get_node_or_null(^"TapaSentina") as MeshInstance3D
	var escotillas: Array[MeshInstance3D] = []
	for n in b.find_children("escotilla_*", "MeshInstance3D", true, false):
		escotillas.append(n as MeshInstance3D)
	escotillas.sort_custom(func(x, y): return x.name < y.name)
	var cam := Camera3D.new()
	cam.far = 25000.0
	cam.fov = 38.0
	add_child(cam)

	print("\n─── por la rejilla ───")
	print("viento %.2f -> mar de %.2f m pico a pico, %d escotillas%s"
		% [Viento.fuerza, Oleaje.altura, escotillas.size(),
			"   (RECORTE APAGADO: control)" if sin_recorte else ""])
	print("%-14s %-22s %-22s %-14s %s"
		% ["escotilla", "se ve la tapa", "sin ella habria mar", "tomas con tapa", "LO QUE SE VE"])

	for e in escotillas:
		var peor_tapa := 0.0
		var peor_mar := 0.0
		var con_tapa := 0
		var tono := 0.0
		var tonos := 0
		# Lo que se ve DE VERDAD ahora mismo, haya tapa o no. Es la cifra que cuenta cuando ya no
		# hay tapa que apagar: si sale mar por la rejilla, sale.
		var mar_ahora := 0.0
		var mejor_a: Image = null
		var mejor_b: Image = null
		for k in TOMAS:
			var t := 0.0
			while t < ENTRE_TOMAS:
				await get_tree().process_frame
				t += get_process_delta_time()
			# La cámara se coloca justo encima de la escotilla y mirando a plomo, que es como se
			# mira por una rejilla desde cubierta.
			var centro: Vector3 = e.global_transform * e.mesh.get_aabb().get_center()
			var arriba: Vector3 = b.global_transform.basis.y.normalized()
			cam.global_position = centro + arriba * 0.85
			cam.look_at(centro - arriba, b.global_transform.basis.z)
			cam.make_current()
			if tapa != null:
				tapa.visible = true
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var a := get_viewport().get_texture().get_image()
			# Sin tapa que apagar no hay nada que comparar: entre dos frames se mueven el mar y el
			# barco, y la diferencia se lo comería todo (medido: 83 % de "tapa" sin tapa ninguna).
			var c := a
			if tapa != null:
				tapa.visible = false
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				c = get_viewport().get_texture().get_image()
				tapa.visible = true

			var dif := 0
			var mar := 0
			var mar_a := 0
			var total := 0
			# Y de qué COLOR se ve lo que tapa: es lo que el ojo juzga. Frío = parece agua.
			var sr := 0.0
			var sb := 0.0
			# Se recorre de 4 en 4 píxeles: la cifra no cambia y la tirada no se eterniza.
			for y in range(0, a.get_height(), 4):
				for x in range(0, a.get_width(), 4):
					total += 1
					var ca := a.get_pixel(x, y)
					var cb := c.get_pixel(x, y)
					# El herraje de la rejilla también es gris azulado, así que además de azul hay
					# que pedir CLARO: el mar lo es y el hierro en sombra no.
					if ca.b > ca.r * 1.30 and ca.b > 0.15:
						mar_a += 1
					if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.04:
						dif += 1
						# Lo que hay DEBAJO de la tapa: azul de mar (el canal azul manda sobre el
						# rojo) o madera (al revés). La madera de este barco es siempre cálida.
						# Azul CLARAMENTE dominante y no una sombra: la madera en penumbra sale gris
						# azulada y con 1,08 de umbral se contaba como mar.
						if cb.b > cb.r * 1.30 and cb.b > 0.05:
							mar += 1
						sr += ca.r
						sb += ca.b
			var ft := float(maxi(total, 1))
			mar_ahora = maxf(mar_ahora, float(mar_a) / ft)
			if dif > 0:
				con_tapa += 1
			if dif > 0:
				tono += sb / maxf(sr, 0.0001)
				tonos += 1
			if float(dif) / ft > peor_tapa:
				peor_tapa = float(dif) / ft
				peor_mar = float(mar) / ft
			# La toma que se guarda es la de MÁS mar a la vista, que es la que hay que mirar.
			if float(mar_a) / ft >= mar_ahora - 0.0001:
				mejor_a = a
				mejor_b = c
		# El tono es azul/rojo de lo que la tapa enseña: por encima de 1 tira a azul (parece agua),
		# por debajo a marrón (parece madera).
		print("%-14s %7.1f %% del hueco    %7.1f %% del hueco    %d de %d    se ve mar: %.1f %%"
			% [e.name, peor_tapa * 100.0, peor_mar * 100.0, con_tapa, TOMAS, mar_ahora * 100.0])
		if mejor_a != null:
			mejor_a.save_png(carpeta.path_join("rejilla_%s_contapa.png" % e.name))
			mejor_b.save_png(carpeta.path_join("rejilla_%s_sintapa.png" % e.name))
	get_tree().quit(0)
