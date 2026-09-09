extends Camera3D
## Cámara orbital alrededor del barco.
##   · Arranca EXACTAMENTE donde la coloques en el editor. El PIVOTE de la órbita es
##     el punto al que apunta esa cámara (según su posición + hacia dónde mira).
##   · La órbita es RELATIVA AL BARCO: si la dejas detrás, sigue detrás aunque el
##     barco gire; puedes navegar en cualquier dirección mirando siempre igual.
##   · Clic DERECHO + arrastrar el ratón → gira alrededor del pivote.
##   · Rueda del ratón → zoom (acercar / alejar del pivote).
##   · La cámara nunca baja del nivel del mar (se queda por encima del agua).

@export var objetivo_path: NodePath   # barco al que acompaña; si se deja vacío, usa el nodo padre
@export var distancia_min := 2.0
@export var distancia_max := 80.0
@export var zoom_paso := 1.5
@export var sensibilidad := 0.007     # radianes por píxel de ratón
@export var pitch_min := -1.2         # límite inferior de inclinación (rad)
@export var pitch_max := 1.45         # límite superior (casi cenital)
@export var altura_min_agua := 0.8    # altura mínima de la cámara sobre el mar (y=0)
@export var suavizado := 12.0         # suavizado del zoom (mayor = más rápido)
## Pone el pivote a MEDIA ALTURA del barco en vez de donde mirase la cámara del editor.
##
## Con el pivote a la altura de la cubierta, al acercarse el encuadre se queda en el casco y la
## arboladura se sale por arriba: el mástil aparece cortado y la bandera no se ve. A media
## altura entra el conjunto, y el zoom se acerca al centro del barco en vez de a su base.
##
## La altura se MIDE de las mallas del propio barco, no es un número a mano: así vale igual
## para la balandra que para la lancha, que tienen palos muy distintos.
@export var mira_media_altura := true

var _yaw := 0.0                       # giro RELATIVO al rumbo del barco
var _pitch := 0.4
var _distancia := 13.0
var _dist_actual := 13.0
var _pivote_local := Vector3.ZERO     # pivote en el espacio LOCAL del barco (fijado al abrir)
var _arrastrando := false
var _objetivo: Node3D


func _ready() -> void:
	current = true
	_objetivo = get_node_or_null(objetivo_path) as Node3D
	if _objetivo == null:
		_objetivo = get_parent_node_3d()

	# Pivote = el punto al que MIRA la cámara colocada (a la distancia del barco).
	var pos := global_position
	var frente := -global_transform.basis.z
	var d := 13.0
	if _objetivo:
		d = maxf(0.5, pos.distance_to(_objetivo.global_position))
	var pivote := pos + frente * d
	if _objetivo:
		# Guardar el pivote en el espacio local del barco → acompaña su posición y su giro.
		_pivote_local = _objetivo.global_transform.basis.inverse() * (pivote - _objetivo.global_position)

	# Órbita deducida de la posición de la cámara respecto al pivote.
	var off := pos - pivote               # = -frente * d
	var largo := off.length()
	_distancia = clampf(largo, distancia_min, distancia_max)
	_dist_actual = _distancia
	if largo > 0.0001:
		var world_yaw := atan2(off.x, off.z)
		_yaw = world_yaw - _barco_yaw()   # guardar relativo al rumbo del barco
		_pitch = clampf(asin(clampf(off.y / largo, -1.0, 1.0)), pitch_min, pitch_max)

	if mira_media_altura:
		_subir_pivote.call_deferred()


## Sube el pivote a la mitad de la altura del barco, medida de sus mallas.
##
## Diferido porque el modelo se instancia con la escena y hay que dejar que esté dentro del
## árbol; y se saltan los `SoftBody3D` porque un paño físico vive en espacio de MUNDO y su caja
## no dice nada de la altura del barco.
func _subir_pivote() -> void:
	if _objetivo == null:
		return
	var inv := _objetivo.global_transform.affine_inverse()
	var bajo := INF
	var alto := -INF
	for n in _objetivo.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi is SoftBody3D or mi.mesh == null or not mi.is_inside_tree():
			continue
		var caja := mi.get_aabb()
		var t := inv * mi.global_transform
		for k in 8:
			var y: float = (t * caja.get_endpoint(k)).y
			bajo = minf(bajo, y)
			alto = maxf(alto, y)
	if bajo > alto:
		return
	_pivote_local.y = (bajo + alto) * 0.5
	print("camara_orbital: barco de %.2f m de alto (%.2f a %.2f), pivote a %.2f"
		% [alto - bajo, bajo, alto, _pivote_local.y])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_arrastrando = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_distancia = clampf(_distancia - zoom_paso, distancia_min, distancia_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_distancia = clampf(_distancia + zoom_paso, distancia_min, distancia_max)
	elif event is InputEventMouseMotion and _arrastrando:
		_yaw -= event.relative.x * sensibilidad
		_pitch = clampf(_pitch - event.relative.y * sensibilidad, pitch_min, pitch_max)


func _physics_process(delta: float) -> void:
	if _objetivo == null:
		return
	_dist_actual = lerpf(_dist_actual, _distancia, clampf(delta * suavizado, 0.0, 1.0))

	# El pivote acompaña al barco (posición y giro), conservando el desfase local.
	var pivote := _objetivo.global_position + _objetivo.global_transform.basis * _pivote_local

	# El giro mundial de la cámara = rumbo del barco + giro relativo (así sigue al barco).
	var world_yaw := _barco_yaw() + _yaw

	# Suelo sobre el agua: subir el pitch lo justo para que la cámara no baje de 'altura_min_agua'.
	var min_sin := (altura_min_agua - pivote.y) / maxf(0.01, _dist_actual)
	var piso := asin(clampf(min_sin, -1.0, 1.0))
	_pitch = clampf(_pitch, maxf(pitch_min, piso), pitch_max)

	var off := Vector3(
		cos(_pitch) * sin(world_yaw),
		sin(_pitch),
		cos(_pitch) * cos(world_yaw)
	) * _dist_actual
	global_position = pivote + off
	look_at(pivote, Vector3.UP)


# Rumbo del barco (yaw) según su eje +Z local (popa; avanza hacia -Z).
func _barco_yaw() -> float:
	if _objetivo == null:
		return 0.0
	var atras := _objetivo.global_transform.basis.z
	return atan2(atras.x, atras.z)
