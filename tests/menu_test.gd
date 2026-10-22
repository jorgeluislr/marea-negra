class_name MenuTest
extends RefCounted

## Paquete `menu`: el menú principal, el de ajustes y el de pausa.
##
## El menú principal (`scenes/ui/menu_principal.tscn`) es la escena con la que arranca el juego:
## lanza las cinco escenas que hay, abre los ajustes y sale. Los ajustes (`menu_ajustes.tscn`)
## eligen la dificultad del capitán de IA y el volumen, que guarda `Ajustes`. Esc en partida pausa y
## abre un panel con Continuar, Ajustes, Menú principal y Salir (autoload `Partida`).
##
## Se maneja con el RATÓN, haciendo clic en el centro de cada botón con `Input.parse_input_event`,
## para probar también que los botones están donde se ven y nada los tapa. Con `cambiar_escena` a
## false el menú solo AVISA de la escena pedida: cambiarla de verdad tiraría la batería.
##
## Al menú y a `Partida` se les llama por ruta y por nombre, sin `class_name`, para que si faltan
## salga en rojo la comprobación y no la batería entera caída por un error de parseo.

const MENU := "res://scenes/ui/menu_principal.tscn"
const RUTA_PRUEBA := "user://ajustes_prueba_menu.cfg"
const TITULO := "res://assets/textures/ui/titulo_menu.png"
const MARCO := "res://assets/textures/ui/marco_menu.png"
## Cada botón del menú y la escena que tiene que abrir.
const ESCENAS := {
	"Navegar": "res://scenes/world/main_world.tscn",
	"BatallaRapida": "res://scenes/world/escaramuza.tscn",
	"TiroAlBlanco": "res://scenes/world/combate.tscn",
	"DueloCapitanes": "res://scenes/world/duelo_ia.tscn",
	"Tormenta": "res://scenes/world/tormenta.tscn",
}


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("menu")
	var hay := ResourceLoader.exists(MENU)
	m.comprobar(hay, "existe el menú principal", MENU)
	m.comprobar(ProjectSettings.get_setting("application/run/main_scene") == MENU,
		"el juego arranca en el menú", str(ProjectSettings.get_setting("application/run/main_scene")))
	if not hay:
		return
	var raton := Input.mouse_mode
	if m.escenario("estilo"):
		await _estilo(m, arbol)
	if m.escenario("escenas"):
		await _escenas(m, arbol)
	if m.escenario("dificultad"):
		await _dificultad(m, arbol)
	if m.escenario("volumen"):
		await _volumen(m, arbol)
	if m.escenario("ajustes"):
		await _ajustes(m, arbol)
	if m.escenario("pausa"):
		await _pausa(m, arbol)
	if m.escenario("ajustes_en_pausa"):
		await _ajustes_en_pausa(m, arbol)
	if m.escenario("carga"):
		await _carga(m, arbol)
	if m.escenario("intro"):
		await _intro(m, arbol)
	if m.escenario("islas"):
		await _islas(m, arbol)
	Input.mouse_mode = raton


## Monta el menú encima del mundo de la batería, en una capa por encima del HUD.
static func _montar(arbol: SceneTree) -> Node:
	var capa := CanvasLayer.new()
	capa.layer = 100
	arbol.root.add_child(capa)
	var menu := (load(MENU) as PackedScene).instantiate()
	menu.set("cambiar_escena", false)
	capa.add_child(menu)
	for i in 5:
		await arbol.process_frame
	return menu


## Abre los ajustes con su botón del menú principal.
static func _abrir_ajustes(arbol: SceneTree, menu: Node) -> void:
	var b := menu.find_child("Ajustes", true, false) as Button
	if b != null:
		await _clic(arbol, b)


static func arranque_imagen() -> String:
	return String(ProjectSettings.get_setting("application/boot_splash/image", ""))


static func _desmontar(menu: Node) -> void:
	menu.get_parent().queue_free()


static func _clic(arbol: SceneTree, c: Control) -> void:
	var p := c.get_global_rect().get_center()
	var mov := InputEventMouseMotion.new()
	mov.position = p
	mov.global_position = p
	Input.parse_input_event(mov)
	await arbol.process_frame
	for pulsado in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pulsado
		e.position = p
		e.global_position = p
		Input.parse_input_event(e)
		await arbol.process_frame
	await arbol.process_frame


static func _tecla(arbol: SceneTree, k: Key) -> void:
	for pulsado in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = pulsado
		Input.parse_input_event(e)
		await arbol.process_frame
	await arbol.process_frame


## Cada botón abre su escena, la escena existe, y Salir pide salir.
static func _escenas(m: MarcoPruebas, arbol: SceneTree) -> void:
	var menu := await _montar(arbol)
	m.comprobar(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "en el menú el ratón se ve")
	var pedidas: Array[String] = []
	menu.connect("escena_pedida", func(r: String): pedidas.append(r))
	for nombre in ESCENAS:
		var b := menu.find_child(nombre, true, false) as Button
		if not m.comprobar(b != null and b.is_visible_in_tree(), "hay botón %s" % nombre):
			continue
		pedidas.clear()
		await _clic(arbol, b)
		var r: String = ESCENAS[nombre]
		m.comprobar(pedidas == [r], "%s abre %s" % [nombre, r.get_file()], str(pedidas))
		m.comprobar(ResourceLoader.exists(r), "%s existe" % r.get_file())
	var salir := menu.find_child("Salir", true, false) as Button
	var sale := [false]
	menu.connect("salir_pedido", func(): sale[0] = true)
	if m.comprobar(salir != null, "hay botón Salir"):
		await _clic(arbol, salir)
		m.comprobar(sale[0], "Salir pide salir")
	_desmontar(menu)


## La dificultad elegida con el ratón llega a `Ajustes`, se guarda en disco y la lee un arranque
## nuevo; y un menú nuevo la muestra marcada.
static func _dificultad(m: MarcoPruebas, arbol: SceneTree) -> void:
	var ruta_antes: String = Ajustes.ruta
	var nivel_antes: String = Ajustes.dificultad
	var vol_antes: float = Ajustes.volumen_musica
	Ajustes.ruta = RUTA_PRUEBA
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_PRUEBA))
	Ajustes.dificultad = "normal"
	var menu := await _montar(arbol)
	await _abrir_ajustes(arbol, menu)
	for par in [["Dificil", "dificil"], ["Facil", "facil"], ["Dificil", "dificil"]]:
		var b := menu.find_child(par[0], true, false) as Button
		if not m.comprobar(b != null, "hay botón %s" % par[0]):
			continue
		await _clic(arbol, b)
		m.comprobar(Ajustes.dificultad == par[1], "%s pone la dificultad «%s»" % par,
			Ajustes.dificultad)
	_desmontar(menu)
	# Un arranque nuevo: otro Ajustes leyendo el mismo archivo.
	var nuevo := Node.new()
	nuevo.set_script(load("res://scripts/mundo/ajustes.gd"))
	nuevo.set("ruta", RUTA_PRUEBA)
	m.comprobar(nuevo.call("cargar") and nuevo.get("dificultad") == "dificil",
		"la dificultad elegida sobrevive a un arranque", str(nuevo.get("dificultad")))
	nuevo.free()
	var otro := await _montar(arbol)
	await _abrir_ajustes(arbol, otro)
	var marcado := otro.find_child("Dificil", true, false) as Button
	m.comprobar(marcado != null and marcado.button_pressed, "el menú muestra la dificultad guardada")
	_desmontar(otro)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_PRUEBA))
	Ajustes.ruta = ruta_antes
	Ajustes.dificultad = nivel_antes
	Ajustes.volumen_musica = vol_antes


## El volumen se mueve con el teclado sobre la barra (izquierda baja) y se guarda.
static func _volumen(m: MarcoPruebas, arbol: SceneTree) -> void:
	var ruta_antes: String = Ajustes.ruta
	var vol_antes: float = Ajustes.volumen_musica
	Ajustes.ruta = RUTA_PRUEBA
	Ajustes.volumen_musica = 1.0
	var menu := await _montar(arbol)
	await _abrir_ajustes(arbol, menu)
	var barra := menu.find_child("Volumen", true, false) as Range
	if m.comprobar(barra != null, "hay barra de volumen"):
		m.casi(barra.value, 1.0, 0.001, "la barra arranca en el volumen guardado")
		barra.grab_focus()
		for i in 3:
			await _tecla(arbol, KEY_LEFT)
		m.menor_que(Ajustes.volumen_musica, 0.95, "bajar la barra baja el volumen")
		var cfg := ConfigFile.new()
		var leido := cfg.load(RUTA_PRUEBA) == OK
		m.casi(float(cfg.get_value("audio", "volumen_musica", -1.0)) if leido else -1.0,
			Ajustes.volumen_musica, 0.001, "el volumen se guarda")
	_desmontar(menu)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_PRUEBA))
	Ajustes.ruta = ruta_antes
	Ajustes.set("volumen_musica", vol_antes)
	Ajustes.volumen_musica_cambiado.emit(vol_antes)


## Esc en partida pausa y abre el panel; Continuar y Esc vuelven; Menú principal pide el menú.
static func _pausa(m: MarcoPruebas, arbol: SceneTree) -> void:
	var partida := arbol.root.get_node_or_null(^"Partida")
	if not m.comprobar(partida != null, "existe el autoload Partida"):
		return
	partida.set("cambiar_escena", false)
	m.comprobar(not arbol.paused, "la batería no empieza en pausa")
	await _tecla(arbol, KEY_ESCAPE)
	m.comprobar(arbol.paused, "Esc pausa la partida")
	var cont := partida.find_child("Continuar", true, false) as Button
	m.comprobar(cont != null and cont.is_visible_in_tree(), "en pausa se ve Continuar")
	m.comprobar(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "en pausa el ratón se ve")
	if cont != null:
		await _clic(arbol, cont)
	m.comprobar(not arbol.paused, "Continuar quita la pausa")
	await _tecla(arbol, KEY_ESCAPE)
	await _tecla(arbol, KEY_ESCAPE)
	m.comprobar(not arbol.paused, "Esc otra vez quita la pausa")
	await _tecla(arbol, KEY_ESCAPE)
	var pedidas: Array[String] = []
	partida.connect("escena_pedida", func(r: String): pedidas.append(r))
	var al_menu := partida.find_child("MenuPrincipal", true, false) as Button
	if m.comprobar(al_menu != null and al_menu.is_visible_in_tree(), "en pausa se ve Menú principal"):
		await _clic(arbol, al_menu)
		m.comprobar(pedidas == [MENU], "Menú principal vuelve al menú", str(pedidas))
		m.comprobar(not arbol.paused, "al volver al menú se quita la pausa")
	arbol.paused = false
	partida.set("cambiar_escena", true)


## El botón Ajustes del menú principal cambia la lista por el menú de ajustes, y Volver y Esc
## devuelven la lista.
static func _ajustes(m: MarcoPruebas, arbol: SceneTree) -> void:
	var menu := await _montar(arbol)
	var lista := menu.find_child("Panel", true, false) as Control
	var b := menu.find_child("Ajustes", true, false) as Button
	var ajustes := menu.find_child("MenuAjustes", true, false) as Control
	if not m.comprobar(b != null and ajustes != null and lista != null,
			"el menú principal tiene botón y menú de ajustes"):
		_desmontar(menu)
		return
	m.comprobar(not ajustes.is_visible_in_tree(), "los ajustes empiezan cerrados")
	m.comprobar(menu.find_child("Dificil", true, false).is_visible_in_tree() == false,
		"la dificultad ya no está en la lista principal")
	await _clic(arbol, b)
	m.comprobar(ajustes.is_visible_in_tree() and not lista.is_visible_in_tree(),
		"Ajustes abre el menú de ajustes en lugar de la lista")
	var volver := ajustes.find_child("Volver", true, false) as Button
	if m.comprobar(volver != null, "hay botón Volver"):
		await _clic(arbol, volver)
		m.comprobar(lista.is_visible_in_tree() and not ajustes.is_visible_in_tree(),
			"Volver devuelve la lista")
	await _clic(arbol, b)
	await _tecla(arbol, KEY_ESCAPE)
	m.comprobar(lista.is_visible_in_tree() and not ajustes.is_visible_in_tree(),
		"Esc en los ajustes devuelve la lista")
	_desmontar(menu)


## En pausa también hay ajustes: Esc los cierra sin quitar la pausa, y el volumen cambia en vivo.
static func _ajustes_en_pausa(m: MarcoPruebas, arbol: SceneTree) -> void:
	var partida := arbol.root.get_node_or_null(^"Partida")
	if not m.comprobar(partida != null, "existe el autoload Partida"):
		return
	var ruta_antes: String = Ajustes.ruta
	var vol_antes: float = Ajustes.volumen_musica
	Ajustes.ruta = RUTA_PRUEBA
	await _tecla(arbol, KEY_ESCAPE)
	var b := partida.find_child("Ajustes", true, false) as Button
	var ajustes := partida.find_child("MenuAjustes", true, false) as Control
	if m.comprobar(b != null and ajustes != null and b.is_visible_in_tree(),
			"en pausa hay botón y menú de ajustes"):
		await _clic(arbol, b)
		m.comprobar(ajustes.is_visible_in_tree(), "Ajustes abre el menú de ajustes en pausa")
		var barra := ajustes.find_child("Volumen", true, false) as Range
		if m.comprobar(barra != null, "en pausa hay barra de volumen"):
			barra.grab_focus()
			await _tecla(arbol, KEY_LEFT)
			m.casi(Ajustes.volumen_musica, barra.value, 0.001, "en pausa la barra mueve el volumen")
		await _tecla(arbol, KEY_ESCAPE)
		m.comprobar(arbol.paused and not ajustes.is_visible_in_tree(),
			"Esc cierra los ajustes y sigue en pausa")
	await _tecla(arbol, KEY_ESCAPE)
	m.comprobar(not arbol.paused, "y otro Esc vuelve a la partida")
	arbol.paused = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_PRUEBA))
	Ajustes.ruta = ruta_antes
	Ajustes.set("volumen_musica", vol_antes)
	Ajustes.volumen_musica_cambiado.emit(vol_antes)


## El título es la imagen de Meshy y los tres paneles (menú, ajustes y pausa) llevan su marco.
static func _estilo(m: MarcoPruebas, arbol: SceneTree) -> void:
	var menu := await _montar(arbol)
	var titulo := menu.find_child("Titulo", true, false) as TextureRect
	m.comprobar(titulo != null and titulo.texture != null and titulo.texture.resource_path == TITULO,
		"el título es la imagen del título", str(titulo))
	var partida := arbol.root.get_node_or_null(^"Partida")
	var paneles := {
		"lista del menú": menu.find_child("Panel", true, false),
		"ajustes": menu.find_child("MenuAjustes", true, false),
		"pausa": partida.find_child("Caja", true, false) if partida != null else null,
	}
	for nombre in paneles:
		var p := paneles[nombre] as Control
		var caja := p.get_theme_stylebox("panel") as StyleBoxTexture if p != null else null
		m.comprobar(caja != null and caja.texture != null and caja.texture.resource_path == MARCO,
			"el panel de %s lleva el marco" % nombre)
	_desmontar(menu)


## La pantalla de carga: el arranque enseña la imagen de carga, y `Partida.precargar()` pone la
## pantalla con su barra mientras lee la escena en otro hilo y la quita al tenerla. Con
## `cambiar_escena` a false entrega la escena sin cambiarla.
static func _carga(m: MarcoPruebas, arbol: SceneTree) -> void:
	var arranque := String(ProjectSettings.get_setting("application/boot_splash/image", ""))
	m.comprobar(arranque != "" and FileAccess.file_exists(arranque),
		"el arranque enseña una imagen del juego", arranque)
	# Los 5 s de portada que pidió el usuario los pone el MENÚ, no el motor: el mínimo del motor vale
	# para cualquier escena, también la batería, y le retrasa el primer fotograma lo bastante como para
	# desfasar el reloj del mar del de la física (la guía de tiro fallaba por 2,45 m en vez de 0,01).
	m.comprobar(int(ProjectSettings.get_setting("application/boot_splash/minimum_display_time", 0)) == 0,
		"el motor no alarga la portada (la alarga el menú)")
	var partida := arbol.root.get_node_or_null(^"Partida")
	var pantalla := partida.find_child("PantallaCarga", true, false) as Control if partida else null
	if not m.comprobar(pantalla != null and pantalla.find_child("Progreso", true, false) is Range,
			"Partida tiene pantalla de carga con barra"):
		return
	m.comprobar(not pantalla.visible, "la pantalla de carga empieza oculta")
	var hay: Array = partida.call("pantallas")
	m.comprobar(not hay.is_empty(), "hay imágenes de carga en la carpeta", str(hay))
	m.comprobar(arranque in hay, "el arranque usa una de ellas")
	partida.set("cambiar_escena", false)
	var llegada := []
	var avisar := func(e): llegada.append(e)
	partida.connect("cargada", avisar)
	var ruta := "res://scenes/world/combate.tscn"
	partida.call("precargar", ruta)
	await arbol.process_frame
	m.comprobar(pantalla.is_visible_in_tree(), "al abrir una escena se ve la pantalla de carga")
	var imagen := pantalla.find_child("Imagen", true, false) as TextureRect
	m.comprobar(imagen != null and imagen.texture != null and imagen.texture.resource_path in hay,
		"enseña una de las imágenes de carga",
		str(imagen.texture.resource_path if imagen and imagen.texture else "ninguna"))
	var barra := pantalla.find_child("Progreso", true, false) as Range
	var t := 0.0
	while llegada.is_empty() and t < 30.0:
		await arbol.process_frame
		t += arbol.root.get_process_delta_time()
	var escena := llegada[0] as PackedScene if not llegada.is_empty() else null
	m.comprobar(escena != null and escena.resource_path == ruta, "llega la escena pedida",
		str(escena.resource_path if escena else "nada en %.0f s" % t))
	m.casi(barra.value / barra.max_value, 1.0, 0.001, "la barra acaba llena")
	await arbol.process_frame
	m.comprobar(not pantalla.visible, "sin cambiar de escena la pantalla se quita al tenerla")
	partida.disconnect("cargada", avisar)
	partida.set("cambiar_escena", true)


## La intro del arranque: el nombre grande sobre negro, que se encoge hasta su sitio mientras el negro
## se abre desde él. En la batería no sale sola (el menú no es la escena actual): se pide a mano.
## Mientras dura tapa los botones, y una tecla la salta.
static func _intro(m: MarcoPruebas, arbol: SceneTree) -> void:
	var menu := await _montar(arbol)
	m.comprobar(menu.find_child("Intro", true, false) == null, "montado en la batería no hay intro")
	if not m.comprobar(menu.has_method("reproducir_intro"), "el menú tiene intro"):
		_desmontar(menu)
		return
	var titulo := menu.find_child("Titulo", true, false) as Control
	var final := titulo.get_global_rect()
	menu.call("reproducir_intro")
	await arbol.process_frame
	var intro := menu.find_child("Intro", true, false) as Control
	var nombre := menu.find_child("TituloIntro", true, false) as Control
	if not m.comprobar(intro != null and intro.is_visible_in_tree() and nombre != null,
			"la intro se ve con su nombre"):
		_desmontar(menu)
		return
	# Las letras solas llegan en una generación aparte: mientras no estén, la intro usa el título.
	var letras := "res://assets/textures/ui/titulo_letras.png"
	var espera := letras if ResourceLoader.exists(letras) else String(titulo.get("texture").resource_path)
	m.comprobar((nombre as TextureRect).texture != null
		and (nombre as TextureRect).texture.resource_path == espera,
		"la intro usa las letras solas si están (y si no, el título)", espera.get_file())
	var negro := intro.find_child("Negro", true, false) as ColorRect
	m.comprobar(negro != null and negro.material == null and is_equal_approx(negro.color.a, 1.0),
		"empieza en negro y se ilumina entero, sin círculo")
	m.comprobar(not titulo.is_visible_in_tree() or titulo.modulate.a < 0.01,
		"durante la intro el título del menú no se ve")
	m.comprobar(intro.mouse_filter == Control.MOUSE_FILTER_STOP, "la intro tapa los botones")
	var centro_pantalla: Vector2 = menu.get_viewport_rect().get_center()
	m.menor_que(nombre.get_global_rect().get_center().distance_to(centro_pantalla), 2.0,
		"el nombre empieza en el centro de la pantalla")
	m.mayor_que(nombre.get_global_rect().size.x, final.size.x * 1.3, "y más grande que al final")
	var duracion: float = menu.get("DURACION_INTRO") + menu.get("TOPE_QUIETUD")
	await arbol.create_timer(duracion + 0.3).timeout
	m.comprobar(not is_instance_valid(intro) or not intro.is_inside_tree(), "al acabar la intro se va")
	m.comprobar(titulo.is_visible_in_tree() and titulo.get_global_rect().is_equal_approx(final),
		"y el título queda en su sitio", str(titulo.get_global_rect()))
	menu.call("reproducir_intro")
	await arbol.process_frame
	await _tecla(arbol, KEY_SPACE)
	m.comprobar(menu.find_child("Intro", true, false) == null and titulo.is_visible_in_tree(),
		"una tecla salta la intro")
	# Con portada: la imagen del arranque sigue encima los segundos que falten hasta los 5.
	m.casi(float(menu.get("PORTADA_SEGUNDOS")), 5.0, 0.001, "la portada dura 5 s (lo pidió el usuario)")
	menu.call("reproducir_intro", 1.0)
	await arbol.process_frame
	var portada := menu.find_child("Portada", true, false) as TextureRect
	m.comprobar(portada != null and portada.is_visible_in_tree() and portada.texture != null
		and portada.texture.resource_path == arranque_imagen(), "la intro empieza con la portada del arranque")
	await arbol.create_timer(duracion + 1.0 + 0.6).timeout
	m.comprobar(menu.find_child("Intro", true, false) == null and titulo.is_visible_in_tree(),
		"y tras la portada sigue la intro hasta el final")
	menu.call("reproducir_intro", 1.0)
	await arbol.process_frame
	await _tecla(arbol, KEY_SPACE)
	m.comprobar(menu.find_child("Intro", true, false) == null and titulo.is_visible_in_tree(),
		"una tecla salta la intro")
	_desmontar(menu)


## La pantalla de carga espera a las islas: `GestorTierra.al_dia()` dice si ya está puesto todo lo
## que toca alrededor del barco —el detalle cercano y las siluetas hasta el horizonte— y no queda
## nada pedido ni a medio meter. Se comprueba contando, celda a celda, lo que falta cuando lo dice.
static func _islas(m: MarcoPruebas, arbol: SceneTree) -> void:
	var g := arbol.get_first_node_in_group("tierra")
	if not m.comprobar(g != null and g.has_method("al_dia"), "el gestor de tierra dice si está al día"):
		return
	var t := 0.0
	while not g.call("al_dia") and t < 60.0:
		await arbol.process_frame
		t += arbol.root.get_process_delta_time()
	m.comprobar(g.call("al_dia"), "se pone al día", "%.1f s" % t)
	var rel = g.get("relieve")
	var f: Node3D = g.call("foco_actual")
	var gp: Vector3 = Origen.a_global(f.global_position)
	var p := Vector2(gp.x, gp.z)
	var lado: float = rel.get("celda")
	var c0: Vector2i = rel.call("celda_de", p)
	var faltan_detalle := 0
	var faltan_silueta := 0
	var r := int(ceil(float(g.get("distancia_silueta")) / lado))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := c0 + Vector2i(dx, dz)
			if not rel.call("tiene", c):
				continue
			var esquina := Vector2(c.x, c.y) * lado
			var d := (p - p.clamp(esquina, esquina + Vector2.ONE * lado)).length()
			if d <= float(g.get("distancia_carga")) and g.call("estado_celda", c) != "cargada":
				faltan_detalle += 1
			if d <= float(g.get("distancia_silueta")) and g.call("silueta_celda", c) == null 					and g.call("estado_celda", c) != "cargada":
				faltan_silueta += 1
	m.comprobar(faltan_detalle == 0, "al día no falta detalle cerca", str(faltan_detalle))
	m.comprobar(faltan_silueta == 0, "al día no falta ninguna silueta", str(faltan_silueta))
