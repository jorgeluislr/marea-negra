extends Node
## Gestor de viento global (autoload "Viento").
## Las telas (velas, banderas) leen 'direccion' y 'fuerza' cada frame.
## La dirección está en ESPACIO MUNDO (horizontal); cada tela la convierte a su
## espacio local, así el ondeo es coherente aunque el barco gire.

@export var direccion_base := Vector3(1.0, 0.0, 0.3)  # hacia dónde sopla (se normaliza)
@export var fuerza_base := 1.0
@export_range(0.0, 1.0) var variacion_fuerza := 0.45  # profundidad de las ráfagas
@export_range(0.0, 1.0) var bamboleo_dir := 0.12      # oscilación de la dirección (rad)

var direccion := Vector3(1, 0, 0)
var fuerza := 1.0
var _t := 0.0


func _ready() -> void:
	direccion = direccion_base.normalized()


func _process(delta: float) -> void:
	_t += delta
	# Ráfagas: la fuerza sube y baja con varias frecuencias superpuestas.
	var g := 0.5 * sin(_t * 0.7) + 0.3 * sin(_t * 1.9 + 1.0) + 0.2 * sin(_t * 3.3)
	fuerza = maxf(0.0, fuerza_base * (1.0 + variacion_fuerza * g))
	# La dirección bambolea suavemente alrededor de la base (la brisa cambia).
	var base := direccion_base.normalized()
	var ang := bamboleo_dir * sin(_t * 0.5)
	direccion = base.rotated(Vector3.UP, ang)
