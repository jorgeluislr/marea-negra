extends PanelContainer
## Menú de ajustes: lo abren el menú principal y el de pausa (`Partida`), los dos con esta misma
## escena (`scenes/ui/menu_ajustes.tscn`).
##
## Cada mando escribe en `Ajustes` con su `set_*`, que lo guarda en `user://ajustes.cfg` y avisa por
## su señal a quien lo use: la música sube o baja en vivo y el capitán lee la dificultad en cada
## decisión, así que cambiarla en pausa vale para la batalla en curso.
##
## **Para añadir un ajuste:** su variable, su `set_*` y su clave en `Ajustes.guardar()`/`cargar()`;
## aquí, un rótulo y el mando en la sección que le toque de la escena, y en `_ready` conectarlo a su
## `set_*`; en `refrescar()`, leerlo. Las pruebas están en `tests/menu_test.gd`.
##
## Esc o Volver cierran el menú y emiten `cerrado`; quien lo abrió vuelve a lo suyo.

signal cerrado

## Botón de cada nivel de `Ajustes.DIFICULTADES`.
const BOTON_DIFICULTAD := {"facil": "Facil", "normal": "Normal", "dificil": "Dificil"}

@onready var _volumen: HSlider = %Volumen


func _ready() -> void:
	theme = TemaMenu.crear()
	for l in [%Seccion1, %Seccion2]:
		(l as Label).add_theme_font_size_override("font_size", 18)
		(l as Label).add_theme_color_override("font_color", EstiloHud.ROJO_CARTA)
	for l in [%RotuloDificultad, %RotuloMusica]:
		(l as Label).add_theme_color_override("font_color", EstiloHud.TINTA_SUAVE)
		(l as Label).add_theme_font_size_override("font_size", 18)
	%Rotulo.add_theme_font_size_override("font_size", 30)
	var grupo := ButtonGroup.new()
	for nivel in BOTON_DIFICULTAD:
		var b := find_child(BOTON_DIFICULTAD[nivel]) as Button
		b.toggle_mode = true
		b.button_group = grupo
		b.pressed.connect(Ajustes.set_dificultad.bind(nivel))
	_volumen.value_changed.connect(Ajustes.set_volumen_musica)
	%Volver.pressed.connect(cerrar)
	visibility_changed.connect(func():
		if visible:
			refrescar())
	refrescar()


## Pone cada mando en el valor que tiene ahora `Ajustes`, sin escribir nada.
func refrescar() -> void:
	for nivel in BOTON_DIFICULTAD:
		(find_child(BOTON_DIFICULTAD[nivel]) as Button).set_pressed_no_signal(Ajustes.dificultad == nivel)
	_volumen.set_value_no_signal(Ajustes.volumen_musica)


func abrir() -> void:
	show()
	(find_child(BOTON_DIFICULTAD[Ajustes.dificultad]) as Button).grab_focus()


func cerrar() -> void:
	hide()
	cerrado.emit()


func _unhandled_input(evento: InputEvent) -> void:
	var t := evento as InputEventKey
	if visible and t != null and t.pressed and not t.echo and t.physical_keycode == KEY_ESCAPE:
		cerrar()
		get_viewport().set_input_as_handled()
