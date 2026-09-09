extends Node
## Gestor de viento global (autoload "Viento").
## Las telas (velas, banderas) leen 'direccion' y 'fuerza' cada frame.
## La dirección está en ESPACIO MUNDO (horizontal); cada tela la convierte a su
## espacio local, así el ondeo es coherente aunque el barco gire.

@export var direccion_base := Vector3(1.0, 0.0, 0.3)  # hacia dónde sopla (se normaliza)
@export var fuerza_base := 1.0
@export_range(0.0, 1.0) var variacion_fuerza := 0.45  # profundidad de las ráfagas
@export_range(0.0, 1.0) var bamboleo_dir := 0.12      # oscilación de la dirección (rad)

## Velocidad del viento en m/s cuando `fuerza` vale 1. No se usa para empujar nada —de eso se
## encargan `empuje_viento` de cada tela y la polar del casco— sino para poder calcular el
## VIENTO APARENTE, que necesita las dos velocidades en las mismas unidades.
##
## **Tiene que ser MAYOR que la velocidad máxima del barco** (`Barco.velocidad_max`, hoy 12 m/s),
## y por eso vale 16 y no los 8 con los que nació. Con 8, un barco corriendo en popa a 9 m/s daba
## un aparente NEGATIVO —sopla más despacio de lo que corre el barco— y la bandera se orientaba
## 180° al revés que su propio paño: medido, 160,6° entre el hueso y la tela, que es lo que se
## veía como una bandera atascada que no daba la vuelta al mástil. Con 16, 21,6°. Y no es solo un
## número que cuadre: un velero **no puede correr más que el viento en popa**, así que un aparente
## invertido en esa situación es imposible en el mar y solo podía salir de este desajuste.
@export var velocidad_m_s := 16.0

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


## Viento APARENTE que siente algo que se mueve a `velocidad`: el real menos su propia marcha.
##
## Una bandera, una veleta o una vela de un barco en movimiento se orientan al aparente, no al
## real. Con el barco a 8-10 m/s y el viento de través la diferencia llega a 50°, que es
## justo lo que se veía como "la bandera no termina de rotar": el paño ya iba al aparente —lo
## consigue solo, porque el `SoftBody` viaja por el mundo y su arrastre lo alinea— y el hueso
## apuntaba al real.
func aparente(velocidad: Vector3) -> Vector3:
	return direccion.normalized() * (fuerza * velocidad_m_s) - velocidad
