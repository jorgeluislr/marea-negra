extends Node

## ¿Cuántos barcos caben en la escena? Barre 1, 2, 4 y 8 balandras navegando y mide lo que
## cuesta cada salto.
##
## **Con ventana y con el freno quitado, o no mide nada.** Dos razones distintas y las dos
## obligatorias: `--headless` NO simula `SoftBody3D` —las telas se quedan congeladas y salen
## gratis, que es justo lo que se quiere medir—, y con vsync la escena va clavada a 120 fps y el
## coste se esconde en el margen. Mismo método que `coste_fisica.tscn`.
##
##     godot --path . tools/cuantos_barcos.tscn
##
## La última tirada es la que decide el rumbo del mundo abierto: **8 barcos con la tela física
## en uno solo**. Es el techo de lo que daría cambiar la tela física por la de shader con la
## distancia, que es el nivel de detalle que esta arquitectura ya permite sin tocar `Barco` (las
## velas se mandan por nombre de método, no por tipo).

const SEPARACION := 80.0    ## Metros entre barcos: sus cajas de casco no deben solaparse.
const ASENTAR := 6.0        ## Que carguen el modelo y la tela se estabilice antes de medir.
const MEDIR := 4.0

var _barcos: Array[Node3D] = []
var _escena: PackedScene


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func():
		push_error("cuantos_barcos: se acabó el tiempo"); get_tree().quit(1))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_escena = load("res://scenes/barcos/balandra.tscn") as PackedScene

	print("vsync quitado, max_fps 0, física a %d Hz.  %s"
		% [Engine.physics_ticks_per_second, RenderingServer.get_video_adapter_name()])
	print("%8s %10s %13s %14s %13s %9s"
		% ["barcos", "fps", "ms/frame", "física ms/s", "proceso ms/s", "telas"])

	for objetivo in [1, 2, 4, 8]:
		while _barcos.size() < objetivo:
			_anadir()
		await get_tree().create_timer(ASENTAR).timeout
		await _medir("%d" % objetivo)

	# Y ahora el caso del nivel de detalle: los mismos 8 barcos, pero con la tela física sólo en
	# uno. Los demás se quedan sin `SoftBody3D`, que es lo que costaría tenerlos con tela de
	# shader. No se les vuelve a dar orden de vela después de esto: `Barco._velas` guarda
	# referencias a nodos ya liberados y `_mandar_velas` daría error.
	var quitadas := 0
	for i in range(1, _barcos.size()):
		for t in _barcos[i].find_children("*", "SoftBody3D", true, false):
			t.queue_free()
			quitadas += 1
	await get_tree().create_timer(ASENTAR).timeout
	await _medir("8 (1 tela)")
	print("\n(se quitaron %d telas físicas de los 7 barcos de sotavento)" % quitadas)
	get_tree().quit(0)


func _anadir() -> void:
	var b := _escena.instantiate() as Node3D
	b.name = "Balandra%d" % (_barcos.size() + 1)
	add_child(b)
	b.global_position = Vector3(0.0, b.global_position.y, SEPARACION * float(_barcos.size()))
	_barcos.append(b)


func _process(_d: float) -> void:
	# Navegando, que es cuando las telas trabajan de verdad. Ancladas medirían otra cosa.
	Viento.direccion_base = Vector3(1, 0, 0)
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	Viento.fuerza_base = 1.0
	for b in _barcos:
		if is_instance_valid(b):
			b.set("anclado", false)


func _medir(etiqueta: String) -> void:
	var t0 := Time.get_ticks_usec()
	var frames0 := Engine.get_frames_drawn()
	var pasos0 := Engine.get_physics_frames()
	var suma_fis := 0.0
	var suma_pro := 0.0
	var n := 0
	while Time.get_ticks_usec() - t0 < int(MEDIR * 1e6):
		await get_tree().process_frame
		suma_fis += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		suma_pro += Performance.get_monitor(Performance.TIME_PROCESS)
		n += 1
	var seg := float(Time.get_ticks_usec() - t0) / 1e6
	var fps := float(Engine.get_frames_drawn() - frames0) / seg
	var pasos := float(Engine.get_physics_frames() - pasos0) / seg
	var telas := get_tree().root.find_children("*", "SoftBody3D", true, false).size()
	# Milisegundos por SEGUNDO DE JUEGO, no por frame: es lo único comparable entre tiradas con
	# fps distintos, y es el presupuesto que de verdad se gasta.
	print("%8s %10.1f %13.2f %14.1f %13.1f %9d"
		% [etiqueta, fps, 1000.0 / maxf(fps, 0.01),
		   suma_fis / maxf(n, 1) * 1000.0 * pasos,
		   suma_pro / maxf(n, 1) * 1000.0 * fps, telas])
