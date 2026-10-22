class_name Corredera
extends Control

## La velocidad del barco en nudos, en un círculo de latón al lado de la cartela. Se llama como el
## instrumento con que se medía: la corredera de barquilla, la del cordel con nudos.

@export var fondo: Texture2D

var barco: Node

@onready var _nudos := $Nudos as Label


func _ready() -> void:
	resized.connect(queue_redraw)


func _process(_delta: float) -> void:
	if barco == null:
		_nudos.text = ""
		return
	var v := absf(float(barco.get("velocidad"))) * EstiloHud.NUDOS_POR_M_S
	_nudos.text = ("%.1f" % v).replace(".", ",")


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	if fondo != null:
		draw_texture_rect(fondo, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
		return
	draw_circle(c, r, EstiloHud.LATON)
	draw_circle(c, r * 0.86, EstiloHud.PERGAMINO)
