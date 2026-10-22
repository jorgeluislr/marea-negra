extends Control
## Menú principal: la escena con la que arranca el juego (`run/main_scene`).
##
## Lanza las cinco escenas que hay, abre los ajustes (`menu_ajustes.tscn`: dificultad del capitán
## de IA, volumen de la música y los que vengan; los guarda `Ajustes` en `user://ajustes.cfg`) y
## sale. Volver aquí desde la partida es cosa del menú de pausa (`Partida`).
##
## Detrás va la balandra fondeada en bucle (`PORTADA`, grabada con `tools/grabar_portada.tscn`).
## El vídeo no va al repositorio: si falta, queda el fondo liso y el menú funciona igual.
##
## **La intro**, al abrir el juego: la portada del arranque (la imagen de `boot_splash`) sigue encima
## hasta cumplir `PORTADA_SEGUNDOS` desde que se abrió el juego, y luego el nombre grande sobre negro
## —solo las letras (`LETRAS`), sin pergamino, si están— que se encoge hasta su sitio mientras el
## menú se ilumina desde el negro; al final el pergamino del título aparece debajo de las letras. Una sola vez por sesión (`Partida.intro_vista`), y una tecla o un clic la
## saltan. Montado dentro de otra escena —la batería— no sale sola: `reproducir_intro()`.
##
## Con `cambiar_escena` a false los botones solo AVISAN (`escena_pedida`, `salir_pedido`): es lo
## que usan las pruebas (`tests/menu_test.gd`) para no tirar la batería.

signal escena_pedida(ruta: String)
signal salir_pedido

## Cada botón y la escena que abre.
const ESCENAS := {
	"Navegar": "res://scenes/world/main_world.tscn",
	"BatallaRapida": "res://scenes/world/escaramuza.tscn",
	"TiroAlBlanco": "res://scenes/world/combate.tscn",
	"DueloCapitanes": "res://scenes/world/duelo_ia.tscn",
	"Tormenta": "res://scenes/world/tormenta.tscn",
}
const PORTADA := "res://assets/video/portada.ogv"
## Segundos de la intro: aparece el nombre, se queda, y se encoge mientras se abre el negro.
const APARECE := 0.8
const QUIETO := 0.8
const ABRE := 1.8
## Lo que dura la portada desde que se abre el juego (lo pidió el usuario: 5 s aunque cargue antes).
## La alarga el menú y NO `boot_splash/minimum_display_time`: el del motor vale para cualquier escena,
## también la batería, y le retrasaba el primer fotograma hasta desfasar el mar de la física.
const PORTADA_SEGUNDOS := 5.0
## Las letras del título sin el pergamino (generación aparte, `tools/procesar_menu.gd`), colocadas línea
## a línea en el lienzo del título entero sobre sus letras. Si no están, la intro usa el título entero.
const LETRAS := "res://assets/textures/ui/titulo_letras.png"
const FUNDIDO_TITULO := 0.6
const RETIRA_LETRAS := 0.25
const DURACION_INTRO := APARECE + QUIETO + ABRE + FUNDIDO_TITULO + RETIRA_LETRAS
const FUNDIDO_PORTADA := 0.5
## Ancho del nombre al empezar, por el de su sitio final.
const ESCALA_INTRO := 1.7
## La animación no arranca hasta tener estos fotogramas seguidos por debajo de 1/30 s (con tope
## `TOPE_QUIETUD`): el primero del menú —vídeo, sombreadores— tarda tanto que la saltaba casi entera.
const FOTOGRAMAS_QUIETOS := 6
const TOPE_QUIETUD := 3.0

var cambiar_escena := true

@onready var _fondo: VideoStreamPlayer = %Fondo
var _intro: Control
var _tween: Tween


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_estilo()
	for nombre in ESCENAS:
		(find_child(nombre) as Button).pressed.connect(_abrir.bind(ESCENAS[nombre]))
	%Salir.pressed.connect(_salir)
	%Ajustes.pressed.connect(_ajustes)
	%MenuAjustes.cerrado.connect(func():
		%Panel.show()
		%Ajustes.grab_focus())
	if ResourceLoader.exists(PORTADA):
		_fondo.stream = load(PORTADA)
		_fondo.loop = true
		_fondo.play()
	%Navegar.grab_focus()
	# Un fotograma después: al llegar por `change_scene_to_*` aún no es la escena actual en `_ready`.
	await get_tree().process_frame
	if get_tree().current_scene == self and not Partida.intro_vista:
		reproducir_intro(maxf(PORTADA_SEGUNDOS - Time.get_ticks_msec() / 1000.0, 0.0))


## `portada`: segundos que la imagen del arranque sigue encima antes de la intro.
func reproducir_intro(portada := 0.0) -> void:
	_terminar_intro()
	var final: Rect2 = %Titulo.get_rect()
	var pantalla := get_viewport_rect().size
	var inicio := Rect2(Vector2.ZERO, final.size * ESCALA_INTRO)
	inicio.position = pantalla * 0.5 - inicio.size * 0.5
	_intro = Control.new()
	_intro.name = "Intro"
	_intro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro.mouse_filter = Control.MOUSE_FILTER_STOP
	_intro.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_terminar_intro())
	add_child(_intro)
	var negro := ColorRect.new()
	negro.name = "Negro"
	negro.color = Color.BLACK
	negro.set_anchors_preset(Control.PRESET_FULL_RECT)
	negro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro.add_child(negro)
	var nombre := TextureRect.new()
	nombre.name = "TituloIntro"
	nombre.texture = load(LETRAS) if ResourceLoader.exists(LETRAS) else %Titulo.texture
	nombre.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	nombre.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	nombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nombre.position = inicio.position
	nombre.size = inicio.size
	nombre.modulate.a = 0.0
	_intro.add_child(nombre)
	var tapa: TextureRect = null
	var imagen := String(ProjectSettings.get_setting("application/boot_splash/image", ""))
	if portada > 0.0 and ResourceLoader.exists(imagen):
		var fondo := ColorRect.new()
		fondo.color = ProjectSettings.get_setting("application/boot_splash/bg_color", Color.BLACK)
		fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
		fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tapa = TextureRect.new()
		tapa.name = "Portada"
		tapa.texture = load(imagen)
		tapa.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tapa.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tapa.set_anchors_preset(Control.PRESET_FULL_RECT)
		tapa.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tapa.add_child(fondo)
		tapa.move_child(fondo, 0)
		fondo.show_behind_parent = true
		_intro.add_child(tapa)
	var fin_portada := Time.get_ticks_msec() + int(portada * 1000.0)
	%Titulo.modulate.a = 0.0
	var intro := _intro
	var buenos := 0
	var t0 := Time.get_ticks_usec()
	var antes := t0
	while buenos < FOTOGRAMAS_QUIETOS and (Time.get_ticks_usec() - t0) < TOPE_QUIETUD * 1e6:
		await get_tree().process_frame
		var ahora := Time.get_ticks_usec()
		buenos = buenos + 1 if ahora - antes < 33333 else 0
		antes = ahora
	if _intro != intro:
		return   # la saltaron mientras esperaba
	var queda := maxf((fin_portada - Time.get_ticks_msec()) / 1000.0, 0.0)
	_tween = create_tween()
	if tapa != null:
		_tween.tween_interval(queda)
		_tween.tween_property(tapa, "modulate:a", 0.0, FUNDIDO_PORTADA)
	_tween.tween_property(nombre, "modulate:a", 1.0, APARECE)
	_tween.tween_interval(QUIETO)
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(nombre, "position", final.position, ABRE)
	_tween.tween_property(nombre, "size", final.size, ABRE)
	# Se ilumina: el negro se aclara despacio al principio, como cuando sube la luz.
	_tween.tween_property(negro, "color:a", 0.0, ABRE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.set_parallel(false)
	# El pergamino del título aparece DEBAJO de las letras, que van colocadas línea a línea sobre las
	# suyas (`tools/procesar_menu.gd`, `LINEAS`); luego las letras sueltas se retiran en un momento.
	_tween.tween_property(%Titulo, "modulate:a", 1.0, FUNDIDO_TITULO)
	_tween.tween_property(nombre, "modulate:a", 0.0, RETIRA_LETRAS)
	_tween.tween_callback(_terminar_intro)


func _terminar_intro() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if _intro != null:
		_intro.queue_free()
		remove_child(_intro)
		_intro = null
		Partida.intro_vista = true
	%Titulo.modulate.a = 1.0


func _unhandled_input(evento: InputEvent) -> void:
	if _intro != null and evento is InputEventKey and evento.pressed:
		_terminar_intro()
		get_viewport().set_input_as_handled()


func _ajustes() -> void:
	%Panel.hide()
	%MenuAjustes.abrir()


func _abrir(ruta: String) -> void:
	escena_pedida.emit(ruta)
	if cambiar_escena:
		Partida.abrir(ruta)


func _salir() -> void:
	salir_pedido.emit()
	if cambiar_escena:
		get_tree().quit()


func _estilo() -> void:
	theme = TemaMenu.crear()
