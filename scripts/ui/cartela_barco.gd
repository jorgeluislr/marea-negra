class_name CartelaBarco
extends Control

## Cartela de arriba: nombre del barco y su tipo en UNA línea, centrados en el alto del pergamino
## (en dos no caben). Los nudos van aparte, en la `Corredera`.
##
## El tipo se esconde cuando dice lo mismo que el nombre («Balandra», balandra): hasta que cada
## barco tenga nombre propio sería decir dos veces lo mismo.

## El pergamino de Meshy, ya a la escala a la que se ve (`cartela_hud.png`). Se estira en nueve
## parches: las volutas y los medallones de las esquinas quedan a su tamaño y solo el papel del
## centro se alarga.
@export var fondo: Texture2D
@export var margen_fondo := Vector4(44, 34, 44, 34)  ## izquierda, arriba, derecha, abajo, en píxeles

var barco: Node

@onready var _nombre := $Linea/Nombre as Label
@onready var _tipo := $Linea/Tipo as Label


func _ready() -> void:
	resized.connect(queue_redraw)


func _process(_delta: float) -> void:
	if barco == null:
		_nombre.text = ""
		_tipo.text = ""
		return
	_nombre.text = str(barco.get("nombre"))
	_tipo.text = str(barco.get("tipo"))
	_tipo.visible = _tipo.text.to_lower() != _nombre.text.to_lower()


func _draw() -> void:
	if fondo != null:
		var sb := StyleBoxTexture.new()
		sb.texture = fondo
		sb.texture_margin_left = margen_fondo.x
		sb.texture_margin_top = margen_fondo.y
		sb.texture_margin_right = margen_fondo.z
		sb.texture_margin_bottom = margen_fondo.w
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		return
	var h := size.y
	var punta := h * 0.3
	var banda := PackedVector2Array([Vector2(punta, 0), Vector2(size.x - punta, 0),
		Vector2(size.x, h * 0.5), Vector2(size.x - punta, h), Vector2(punta, h), Vector2(0, h * 0.5)])
	draw_colored_polygon(banda, EstiloHud.PERGAMINO)
	banda.append(banda[0])
	draw_polyline(banda, EstiloHud.TINTA_SUAVE, 2.0, true)
