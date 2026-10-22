class_name Salpicadura
extends Node3D

## El penacho de agua donde cae una bala. Se crea en el punto de la OLA (`Oleaje.altura_en`, el
## mismo mar que se dibuja), vive un par de segundos y se borra solo.
##
## Igual que el `Fogonazo`, sin partículas: unos carteles de espuma que suben y caen con la
## gravedad, y un anillo que se abre sobre el agua. Lo que vende una salpicadura es la COLUMNA
## que sube recta y se desploma, no el detalle de las gotas.

@export var vida := 2.2
## Altura de la columna, en metros. La escala la pone quien la crea: un perdigón de metralla
## levanta una pluma pequeña, una rasa una columna de dos metros.
@export var alto := 2.2
@export var gotas := 9

var _t := 0.0
var _carteles: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _vel: Array[Vector3] = []
var _anillo: MeshInstance3D
var _mat_anillo: StandardMaterial3D


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# v² = 2·g·h: la que sube hasta `alto`, repartida entre las gotas.
	var v := sqrt(2.0 * 9.8 * alto)
	for i in gotas:
		var tam := alto * rng.randf_range(0.30, 0.55)
		var m := _cartel(Color(0.93, 0.95, 0.96, 0.85), tam)
		_carteles.append(m)
		_mats.append(m.material_override as StandardMaterial3D)
		var abre := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * v * 0.12
		_vel.append(Vector3.UP * v * rng.randf_range(0.55, 1.0) + abre)
	_anillo = _cartel(Color(0.95, 0.97, 0.98, 0.6), alto * 0.6)
	_mat_anillo = _anillo.material_override as StandardMaterial3D
	# El anillo va TUMBADO sobre el agua, no de cara a la cámara.
	_mat_anillo.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_anillo.rotation.x = -PI * 0.5
	_anillo.position.y = 0.03


func _cartel(color: Color, tam: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(tam, tam)
	m.mesh = q
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	mt.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mt.albedo_texture = Fogonazo._humo_textura()
	mt.albedo_color = color
	m.material_override = mt
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func _process(delta: float) -> void:
	_t += delta
	var u := _t / vida
	if u >= 1.0:
		queue_free()
		return
	for i in _carteles.size():
		var p := _vel[i] * _t + Vector3.DOWN * (4.9 * _t * _t)
		# Lo que vuelve a caer se queda en la superficie como espuma, no atraviesa el mar.
		p.y = maxf(p.y, 0.0)
		_carteles[i].position = p
		_carteles[i].scale = Vector3.ONE * (0.6 + u * 1.2)
		_mats[i].albedo_color.a = 0.85 * (1.0 - u)
	_anillo.scale = Vector3.ONE * (0.4 + u * 3.0)
	_mat_anillo.albedo_color.a = 0.6 * (1.0 - u) * (1.0 - u)
