class_name Isla
extends Resource

## Una isla del archipiélago, como DATO: su nombre, dónde está y su línea de costa.
##
## Es un recurso y no un nodo por la misma razón que `Aparejo`, `Carga` y `AcabadoMadera`: la isla
## no hace nada por sí misma; la pinta `CartaNautica`. El RELIEVE no va aquí: va por celdas de 1 km
## en `Relieve`, una sola fuente para tierra y fondo, porque a 1/25 Cuba ocupa cientos de celdas y
## una isla no es la unidad en que se carga.
##
## **Ejes:** todo en metros, en planta, con el mundo en (x, z). El norte es −Z y el este +X, que es
## como lo lee la carta (`Carta`). `contorno` va relativo a `posicion`.

## Nombre de la isla, el de la carta.
@export var nombre := ""
## Centro de la isla en el mundo, en (x, z).
@export var posicion := Vector2.ZERO
## Línea de costa en ejes de la isla, en metros. La dibuja la carta y de ella sale el relieve.
@export var contorno := PackedVector2Array()

var _limites := Rect2()


## Lo que ocupa la isla en el mundo, en planta: el rectángulo de su costa.
func limites() -> Rect2:
	# Se guarda: la tierra firme tiene once mil puntos y el gestor pregunta cada cuarto de segundo.
	if _limites.size.x <= 0.0 and not contorno.is_empty():
		var r := Rect2(contorno[0] + posicion, Vector2.ZERO)
		for c in contorno:
			r = r.expand(c + posicion)
		_limites = r
	return _limites


## Distancia en planta de `p` (mundo, x z) al rectángulo de la isla; 0 si está dentro.
func distancia_a(p: Vector2) -> float:
	var r := limites()
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dz).length()
