extends SceneTree
## Tercera pasada, con los dos fallos de la primera corregidos:
##  1. `set_point_pinned(k, true)` SIN ruta de anclaje: con ruta, el punto se va al nodo.
##  2. El monitor TIME_PHYSICS_PROCESS se muestrea una vez por frame de proceso, no por paso
##     de física (por paso devuelve el mismo valor repetido, no se refresca).
## Además prueba de saturación: cuánto tarda de reloj en dar 300 pasos con N velas, cuando lo
## ideal a 60 Hz son 5,000 s. Ahí es donde se ve si cabe en el presupuesto de frame.

const ESTAY_A := Vector3(-8.75, 3.387, -0.001)
const ESTAY_B := Vector3(0.077, 9.126, -0.001)
const PASOS := 300

var _am: ArrayMesh
var _tr: Transform3D
var _vs: PackedVector3Array
var _pins: PackedInt32Array
var _raiz: Node3D
var _cuerpos: Array[SoftBody3D] = []

func _initialize() -> void:
	_correr()

func _trans(n: Node, raiz: Node) -> Transform3D:
	var t := Transform3D(); var x := n
	while x != null and x != raiz:
		if x is Node3D: t = (x as Node3D).transform * t
		x = x.get_parent()
	return t

func _dist_al_estay(p: Vector3) -> float:
	var d := ESTAY_B - ESTAY_A
	var t := clampf((p - ESTAY_A).dot(d) / d.length_squared(), 0.0, 1.0)
	return p.distance_to(ESTAY_A + d * t)

func _anadir() -> SoftBody3D:
	var sb := SoftBody3D.new()
	sb.name = "PanoFisico%d" % _cuerpos.size()
	sb.mesh = _am
	sb.transform = _tr
	sb.simulation_precision = 5
	sb.total_mass = 8.0
	sb.linear_stiffness = 0.5
	sb.damping_coefficient = 0.01
	sb.drag_coefficient = 0.3
	_raiz.add_child(sb)
	await process_frame
	for k in _pins:
		sb.set_point_pinned(k, true)          # sin ruta: se queda donde está
	_cuerpos.append(sb)
	return sb

## Devuelve [ms medios de fisica, ms pico, segundos de reloj para PASOS pasos]
func _medir() -> Array:
	for i in 40:
		await process_frame
	var f0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_usec()
	var suma := 0.0; var pico := 0.0; var n := 0
	while Engine.get_physics_frames() - f0 < PASOS:
		await process_frame
		var ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		suma += ms; pico = maxf(pico, ms); n += 1
	var seg := float(Time.get_ticks_usec() - t0) / 1_000_000.0
	return [suma / maxf(n, 1), pico, seg, n]

func _correr() -> void:
	await process_frame
	var modelo: Node3D = (load("res://assets/models/balandra.glb") as PackedScene).instantiate()
	var mi := modelo.find_children("foque", "MeshInstance3D", true, false)[0] as MeshInstance3D
	_tr = _trans(mi, modelo)
	var arr := mi.mesh.surface_get_arrays(0)
	_vs = arr[Mesh.ARRAY_VERTEX]
	var na := []; na.resize(Mesh.ARRAY_MAX)
	na[Mesh.ARRAY_VERTEX] = _vs
	na[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
	_am = ArrayMesh.new()
	_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
	_pins = PackedInt32Array()
	for k in _vs.size():
		if _dist_al_estay(_tr * _vs[k]) < 0.08: _pins.append(k)
	print("yankee: %d vertices, %d triangulos, %d fijados al estay" % [_vs.size(), arr[Mesh.ARRAY_INDEX].size() / 3, _pins.size()])
	print("fisica a %d Hz, presupuesto de paso %.2f ms; %d pasos ideales = %.3f s de reloj"
		% [Engine.physics_ticks_per_second, 1000.0 / Engine.physics_ticks_per_second, PASOS, float(PASOS) / Engine.physics_ticks_per_second])

	_raiz = Node3D.new(); root.add_child(_raiz)
	await process_frame
	var base: Array = await _medir()
	print("%3d velas  fisica %6.3f ms  pico %6.3f ms  reloj %5.3f s" % [0, base[0], base[1], base[2]])
	var prev: float = base[0]
	for objetivo in [1, 2, 4, 8, 16, 32]:
		while _cuerpos.size() < objetivo:
			await _anadir()
		var m: Array = await _medir()
		print("%3d velas  fisica %6.3f ms  pico %6.3f ms  reloj %5.3f s   delta %+6.3f ms  por vela %+6.3f ms"
			% [objetivo, m[0], m[1], m[2], m[0] - base[0], (m[0] - base[0]) / float(objetivo)])
	# ¿se sostiene el paño?
	var sb0 := _cuerpos[0]
	var suma := 0.0; var maxd := 0.0; var maxfijo := 0.0
	for k in _vs.size():
		var d := (sb0.get_point_transform(k) - _tr * _vs[k]).length()
		suma += d; maxd = maxf(maxd, d)
	for k in _pins:
		maxfijo = maxf(maxfijo, (sb0.get_point_transform(k) - _tr * _vs[k]).length())
	print("desviacion del reposo: media %.4f m  max %.4f m   los %d fijados: max %.4f m" % [suma / float(_vs.size()), maxd, _pins.size(), maxfijo])
	quit(0)
