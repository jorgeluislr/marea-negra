extends Node
## Escena de temporal: el mundo de siempre con la mar que se le pida, para ver cómo se comporta
## el casco cuando la ola es grande.
##
##     godot --path . scenes/world/tormenta.tscn
##
## Se juega igual que el mundo normal (es el mismo, instanciado dentro), y encima:
##
## - **1, 2, 3, 4** cambian el estado de la mar: bonanza, fresco, duro, temporal. De "duro" para
##   arriba se arría el trapo, que es lo que se hace en el mar: con el viento a 1,9 —treinta
##   metros por segundo— y toda la vela arriba, la balandra se acuesta 32° y no se levanta
##   (medido con `tools/flotacion.tscn -- 1.9`). Se pueden volver a izar con S cuando se quiera.
## - **5** congela y descongela la mar, para mirar una ola quieta.
## - El panel de arriba a la izquierda dice la mar que hay y lo que el barco está haciendo con
##   ella: cuánto cabecea, cuánto escora y cuánto se separa de la lámina.
##
## **La mar sube sola, con su inercia de siempre (25 s), no de golpe.** Dos razones: es lo que
## hace una mar de verdad —se levanta con el viento y tarda— y, muy en concreto, los paños nacen
## en los primeros frames y necesitan un par de segundos de quietud para asentarse (ver
## `mar.gd`); estrenarles un temporal encima los rompe. Por eso tampoco se llama a
## `Oleaje.asentar()`, que es cosa de herramientas de medida.

const MUNDO := "res://scenes/world/main_world.tscn"

## Estado de la mar: nombre, fuerza del viento, profundidad de las rachas y bamboleo de la
## dirección. La ALTURA no se pone aquí: sale del viento al cuadrado, que es lo que hace
## `Oleaje` con Pierson-Moskowitz. Un solo mando, y la mar y las velas no pueden contradecirse.
const ESTADOS := [
	{"nombre": "bonanza",  "fuerza": 0.35, "rachas": 0.25, "bamboleo": 0.08, "trapo": true},
	{"nombre": "fresco",   "fuerza": 1.00, "rachas": 0.45, "bamboleo": 0.12, "trapo": true},
	{"nombre": "duro",     "fuerza": 1.45, "rachas": 0.55, "bamboleo": 0.16, "trapo": false},
	{"nombre": "temporal", "fuerza": 1.90, "rachas": 0.70, "bamboleo": 0.22, "trapo": false},
]
## Con cuál empieza. El temporal es el 3.
@export var estado_inicial := 3

var _panel: Label
var _estado := 0
var _congelado := false


func _ready() -> void:
	add_child((load(MUNDO) as PackedScene).instantiate())
	_panel = Label.new()
	_panel.position = Vector2(16, 16)
	_panel.add_theme_color_override("font_color", Color(1, 1, 1))
	_panel.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_panel.add_theme_constant_override("outline_size", 6)
	var capa := CanvasLayer.new()
	capa.layer = 10
	capa.add_child(_panel)
	add_child(capa)
	# Un margen antes de tocar nada: el barco se apunta al grupo "barco_activo" cuando el gestor
	# lo elige, y sin esperarlo el trapo no se arriaría porque no hay a quién decírselo.
	await get_tree().create_timer(1.5).timeout
	_poner(clampi(estado_inicial, 0, ESTADOS.size() - 1))


func _unhandled_input(evento: InputEvent) -> void:
	var t := evento as InputEventKey
	if t == null or not t.pressed or t.echo:
		return
	if t.physical_keycode >= KEY_1 and t.physical_keycode <= KEY_4:
		_poner(t.physical_keycode - KEY_1)
	elif t.physical_keycode == KEY_5:
		_congelado = not _congelado
		Engine.time_scale = 0.0 if _congelado else 1.0


func _poner(i: int) -> void:
	_estado = i
	var e: Dictionary = ESTADOS[i]
	Viento.fuerza_base = float(e["fuerza"])
	Viento.variacion_fuerza = float(e["rachas"])
	Viento.bamboleo_dir = float(e["bamboleo"])
	var b := get_tree().get_first_node_in_group("barco_activo")
	if b != null:
		b.call("set_vela_delantera", bool(e["trapo"]))
		b.call("set_vela_trasera", bool(e["trapo"]))
	print("tormenta: mar %s (viento %.2f)%s — la mar tarda unos %.0f s en levantarse"
		% [e["nombre"], e["fuerza"],
			"" if bool(e["trapo"]) else ", trapo arriado", Oleaje.inercia])


func _process(_delta: float) -> void:
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	var txt := "mar: %s   (1-4 cambia, 5 congela)\nviento %.2f -> ola %.2f m de alta" % [
		ESTADOS[_estado]["nombre"], Viento.fuerza, Oleaje.altura]
	if b != null:
		var eu := b.global_transform.basis.get_euler()
		# La separación del casco a su lámina: es el hueco por el que se vería entrar el mar, y
		# la que dice si el modelo aguanta la ola grande o el barco se queda colgando.
		var h: float = Oleaje.altura_en(Vector2(b.global_position.x, b.global_position.z))
		txt += "\ncabeceo %+.1f°   escora %+.1f°\nquilla a %.2f m de la lámina (en reposo %.2f)" % [
			rad_to_deg(eu.x), rad_to_deg(eu.z),
			b.global_position.y - h, float(b.get("altura_flotacion")) - Oleaje.nivel]
	_panel.text = txt
