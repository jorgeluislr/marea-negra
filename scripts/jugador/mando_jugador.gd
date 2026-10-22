class_name MandoJugador
extends Node

## Traduce teclado y ratón en ÓRDENES para el barco del que cuelga. Es "el jugador al timón".
##
## Existe porque `Barco` no debe leer el teclado: `Input.is_key_pressed` y `_unhandled_input`
## son globales, así que con dos barcos en el agua los dos obedecían la misma tecla. Medido con
## `tools/quien_obedece.tscn` antes del cambio: dos balandras giraban **+26,21° las dos**,
## idénticos a la centésima — no es que se parecieran, es que leían la misma entrada. Y fallaba
## por triplicado (timón, velas y cañones), porque salía de sitios distintos.
##
## Con el mando aquí no puede repetirse: sólo hay un jugador y está en un barco. Un capitán de
## IA se cuelga igual del suyo y llama a los mismos métodos, sin tocar el teclado.
##
## El vocabulario del barco es: `orden_timon`, `set_vela_delantera/trasera`, `set_ancla`,
## `apuntar`, `apuntar_fino` y `disparar_banda`.
##
## La navegación rápida (`Travesia`, con la T) también es del jugador y no del barco: cuelga de
## aquí como hijo "Travesia".

# ── Maniobra ─────────────────────────────────────────────────────────────────
@export var tecla_babor_timon := KEY_A
@export var tecla_estribor_timon := KEY_D
@export var tecla_vela_delantera := KEY_W
@export var tecla_vela_trasera := KEY_S
@export var tecla_ancla := KEY_SPACE
## Navegación rápida: ×1 → ×2 → ×4 → ×1.
@export var tecla_travesia := KEY_T

# ── Artillería ───────────────────────────────────────────────────────────────
## MODO BATTLE: enciende los controles de artillería, la guía de tiro y el apuntado con ratón.
## Fuera de él las flechas y el clic no tocan los cañones, para no disparar mientras se maniobra.
@export var tecla_battle := KEY_B
## Cambia la munición de la batería: rasa → palanqueta → metralla. Solo en modo batalla.
@export var tecla_municion := KEY_Q
## Las flechas eligen batería: arriba proa, abajo popa, izquierda babor, derecha estribor.
@export var tecla_proa := KEY_UP
@export var tecla_popa := KEY_DOWN
@export var tecla_babor := KEY_LEFT
@export var tecla_estribor := KEY_RIGHT
## Grados por píxel de ratón, a los lados y en elevación.
@export var punteria_lateral := 0.12
@export var punteria_elevacion := 0.06

var _barco: Barco
var _travesia: Travesia


func _ready() -> void:
	_barco = get_parent() as Barco
	if _barco == null:
		push_warning("MandoJugador: tiene que colgar de un Barco")
		set_process_unhandled_input(false)
		set_physics_process(false)
		return
	_travesia = Travesia.new()
	_travesia.name = "Travesia"
	_travesia.barco = _barco
	add_child(_travesia)


## Con el personaje andando por cubierta el mando calla: el WASD es suyo para moverse.
func _mandando() -> bool:
	return _barco != null and bool(_barco.gobierno)


func _physics_process(_delta: float) -> void:
	if not _mandando():
		_barco.orden_timon = 0.0
		return
	_barco.orden_timon = (float(Input.is_key_pressed(tecla_babor_timon))
		- float(Input.is_key_pressed(tecla_estribor_timon)))


func _unhandled_input(event: InputEvent) -> void:
	if not _mandando():
		return
	if event is InputEventMouseMotion and _barco.modo_battle:
		# El botón DERECHO es el de girar la cámara y sigue mandando: mientras se sostiene, el
		# ratón no apunta.
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			var rel := (event as InputEventMouseMotion).relative
			_barco.apuntar_fino(rel.x * punteria_lateral, -rel.y * punteria_elevacion)
		return
	if event is InputEventMouseButton and event.pressed and _barco.modo_battle:
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var n := _barco.disparar_banda()
			if n > 0:
				print("%s: fuego de %s, %d piezas, quedan %d balas"
					% [_barco.nombre, _barco.banda_apuntada, n, _barco.municion])
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).keycode
	match k:
		tecla_vela_delantera:
			_barco.set_vela_delantera(not _barco.vela_delantera)
		tecla_vela_trasera:
			_barco.set_vela_trasera(not _barco.vela_trasera)
		tecla_ancla:
			_barco.set_ancla(not _barco.anclado)
		tecla_travesia:
			_travesia.siguiente()
		tecla_battle:
			_barco.modo_battle = not _barco.modo_battle
			print("%s: modo battle %s (%d balas)"
				% [_barco.nombre, "ON" if _barco.modo_battle else "OFF", _barco.municion])
		_:
			if not _barco.modo_battle:
				return
			match k:
				tecla_proa: _barco.apuntar("proa")
				tecla_popa: _barco.apuntar("popa")
				tecla_babor: _barco.apuntar("babor")
				tecla_estribor: _barco.apuntar("estribor")
				tecla_municion:
					_barco.municion_actual = Municion.siguiente(_barco.municion_actual)
					print("%s: cargando %s (%d)" % [_barco.nombre, _barco.municion_actual,
						_barco.municion])
				_:
					return
	get_viewport().set_input_as_handled()
