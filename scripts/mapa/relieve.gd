class_name Relieve
extends Resource

## Las alturas del Caribe por celdas de 1 km: tierra y fondo, una sola fuente.
##
## Es DATO, como `Isla` y `Archipielago`; quien lo dibuja es `GestorTierra`. Lo genera
## `blender_src/relieve_caribe.py` en `carpeta`: un `c_<cx>_<cz>.alt` por celda (251 × 251 alturas en
## float16, gzip, 4 m entre ellas, el borde compartido con la vecina), un `indice.json` con las celdas
## que tienen algo y `basto.bin` con una versión de 26 × 26 de cada una para las siluetas lejanas.
## Las celdas que son solo fondo no están: ahí no hay nada que dibujar ni en qué varar.
##
## `altura_en()` responde para cualquier punto del mundo, en metros sobre el agua en reposo
## (negativo es fondo): es la batimetría que leerán el oleaje somero y el barco al encallar.
##
## Se lee desde HILOS (el índice al arrancar, cada celda al acercarse el barco), así que lo que se
## comparte va con un `Mutex`.

## Dónde están los ficheros. Ojo al exportar: no son recursos de Godot, el filtro de exportación
## tiene que incluir `*.alt`, `*.bin` y `*.json` de esta carpeta.
@export_dir var carpeta := "res://assets/islas/relieve"
## Fondo que se da fuera de las celdas, en metros: el tope de profundidad del generador.
@export var fondo := -40.0
## Metros de juego por metro REAL de relieve. Las celdas de dos capas (las de los mapas de altura
## reales) guardan la playa y el fondo en metros de juego y el relieve en metros reales, y aquí se
## componen: `base + escala_vertical · relieve`. Cambiarla no obliga a regenerar nada. Las celdas
## antiguas, de una capa, traen la escala ya aplicada (1/8) y no la siguen. 1/12, IGUAL que la
## escala en planta (`Archipielago.escala`): las pendientes son las reales, sin exagerar. Elegido
## por el usuario el 23-10-2026 tras comparar fotos (`tools/foto_relieve.tscn`).
@export var escala_vertical := 1.0 / 12.0

var celda := 1000.0
var paso := 4.0
var lado := 251
var basto := 10
var lado_basto := 26

var _indice := {}            # Vector2i -> Vector2i(byte en basto.bin, capas)
var _bastos := PackedByteArray()
var _cache := {}             # Vector2i -> PackedFloat32Array, las últimas leídas
var _orden_cache: Array[Vector2i] = []
var _listo := false
var _mutex := Mutex.new()

const CACHE_MAX := 24


## Lee el índice y las siluetas bastas. Para llamarlo desde un hilo: son unos cientos de KB.
func cargar() -> void:
	var texto := FileAccess.get_file_as_string(carpeta + "/indice.json")
	var d = JSON.parse_string(texto)
	if d == null:
		push_warning("Relieve: no hay índice en %s" % carpeta)
		return
	celda = float(d["celda"])
	paso = float(d["paso"])
	lado = int(d["lado"])
	basto = int(d["basto"])
	lado_basto = (lado - 1) / basto + 1
	var indice := {}
	var pos := 0
	for e in d["celdas"]:
		var capas := int(e.get("capas", 1))
		indice[Vector2i(int(e["c"][0]), int(e["c"][1]))] = Vector2i(pos, capas)
		pos += lado_basto * lado_basto * 2 * capas
	var bastos := FileAccess.get_file_as_bytes(carpeta + "/basto.bin")
	_mutex.lock()
	_indice = indice
	_bastos = bastos
	_listo = true
	_mutex.unlock()


func listo() -> bool:
	return _listo


func celdas() -> int:
	return _indice.size()


## Celda en la que cae el punto `p` (mundo, x z).
func celda_de(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / celda), floori(p.y / celda))


func tiene(c: Vector2i) -> bool:
	return _indice.has(c)


## Las 251 × 251 alturas de la celda, fila a fila (z) y columna (x). Lento: para un hilo.
func leer(c: Vector2i) -> PackedFloat32Array:
	_mutex.lock()
	var guardada: Variant = _cache.get(c)
	_mutex.unlock()
	if guardada != null:
		return guardada
	var r := PackedFloat32Array()
	if not tiene(c):
		return r
	var crudo := FileAccess.get_file_as_bytes("%s/c_%d_%d.alt" % [carpeta, c.x, c.y])
	var datos := crudo.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	r = _componer(datos, 0, lado * lado, (_indice[c] as Vector2i).y)
	_mutex.lock()
	_cache[c] = r
	_orden_cache.append(c)
	if _orden_cache.size() > CACHE_MAX:
		_cache.erase(_orden_cache.pop_front())
	_mutex.unlock()
	return r


## La versión basta de la celda (26 × 26, 40 m entre alturas) para su silueta lejana.
func leer_basto(c: Vector2i) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	if not tiene(c):
		return r
	var e: Vector2i = _indice[c]
	return _componer(_bastos, e.x, lado_basto * lado_basto, e.y)


## Cambia la escala vertical y olvida las celdas ya leídas con la anterior. Lo ya construido en el
## mundo (mallas, colisión) no cambia hasta que la celda se vuelva a cargar.
func poner_escala_vertical(e: float) -> void:
	_mutex.lock()
	escala_vertical = e
	_cache.clear()
	_orden_cache.clear()
	_mutex.unlock()


## `n` alturas desde el byte `desde`: con una capa, tal cual; con dos, base + escala · relieve.
func _componer(datos: PackedByteArray, desde: int, n: int, capas: int) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	r.resize(n)
	if capas < 2:
		for k in n:
			r[k] = datos.decode_half(desde + k * 2)
		return r
	var otra := desde + n * 2
	for k in n:
		r[k] = datos.decode_half(desde + k * 2) + escala_vertical * datos.decode_half(otra + k * 2)
	return r


## Altura del terreno en `p` (mundo, x z): metros sobre el agua en reposo, negativo si es fondo.
func altura_en(p: Vector2) -> float:
	var c := celda_de(p)
	if not tiene(c):
		return fondo
	var h := leer(c)
	var u := (p.x - c.x * celda) / paso
	var v := (p.y - c.y * celda) / paso
	var i := clampi(int(floor(u)), 0, lado - 2)
	var j := clampi(int(floor(v)), 0, lado - 2)
	var fx := clampf(u - i, 0.0, 1.0)
	var fz := clampf(v - j, 0.0, 1.0)
	var a := lerpf(h[j * lado + i], h[j * lado + i + 1], fx)
	var b := lerpf(h[(j + 1) * lado + i], h[(j + 1) * lado + i + 1], fx)
	return lerpf(a, b, fz)
