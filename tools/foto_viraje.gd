extends Node
## Herramienta de sesion: la bandera A LO LARGO de un viraje de 90 grados a estribor, desde una
## camara fija RESPECTO AL BARCO. Es el caso que el usuario reporto como "se enrolla y no gira".
##
## El encuadre va en ejes del BARCO (proa, estribor, arriba) y no del mundo: si no, en cuanto el
## barco vira la camara se queda mirando a otro sitio y las fotos no son comparables.

@export var carpeta := ""

var _b: Node3D
var _cam: Camera3D
var _skel: Skeleton3D
var _hueso := -1


func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func():
		push_error("foto_viraje: se acabo el tiempo"); get_tree().quit(1))
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_b = esc.instantiate() as Node3D
	add_child(_b)
	Viento.direccion_base = Vector3(1, 0, 0)
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	await get_tree().create_timer(4.0).timeout
	_skel = _b.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_hueso = _skel.find_bone("giro_bandera")
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.fov = 34.0
	_cam.make_current()

	for i in 700:
		_b.set("anclado", false)
		await get_tree().process_frame
	await _foto("s0_antes.png")

	var r0 := _rumbo()
	_pulsar(true)
	var k := 1
	while absf(wrapf(_rumbo() - r0, -180.0, 180.0)) < 90.0:
		_b.set("anclado", false)
		await get_tree().process_frame
		var g := absf(wrapf(_rumbo() - r0, -180.0, 180.0))
		if g > k * 30.0:
			await _foto("s%d_girando_%02d.png" % [k, int(g)])
			k += 1
	_pulsar(false)
	for j in 3:
		for i in 200:
			_b.set("anclado", false)
			await get_tree().process_frame
		await _foto("s9_despues_%d.png" % j)
	get_tree().quit()


func _rumbo() -> float:
	var f := -_b.global_transform.basis.z
	return rad_to_deg(atan2(f.x, f.z))


func _foto(nombre: String) -> void:
	var p := _skel.global_transform * _skel.get_bone_global_pose(_hueso).origin
	var ade := -_b.global_transform.basis.z
	var der := _b.global_transform.basis.x
	_cam.global_position = p + der * 3.4 - ade * 2.8 + Vector3.UP * 0.4
	_cam.look_at(p + Vector3(0, 0.25, 0), Vector3.UP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
	print("FOTO %s   rumbo %.0f" % [nombre, _rumbo()])


func _pulsar(abajo: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_D
	e.physical_keycode = KEY_D
	e.pressed = abajo
	Input.parse_input_event(e)
