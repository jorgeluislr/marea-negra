extends CanvasLayer
## La partida en curso (autoload "Partida"): abre las escenas del menú y pone el menú de pausa.
##
## **Esc pausa** en cualquier escena que no sea el menú principal y abre Continuar, Ajustes, Menú
## principal y Salir; Esc otra vez, o Continuar, sigue. Los ajustes son los mismos del menú
## principal (`menu_ajustes.tscn`) y valen en vivo; Esc dentro de ellos vuelve a la pausa.
## El ratón se suelta al pausar y vuelve como estaba.
##
## **Los autoloads sobreviven al cambio de escena**, y varias escenas los tocan: la tormenta sube
## el viento a 1,9 y puede dejar el tiempo congelado, la travesía cambia `time_scale` y los Hz de la
## física, el origen flotante acumula desplazamiento y el clima pone el viento de la fecha. Sin
## deshacerlo, navegar después de la tormenta saldría con temporal. Por eso `abrir()` repone antes
## de cada escena lo que traían de fábrica `Viento`, `Oleaje`, `Horizonte` y `Origen` (lo que tenían
## al arrancar, `_fabrica`), y guarda el calendario si la partida lo llevaba.
##
## **La pantalla de carga** tapa el cambio con una imagen AL AZAR de `CARPETA_CARGA` (para añadir
## una, basta con dejarla ahí; el arranque del juego usa una fija, `application/boot_splash/image`,
## porque Godot la enseña antes de que corra ningún script). La
## escena se lee en otro hilo con su barra de progreso, y la pantalla se queda hasta que la escena
## nueva da `ASENTADA` fotogramas seguidos por debajo de 1/30 s (con tope `TOPE_ASIENTO`): los
## primeros fotogramas de un mundo compilan sombreadores y montan telas, y dan tirones que se ven.
##
## Con `cambiar_escena` a false solo AVISA (`escena_pedida`) y `precargar` entrega la escena
## (`cargada`) sin cambiarla: es lo que usan las pruebas.

signal escena_pedida(ruta: String)
signal cargada(escena: PackedScene)

const MENU := "res://scenes/ui/menu_principal.tscn"
const AJUSTES := "res://scenes/ui/menu_ajustes.tscn"
const CARPETA_CARGA := "res://assets/textures/ui/carga/"
const ASENTADA := 10
const TOPE_ASIENTO := 40.0
## Lo que se ve donde no llega la imagen: el azul del mar de abajo. Es también el `bg_color` del
## arranque (`application/boot_splash/bg_color`), para que las dos pantallas sean la misma.
const COLOR_CARGA := Color(0.04, 0.08, 0.11)
const RESTAURAR := [^"/root/Viento", ^"/root/Oleaje", ^"/root/Horizonte", ^"/root/Origen"]

var cambiar_escena := true
## Si ya se vio la intro del menú en esta sesión: al volver de una partida no se repite.
var intro_vista := false

var _panel: Control
var _caja: Control
var _ajustes: Control
var _raton_antes := Input.MOUSE_MODE_VISIBLE
## Por autoload, sus variables exportadas tal como estaban al arrancar.
var _fabrica := {}
var _hz_fisica := 60
var _carga: Control
var _progreso: ProgressBar
var _rotulo: Label
var _imagen: TextureRect
var _lados: TextureRect
## La escena que se está leyendo, o "" si no se lee ninguna.
var _leyendo := ""
## Mientras la escena nueva se asienta: fotogramas buenos seguidos, segundos y reloj del anterior.
var _asentando := false
var _buenos := 0
var _asiento := 0.0
var _usec := 0


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hz_fisica = Engine.physics_ticks_per_second
	for ruta in RESTAURAR:
		var n := get_node_or_null(ruta)
		if n == null:
			continue
		var valores := {}
		for p in n.get_property_list():
			if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and p["usage"] & PROPERTY_USAGE_STORAGE:
				valores[p["name"]] = n.get(p["name"])
		_fabrica[ruta] = valores
	_montar_panel()
	_montar_carga()


func _unhandled_input(evento: InputEvent) -> void:
	var t := evento as InputEventKey
	if t == null or not t.pressed or t.echo or t.physical_keycode != KEY_ESCAPE:
		return
	var escena := get_tree().current_scene
	if escena != null and escena.scene_file_path == MENU:
		return
	pausar(not _panel.visible)
	get_viewport().set_input_as_handled()


func en_pausa() -> bool:
	return _panel.visible


func pausar(si: bool) -> void:
	if si == _panel.visible:
		return
	_ajustes.hide()
	_caja.show()
	if si:
		_raton_antes = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = _raton_antes
	_panel.visible = si
	get_tree().paused = si
	if si:
		(_panel.find_child("Continuar", true, false) as Button).grab_focus()


## Va a una escena desde el menú o desde la pausa, con los autoloads como al arrancar.
func abrir(ruta: String) -> void:
	escena_pedida.emit(ruta)
	_panel.visible = false
	get_tree().paused = false
	if cambiar_escena:
		precargar(ruta)


## Las imágenes de carga que hay en `CARPETA_CARGA`.
func pantallas() -> Array:
	var hay := []
	for f in ResourceLoader.list_directory(CARPETA_CARGA):
		if f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			hay.append(CARPETA_CARGA + f)
	hay.sort()
	return hay


## Enseña la pantalla de carga y lee la escena en otro hilo; al tenerla, la abre (o solo la
## entrega por `cargada` si `cambiar_escena` es false).
func precargar(ruta: String) -> void:
	_progreso.value = 0.0
	_rotulo.text = "Cargando…"
	var hay := pantallas()
	if not hay.is_empty():
		var t := load(hay.pick_random()) as Texture2D
		_imagen.texture = t
		_lados.texture = t
	_carga.show()
	_asentando = false
	if ResourceLoader.load_threaded_request(ruta) != OK:
		push_error("Partida: no se puede leer %s" % ruta)
		_carga.hide()
		return
	_leyendo = ruta


func _process(_delta: float) -> void:
	if _leyendo != "":
		_seguir_lectura()
	elif _asentando:
		_seguir_asiento()


func _seguir_lectura() -> void:
	var avance := []
	var estado := ResourceLoader.load_threaded_get_status(_leyendo, avance)
	if not avance.is_empty():
		_progreso.value = float(avance[0])
	if estado == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var ruta := _leyendo
	_leyendo = ""
	if estado != ResourceLoader.THREAD_LOAD_LOADED:
		push_error("Partida: falló la lectura de %s (%d)" % [ruta, estado])
		_carga.hide()
		return
	var escena := ResourceLoader.load_threaded_get(ruta) as PackedScene
	_progreso.value = 1.0
	cargada.emit(escena)
	if not cambiar_escena:
		_carga.hide()
		return
	_reponer()
	get_tree().change_scene_to_packed(escena)
	_asentando = true
	_buenos = 0
	_asiento = 0.0
	_usec = Time.get_ticks_usec()


## Reloj de pared y no `delta`: `delta` va escalado por `time_scale` y topado por el motor.
func _seguir_asiento() -> void:
	var ahora := Time.get_ticks_usec()
	var paso := float(ahora - _usec) / 1e6
	_usec = ahora
	_asiento += paso
	_buenos = _buenos + 1 if paso < 1.0 / 30.0 else 0
	var islas := true
	for g in get_tree().get_nodes_in_group("tierra"):
		if g.has_method("al_dia") and not g.al_dia():
			islas = false
	if not islas:
		_rotulo.text = "Cargando las islas…"
	if (_buenos >= ASENTADA and islas) or _asiento >= TOPE_ASIENTO:
		if _asiento >= TOPE_ASIENTO:
			push_warning("Partida: la escena no se asentó en %.0f s; se quita la carga igual." % TOPE_ASIENTO)
		_asentando = false
		_carga.hide()


func _reponer() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = _hz_fisica
	for ruta in _fabrica:
		var n := get_node_or_null(ruta)
		var valores: Dictionary = _fabrica[ruta]
		for nombre in valores:
			n.set(nombre, valores[nombre])
	Viento.seguir_calendario = false
	if Calendario.persistente:
		Calendario.guardar()
		Calendario.persistente = false
	Origen.reiniciar()
	Oleaje.asentar()


func _montar_panel() -> void:
	_panel = Control.new()
	_panel.name = "Pausa"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.theme = TemaMenu.crear()
	_panel.visible = false
	add_child(_panel)
	var velo := ColorRect.new()
	velo.color = Color(0, 0, 0, 0.45)
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(velo)
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(centro)
	var caja := PanelContainer.new()
	caja.name = "Caja"
	caja.custom_minimum_size = Vector2(440, 0)
	centro.add_child(caja)
	_caja = caja
	_ajustes = (load(AJUSTES) as PackedScene).instantiate()
	_ajustes.hide()
	_ajustes.cerrado.connect(func():
		_caja.show()
		(_caja.find_child("Ajustes", true, false) as Button).grab_focus())
	centro.add_child(_ajustes)
	var lista := VBoxContainer.new()
	lista.add_theme_constant_override("separation", 6)
	caja.add_child(lista)
	var rotulo := Label.new()
	rotulo.text = "En pausa"
	rotulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotulo.add_theme_font_size_override("font_size", 30)
	lista.add_child(rotulo)
	lista.add_child(HSeparator.new())
	for b in [["Continuar", "Continuar", pausar.bind(false)],
			["Ajustes", "Ajustes", _abrir_ajustes],
			["MenuPrincipal", "Menú principal", abrir.bind(MENU)],
			["Salir", "Salir del juego", _salir]]:
		var boton := Button.new()
		boton.name = b[0]
		boton.text = b[1]
		boton.pressed.connect(b[2])
		lista.add_child(boton)


## La imagen entera, sin recortar, y donde no llegue —una pantalla que no sea 16:9— la misma
## ampliada, desenfocada y oscurecida en vez de franjas lisas. Abajo, el rótulo y la barra sobre
## el mar.
func _montar_carga() -> void:
	_carga = Control.new()
	_carga.name = "PantallaCarga"
	_carga.set_anchors_preset(Control.PRESET_FULL_RECT)
	_carga.theme = TemaMenu.crear()
	_carga.mouse_filter = Control.MOUSE_FILTER_STOP
	_carga.visible = false
	add_child(_carga)
	var liso := ColorRect.new()
	liso.color = COLOR_CARGA
	liso.set_anchors_preset(Control.PRESET_FULL_RECT)
	_carga.add_child(liso)
	_lados = TextureRect.new()
	_lados.name = "Lados"
	_lados.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lados.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_lados.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lados.modulate = Color(0.45, 0.45, 0.45)
	_lados.material = ShaderMaterial.new()
	(_lados.material as ShaderMaterial).shader = _desenfoque()
	_carga.add_child(_lados)
	_imagen = TextureRect.new()
	_imagen.name = "Imagen"
	_imagen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_imagen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_imagen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_carga.add_child(_imagen)
	var pie := VBoxContainer.new()
	pie.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	pie.offset_left = -300
	pie.offset_right = 300
	pie.offset_top = -120
	pie.offset_bottom = -48
	pie.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pie.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_carga.add_child(pie)
	var rotulo := Label.new()
	rotulo.name = "Rotulo"
	_rotulo = rotulo
	rotulo.text = "Cargando…"
	rotulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotulo.add_theme_color_override("font_color", EstiloHud.PERGAMINO)
	rotulo.add_theme_color_override("font_outline_color", EstiloHud.TINTA)
	rotulo.add_theme_constant_override("outline_size", 6)
	pie.add_child(rotulo)
	_progreso = ProgressBar.new()
	_progreso.name = "Progreso"
	_progreso.max_value = 1.0
	_progreso.show_percentage = false
	_progreso.custom_minimum_size = Vector2(0, 14)
	_progreso.add_theme_stylebox_override("background",
		TemaMenu.caja(Color(EstiloHud.TINTA, 0.7), EstiloHud.LATON, 2, 0))
	_progreso.add_theme_stylebox_override("fill",
		TemaMenu.caja(EstiloHud.LATON, EstiloHud.LATON, 0, 0))
	pie.add_child(_progreso)


static func _desenfoque() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec4 suma = vec4(0.0);
	for (int i = -3; i <= 3; i++)
		for (int j = -3; j <= 3; j++)
			suma += texture(TEXTURE, UV + vec2(float(i), float(j)) * 0.006);
	COLOR = suma / 49.0 * COLOR;
}
"""
	return sh


func _abrir_ajustes() -> void:
	_caja.hide()
	_ajustes.call("abrir")


func _salir() -> void:
	# El calendario se guarda solo al salir del árbol (`Calendario._notification`).
	get_tree().quit()
