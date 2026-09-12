class_name Fogonazo
extends Node3D

## El fogonazo y la humareda de un disparo. Se crea en la boca, vive medio segundo y se borra
## solo: es un efecto, no un objeto del mundo, y no debe quedarse en el árbol.
##
## Sin partículas a propósito: un `GPUParticles3D` bien ajustado se lleva media sesión de
## parámetros, y aquí basta con un destello que decae y unas bocanadas que se expanden. Lo que
## vende el disparo es el DESTELLO CORTO más el humo que persiste, no el detalle de las motas.

@export var vida := 1.6
@export var alcance_luz := 9.0
## Nueve y no cinco: con cinco se cuentan una a una, que es lo contrario de una humareda.
@export var bocanadas := 9
## Tamaño del cartel de cada bocanada, en metros, antes de escalar.
@export var ancho_bocanada := 0.75


## Degradado radial: opaco en el centro y transparente en el borde.
##
## Es lo que convierte un círculo con el borde marcado en humo. Antes cada bocanada era una
## ESFERA con alfa uniforme, así que su contorno era la silueta de la malla — un disco de borde
## nítido por mucho que se bajara la opacidad, porque el corte no estaba en el alfa sino en la
## geometría. Con un cartel orientado a cámara el desvanecido lo hace el propio alfa de la
## textura y no hay silueta que recortar.
##
## Las paradas no son una rampa lineal: el humo real es denso en el núcleo y se deshilacha
## despacio, así que cae poco hasta la mitad del radio y mucho en el último tercio. Una rampa
## recta se ve como un degradado de programa de dibujo.
##
## `static` porque es la misma imagen para todas las piezas y todos los disparos: una andanada
## son cuatro fogonazos de cinco bocanadas, y generar veinte texturas idénticas por salva sería
## tirar memoria.
static var _textura_humo: GradientTexture2D


static func _humo_textura() -> GradientTexture2D:
	if _textura_humo != null:
		return _textura_humo
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.72), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 128
	t.height = 128
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_textura_humo = t
	return t


## Un cartel con esa textura, siempre de cara a la cámara.
##
## `DEPTH_DRAW_DISABLED` importa tanto como el degradado: cinco carteles que se cruzan entre sí
## escribiendo profundidad se recortan unos a otros en línea recta, y esos cortes rectos son
## exactamente lo que delata que son planos. Sin escritura de profundidad se mezclan.
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
	mt.albedo_texture = _humo_textura()
	mt.albedo_color = color
	m.material_override = mt
	add_child(m)
	return m

var _t := 0.0
var _luz: OmniLight3D
var _llama: MeshInstance3D
var _mat_llama: StandardMaterial3D
var _humo: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _dirs: Array[Vector3] = []


## `hacia` es la dirección del tiro: el humo sale por delante de la boca, como debe.
func encender(hacia: Vector3) -> void:
	_luz = OmniLight3D.new()
	_luz.light_color = Color(1.0, 0.78, 0.45)
	_luz.omni_range = alcance_luz
	_luz.light_energy = 6.0
	add_child(_luz)

	# El destello también era una esfera y tenía el mismo borde duro. Va con el mismo cartel,
	# pero SUMANDO luz en vez de mezclando: una llama no tapa lo que hay detrás, lo ilumina.
	_llama = _cartel(Color(1.0, 0.85, 0.5), 0.55)
	_mat_llama = _llama.material_override as StandardMaterial3D
	_mat_llama.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in bocanadas:
		# Cada bocanada nace con un tamaño algo distinto: cinco carteles idénticos creciendo a
		# la vez se leen como cinco discos, no como una humareda.
		var m := _cartel(Color(0.82, 0.80, 0.78, 0.55),
			ancho_bocanada * rng.randf_range(0.8, 1.3))
		_humo.append(m)
		_mats.append(m.material_override as StandardMaterial3D)
		# Reparto: sale hacia delante, abriéndose un poco.
		var desvio := Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.1, 0.35),
			rng.randf_range(-0.3, 0.3))
		# 1,0-2,2 m/s y no 2,0-4,5. A la velocidad de antes cada bocanada recorria hasta 7 m en
		# los 1,6 s de vida, y midiendo unos 2 m de ancho acababan separadas: en la foto del
		# segundo 1,1 se veian bolas sueltas, una de ellas despegada del costado. Una humareda
		# es una nube, o sea bocanadas que se SOLAPAN mientras crecen; recorriendo la mitad se
		# tocan todo el rato.
		_dirs.append((hacia + desvio).normalized() * rng.randf_range(1.0, 2.2))


func _process(delta: float) -> void:
	_t += delta
	var u: float = _t / vida
	if u >= 1.0:
		queue_free()
		return
	# El destello dura una décima parte: es lo que lo hace parecer un fogonazo y no una bengala.
	var f: float = clampf(1.0 - u / 0.12, 0.0, 1.0)
	if _luz != null:
		_luz.light_energy = 6.0 * f * f
	if _llama != null:
		_llama.visible = f > 0.0
		_llama.scale = Vector3.ONE * (1.0 + (1.0 - f) * 1.8)
		_mat_llama.albedo_color.a = f
	for i in _humo.size():
		var m := _humo[i]
		m.position = _dirs[i] * u
		m.scale = Vector3.ONE * (0.5 + u * 2.6)
		_mats[i].albedo_color.a = 0.55 * (1.0 - u)
