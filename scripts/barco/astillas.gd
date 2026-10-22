class_name Astillas
extends Node3D

## Las astillas que salta una bala al entrar en la madera. Un efecto, no un objeto: vuela, cae y
## se borra solo. Va colgado del ÁRBOL y no del barco por lo mismo que el humo: una astilla que
## sale despedida no navega con el casco.
##
## Un solo `MultiMeshInstance3D` para todas: son una docena de tablillas por impacto y una andanada
## son cuatro impactos, y cuarenta nodos para un efecto de un segundo es tirar el árbol.

@export var vida := 1.3
@export var cuantas := 14
## Hacia dónde salen: la normal de la cara que tocó la bala. La pone quien la crea.
var normal := Vector3.UP
## Color de la madera. Las de cubierta y las del costado son del mismo roble.
var color := Color(0.45, 0.32, 0.19)

var _t := 0.0
var _mm: MultiMesh
var _vel: Array[Vector3] = []
var _giro: Array[Vector3] = []
var _tam: Array[Vector3] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	var caja := BoxMesh.new()
	caja.size = Vector3.ONE
	var mt := StandardMaterial3D.new()
	mt.albedo_color = color
	mt.roughness = 0.95
	caja.material = mt
	_mm.mesh = caja
	_mm.instance_count = cuantas
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	for i in cuantas:
		# Un cono de unos 50° alrededor de la normal, más un empujón hacia arriba.
		var d := (n + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.3, 0.9),
			rng.randf_range(-0.8, 0.8))).normalized()
		_vel.append(d * rng.randf_range(3.0, 8.0))
		_giro.append(Vector3(rng.randf_range(-15, 15), rng.randf_range(-15, 15), rng.randf_range(-15, 15)))
		_tam.append(Vector3(rng.randf_range(0.02, 0.05), rng.randf_range(0.01, 0.02),
			rng.randf_range(0.08, 0.22)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_mover()


func _process(delta: float) -> void:
	_t += delta
	if _t >= vida:
		queue_free()
		return
	_mover()


func _mover() -> void:
	var encoge := clampf(1.0 - (_t / vida - 0.7) / 0.3, 0.0, 1.0)
	for i in cuantas:
		var p := _vel[i] * _t + Vector3.DOWN * (4.9 * _t * _t)
		var b := Basis.from_euler(_giro[i] * _t).scaled(_tam[i] * encoge)
		_mm.set_instance_transform(i, Transform3D(b, p))
