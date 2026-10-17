class_name Archipielago
extends Resource

## La "base de datos" de islas: la lista de `Isla` del mundo y la rejilla de celdas con que se
## buscan. Un recurso binario en disco (`assets/islas/archipielago.res`), sin nada más.
##
## **El mundo es el Caribe entero a escala 1/25** (decidido con el usuario el 17-10-2026): 122 × 82 km
## de juego, con las costas de OpenStreetMap (`blender_src/costas_caribe.py` las extrae y
## `tools/hornear_islas.tscn` las convierte en este recurso). Escala UNIFORME en planta: con una
## escala para las distancias y otra para las islas, las islas de un mismo grupo —las Vírgenes están
## a 5-10 km reales unas de otras— se pisarían. Las distancias se acortan con la navegación rápida,
## no encogiendo el mar.
##
## La altura va aparte (`escala_altura`), porque a 1/25 un cerro de 130 m se quedaría en 5 m. A 1/8
## Norman Island, de 155 m de largo, sube a 16 m: una isla, no una aguja.
##
## El origen del mundo sigue en el Drake Channel, donde arranca el juego, hasta que haya origen
## flotante: el Caribe mide más de lo que aguanta la precisión simple lejos del origen.

## Islas del mundo.
@export var islas: Array[Isla] = []
## El rectángulo que cubre el mapa, en metros del mundo (x, z). La carta se ajusta a él.
@export var mundo := Rect2(-4000, -4000, 8000, 8000)
## Lado de la celda de la rejilla de búsqueda, en metros.
@export var celda := 1000.0
## Qué punto real cae en el origen del mundo: (latitud, longitud) en grados, oeste negativo.
## Es el centro del Sir Francis Drake Channel, entre Tortola y Norman Island.
@export var origen_real := Vector2(18.385, -64.62)
## Metros de mundo por metro real, en planta.
@export var escala := 1.0 / 25.0
## Metros de mundo por metro real, en altura. Ver la nota de arriba.
@export var escala_altura := 1.0 / 8.0
## De dónde salen las costas, para citarlo (ODbL).
@export var fuente := ""

var _indice := {}


## Celda de la rejilla en la que cae el punto `p` (mundo, x z).
func celda_de(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / celda), floori(p.y / celda))


## Islas que tocan la celda `c`.
func islas_en_celda(c: Vector2i) -> Array[Isla]:
	if _indice.is_empty():
		_indexar()
	var r: Array[Isla] = []
	for i in _indice.get(c, []):
		r.append(islas[i])
	return r


## Islas cuyo rectángulo queda a menos de `radio` metros de `p`. Recorre solo las celdas que
## alcanza el radio, que es para lo que está la rejilla.
func islas_cerca(p: Vector2, radio: float) -> Array[Isla]:
	if _indice.is_empty():
		_indexar()
	var r: Array[Isla] = []
	var a := celda_de(p - Vector2(radio, radio))
	var b := celda_de(p + Vector2(radio, radio))
	var vistas := {}
	for cx in range(a.x, b.x + 1):
		for cz in range(a.y, b.y + 1):
			for i in _indice.get(Vector2i(cx, cz), []):
				if vistas.has(i):
					continue
				vistas[i] = true
				if islas[i].distancia_a(p) <= radio:
					r.append(islas[i])
	return r


## Lleva una coordenada real (grados, oeste negativo) al mundo, en (x, z). El norte es −Z.
##
## Equirrectangular centrada en `origen_real`: en 50 km de archipiélago el error frente a la
## esfera es de metros reales, centímetros de mundo.
func de_lat_lon(lat: float, lon: float) -> Vector2:
	const M_POR_GRADO := 111320.0
	var este := (lon - origen_real.y) * M_POR_GRADO * cos(deg_to_rad(origen_real.x))
	var norte := (lat - origen_real.x) * M_POR_GRADO
	return Vector2(este, -norte) * escala


func _indexar() -> void:
	_indice.clear()
	for i in islas.size():
		var r := islas[i].limites()
		var a := celda_de(r.position)
		var b := celda_de(r.end)
		for cx in range(a.x, b.x + 1):
			for cz in range(a.y, b.y + 1):
				var c := Vector2i(cx, cz)
				if not _indice.has(c):
					_indice[c] = []
				_indice[c].append(i)
