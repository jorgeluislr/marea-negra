extends Node

## Recorre el menú principal DE VERDAD, cambiando de escena: cada botón abre su escena, Esc pausa,
## «Menú principal» vuelve, y tras la tormenta el viento está otra vez como de fábrica. Saca una
## foto del menú, de cada escena y de la pausa.
##
##     godot --path . --max-fps 120 tools/recorrer_menu.tscn -- C:\ruta\fotos
##
## La batería (`tests/menu_test.gd`) prueba los botones sin cambiar de escena, porque cambiarla la
## tiraría; esto es lo que queda: que el cambio funciona. Quien maneja va colgado de la raíz, que
## sobrevive al cambio de escena.

const MENU := "res://scenes/ui/menu_principal.tscn"
const BOTONES := {
	"Navegar": "res://scenes/world/main_world.tscn",
	"BatallaRapida": "res://scenes/world/escaramuza.tscn",
	"TiroAlBlanco": "res://scenes/world/combate.tscn",
	"DueloCapitanes": "res://scenes/world/duelo_ia.tscn",
	"Tormenta": "res://scenes/world/tormenta.tscn",
}


func _ready() -> void:
	var carpeta := OS.get_user_data_dir()
	for a in OS.get_cmdline_user_args():
		carpeta = String(a)
	var c := Conductor.new()
	c.carpeta = carpeta
	get_tree().root.add_child.call_deferred(c)


class Conductor extends Node:
	var carpeta := ""
	var fallos := 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().create_timer(400.0, true, false, true).timeout.connect(func():
			push_error("recorrer_menu: se acabó el tiempo"); get_tree().quit(1))
		var fuerza0: float = Viento.fuerza_base
		get_tree().change_scene_to_file(MENU)
		# La intro: el nombre sobre negro, a medio abrir, y abierta.
		var t_intro := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t_intro < 5000 and (get_tree().current_scene == null
				or get_tree().current_scene.find_child("Intro", true, false) == null):
			await get_tree().process_frame
		_ver(get_tree().current_scene.find_child("Intro", true, false) != null, "sale la intro")
		await _esperar(1.0)
		await _foto("intro_1.png")
		await _esperar(1.3)
		await _foto("intro_2.png")
		await _esperar(0.6)
		await _foto("intro_3.png")
		await _esperar(1.5)
		_ver(get_tree().current_scene.find_child("Intro", true, false) == null, "la intro se acaba sola")
		_ver(get_tree().current_scene.scene_file_path == MENU, "arranca en el menú")
		await _foto("menu.png")
		await _clic(get_tree().current_scene.find_child("Ajustes", true, false))
		await _foto("ajustes.png")
		await _clic(get_tree().current_scene.find_child("Volver", true, false))
		# La lista vuelve a colocar sus botones al mostrarse: un clic dos fotogramas después cae
		# donde estaban antes.
		await _esperar(0.5)
		for nombre in BOTONES:
			var b := get_tree().current_scene.find_child(nombre, true, false) as Button
			if not _ver(b != null, "botón %s" % nombre):
				continue
			await _clic(b)
			var carga := Partida.find_child("PantallaCarga", true, false) as Control
			for i in 3:
				await get_tree().process_frame
			_ver(carga.visible, "al abrir %s se ve la pantalla de carga" % nombre)
			if nombre == "Navegar":
				await _foto("carga.png")
			var t0 := Time.get_ticks_msec()
			while carga.visible and Time.get_ticks_msec() - t0 < 45000:
				await get_tree().process_frame
			_ver(not carga.visible, "y se quita al asentarse %s (%.1f s)"
				% [nombre, (Time.get_ticks_msec() - t0) / 1000.0])
			var tierra := get_tree().get_first_node_in_group("tierra")
			if tierra != null:
				_ver(tierra.al_dia(), "al quitarse la carga de %s las islas están puestas" % nombre)
			await _esperar(1.0)
			var en: String = get_tree().current_scene.scene_file_path
			_ver(en == BOTONES[nombre], "%s abre %s" % [nombre, en])
			await _foto("%s.png" % nombre)
			await _tecla(KEY_ESCAPE)
			_ver(get_tree().paused, "Esc pausa en %s" % nombre)
			if nombre == "Navegar":
				await _foto("pausa.png")
				await _clic(Partida.find_child("Ajustes", true, false))
				await _foto("ajustes_pausa.png")
				await _tecla(KEY_ESCAPE)
				_ver(get_tree().paused, "Esc en los ajustes sigue en pausa")
			var al_menu := Partida.find_child("MenuPrincipal", true, false) as Button
			await _clic(al_menu)
			await _esperar(3.0)
			_ver(get_tree().current_scene.find_child("Intro", true, false) == null,
				"al volver de %s no se repite la intro" % nombre)
			_ver(get_tree().current_scene.scene_file_path == MENU and not get_tree().paused,
				"desde %s vuelve al menú sin pausa" % nombre)
		_ver(is_equal_approx(Viento.fuerza_base, fuerza0) and Engine.time_scale == 1.0,
			"tras la tormenta el viento vuelve a %.2f (está en %.2f)" % [fuerza0, Viento.fuerza_base])
		print("RECORRIDO: %s" % ("todo bien" if fallos == 0 else "%d fallos" % fallos))
		get_tree().quit(1 if fallos > 0 else 0)

	func _ver(si: bool, que: String) -> bool:
		print("%s %s" % ["OK   " if si else "FALLO", que])
		if not si:
			fallos += 1
		return si

	func _esperar(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout

	func _clic(c: Control) -> void:
		var p := c.get_global_rect().get_center()
		for pulsado in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = pulsado
			e.position = p
			e.global_position = p
			Input.parse_input_event(e)
			await get_tree().process_frame

	func _tecla(k: Key) -> void:
		for pulsado in [true, false]:
			var e := InputEventKey.new()
			e.keycode = k
			e.physical_keycode = k
			e.pressed = pulsado
			Input.parse_input_event(e)
			await get_tree().process_frame
		await get_tree().process_frame

	func _foto(nombre: String) -> void:
		for i in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
