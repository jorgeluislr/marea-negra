class_name RosaVientos
extends Control

## Rosa de los vientos: la esfera fija con el norte arriba, una aguja con el rumbo del barco y una
## flecha en el borde por donde ENTRA el viento.
##
## Lo que se lee es el giro de las agujas (`AgujaRumbo`, `AgujaViento`), y es lo que comprueba la
## prueba: la aguja es la que se ve, no una variable al lado. La esfera puede ser la imagen de
## Meshy (`esfera`); sin ella se dibuja una provisional.

@export var esfera: Texture2D

var barco: Node

@onready var _aguja := $AgujaRumbo as Control
@onready var _veleta := $AgujaViento as Control
@onready var _lectura := $Lectura as Label


func _ready() -> void:
	resized.connect(_centrar)
	_centrar()


func _centrar() -> void:
	for a in [_aguja, _veleta]:
		a.size = size
		a.position = Vector2.ZERO
		a.pivot_offset = size * 0.5
	queue_redraw()


func _process(_delta: float) -> void:
	var desde := EstiloHud.viento_desde(Viento.direccion)
	_veleta.rotation_degrees = desde
	var txt := "viento del %s" % EstiloHud.cuarta(desde)
	if barco is Node3D:
		var r := EstiloHud.rumbo_de(barco)
		_aguja.rotation_degrees = r
		txt = "rumbo %03d°  ·  %s" % [int(roundf(r)) % 360, txt]
	_lectura.text = txt


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	if esfera != null:
		draw_texture_rect(esfera, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
		return
	draw_circle(c, r, EstiloHud.LATON)
	draw_circle(c, r * 0.9, EstiloHud.PERGAMINO)
	draw_arc(c, r * 0.78, 0.0, TAU, 64, EstiloHud.TINTA_SUAVE, 1.0, true)
	for i in 72:
		var a := deg_to_rad(i * 5.0) - PI * 0.5
		var largo := 0.1 if i % 18 == 0 else (0.06 if i % 2 == 0 else 0.03)
		var u := Vector2(cos(a), sin(a))
		draw_line(c + u * r * 0.9, c + u * r * (0.9 - largo), EstiloHud.TINTA_SUAVE, 1.0, true)
	# Las cuatro puntas cardinales, en tinta clara para que la aguja destaque encima.
	var t := EstiloHud.TINTA_SUAVE
	t.a = 0.35
	for k in 4:
		var a := k * PI * 0.5 - PI * 0.5
		var punta := c + Vector2(cos(a), sin(a)) * r * 0.74
		var l1 := c + Vector2(cos(a + PI * 0.5), sin(a + PI * 0.5)) * r * 0.1
		var l2 := c + Vector2(cos(a - PI * 0.5), sin(a - PI * 0.5)) * r * 0.1
		draw_colored_polygon(PackedVector2Array([punta, l1, c, l2]), t)
	var f := EstiloHud.letra()
	var tam := int(r * 0.17)
	for par in [["N", 0.0], ["E", 90.0], ["S", 180.0], ["O", 270.0]]:
		var a := deg_to_rad(par[1]) - PI * 0.5
		var p := c + Vector2(cos(a), sin(a)) * r * 0.62
		draw_string(f, p + Vector2(-tam * 0.35, tam * 0.35), par[0], HORIZONTAL_ALIGNMENT_LEFT,
			-1, tam, EstiloHud.TINTA)
