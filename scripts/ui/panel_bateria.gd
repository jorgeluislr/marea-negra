class_name PanelBateria
extends Control

## La batería sobre la silueta del barco, proa arriba, solo en modo batalla: cada cañón en el sitio
## que ocupa en cubierta, con su anillo de carga, la banda apuntada marcada en rojo y la munición
## que queda.
##
## Las marcas se colocan con la posición REAL de cada pieza en ejes del barco, así que valen para
## cualquier casco y cualquier número de cañones. Se rehacen cuando cambia el barco o sus piezas.

const LADO_MARCA := 34.0

@export var icono_canon: Texture2D

var barco: Node:
	set(v):
		barco = v
		_contorno = EstiloHud.contorno(v) if v != null else PackedVector2Array()
		_rehacer()

var _contorno := PackedVector2Array()
var _marcas: Array[MarcaCanon] = []
var _banda := ""
## El tipo de munición que está pintando el panel ahora mismo («rasa», «palanqueta», «metralla»).
## Se expone para que la prueba lea lo mismo que se ve.
var municion_mostrada := ""
## Icono de cada tipo. Los de palanqueta y metralla los dará Meshy (prompts en
## `fuentes/prompts_meshy.md`, «Iconos de munición»); hasta entonces se carga el que haya en
## `assets/textures/ui/icono_<tipo>.png` y, si no hay, el icono pinta el nombre abreviado.
var _iconos := {}

@onready var _municion := $Municion as Label
@onready var _balas := get_node_or_null(^"Balas") as Label
@onready var _icono_municion := get_node_or_null(^"IconoMunicion")


func _ready() -> void:
	resized.connect(_rehacer)


func marcas() -> Array[MarcaCanon]:
	return _marcas


func _process(_delta: float) -> void:
	visible = barco != null and bool(barco.get("modo_battle"))
	if not visible:
		return
	if _piezas().size() != _marcas.size():
		_rehacer()
	_municion.text = str(int(barco.get("municion")))
	_mostrar_municion(str(barco.get("municion_actual")) if "municion_actual" in barco else "rasa")
	var banda := str(barco.get("banda_apuntada"))
	if banda != _banda:
		_banda = banda
		queue_redraw()


func _mostrar_municion(tipo: String) -> void:
	if tipo == municion_mostrada:
		return
	municion_mostrada = tipo
	if _balas != null:
		_balas.text = tipo
	if _icono_municion == null:
		return
	if not _iconos.has("rasa"):
		# La pila de balas de la hoja de iconos es la rasa.
		_iconos["rasa"] = _icono_municion.get("icono")
	if not _iconos.has(tipo):
		var ruta := "res://assets/textures/ui/icono_%s.png" % tipo
		_iconos[tipo] = load(ruta) if ResourceLoader.exists(ruta) else null
	_icono_municion.set("icono", _iconos[tipo])
	_icono_municion.call("poner", tipo.left(3).to_upper(), "Q")


func _piezas() -> Array:
	if barco == null or not barco.has_method("canones_de"):
		return []
	var sale: Array = []
	for banda in ["babor", "estribor", "proa", "popa"]:
		sale.append_array(barco.call("canones_de", banda))
	return sale


## Escala y centro del dibujo: la eslora entra a lo alto y la manga a lo ancho, con hueco abajo
## para la munición.
func _encaje() -> Dictionary:
	var lo := INF
	var hi := -INF
	var semi := 0.1
	for p in _contorno:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
		semi = maxf(semi, absf(p.x))
	if is_inf(lo):
		lo = -1.0
		hi = 1.0
	var alto := size.y - 40.0
	var s := minf(alto * 0.92 / (hi - lo), size.x * 0.6 / (semi * 2.0))
	return {"s": s, "zc": (lo + hi) * 0.5, "c": Vector2(size.x * 0.5, alto * 0.5)}


func _a_pantalla(p: Vector2, e: Dictionary) -> Vector2:
	return e["c"] + Vector2(p.x, p.y - e["zc"]) * e["s"]


func _rehacer() -> void:
	if not is_inside_tree():
		return
	for mk in _marcas:
		mk.queue_free()
	_marcas.clear()
	var e := _encaje()
	for c in _piezas():
		var mk := MarcaCanon.new()
		mk.canon = c
		mk.icono = icono_canon
		mk.size = Vector2(LADO_MARCA, LADO_MARCA)
		mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var local: Vector3 = (barco as Node3D).to_local((c as Node3D).global_position)
		mk.position = _a_pantalla(Vector2(local.x, local.z), e) - mk.size * 0.5
		add_child(mk)
		_marcas.append(mk)
	queue_redraw()


func _draw() -> void:
	if _contorno.size() < 3:
		return
	var e := _encaje()
	var pts := PackedVector2Array()
	for p in _contorno:
		pts.append(_a_pantalla(p, e))
	draw_colored_polygon(pts, EstiloHud.PERGAMINO)
	pts.append(pts[0])
	draw_polyline(pts, EstiloHud.LATON, 3.0, true)
	# La banda apuntada: un trazo rojo por fuera del costado de las piezas que van a tirar.
	var lado := 1.0 if _banda == "estribor" else (-1.0 if _banda == "babor" else 0.0)
	if lado != 0.0:
		var tramo := PackedVector2Array()
		for mk in _marcas:
			if mk.canon != null and mk.canon.call("banda") == _banda:
				tramo.append(mk.position + mk.size * 0.5 + Vector2(lado * LADO_MARCA * 0.9, 0))
		if tramo.size() >= 2:
			draw_polyline(tramo, EstiloHud.ROJO_CARTA, 3.0, true)
		elif tramo.size() == 1:
			draw_circle(tramo[0], 4.0, EstiloHud.ROJO_CARTA)
