extends Node

## Cuanto cuesta de verdad subir la frecuencia de fisica, con el limite de fps QUITADO.
##
## Con vsync puesto la escena va clavada a ~120 fps y el coste no se ve: hay que soltar el freno
## y mirar cuantos fps da la maquina en cada caso. La diferencia es el margen que se gasta.
##
## Se mide navegando, que es cuando las tres telas trabajan de verdad.

var _b: Node3D


func _process(_d: float) -> void:
	if _b != null and is_instance_valid(_b):
		_b.set("anclado", false)


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func():
		push_error("coste_fisica: se acabo el tiempo"); get_tree().quit(1))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_b = esc.instantiate() as Node3D
	add_child(_b)
	Viento.direccion_base = Vector3(1, 0, 0)
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	await get_tree().create_timer(8.0).timeout
	print("vsync quitado, max_fps 0.  %s" % RenderingServer.get_video_adapter_name())
	print("%8s %10s %14s %14s"
		% ["fisica", "fps medios", "ms por frame", "ms de fisica/s"])
	for hz in [60, 120, 240, 360]:
		Engine.physics_ticks_per_second = hz
		await get_tree().create_timer(3.0).timeout   # que se estabilice
		var t0 := Time.get_ticks_usec()
		var frames0 := Engine.get_frames_drawn()
		var pasos0 := Engine.get_physics_frames()
		var suma_fis := 0.0
		var n := 0
		while Time.get_ticks_usec() - t0 < 4_000_000:
			await get_tree().process_frame
			suma_fis += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
			n += 1
		var seg := float(Time.get_ticks_usec() - t0) / 1e6
		var fps := float(Engine.get_frames_drawn() - frames0) / seg
		var pasos := float(Engine.get_physics_frames() - pasos0) / seg
		print("%6d Hz %10.1f %14.2f %14.1f    (%.0f pasos/s reales)"
			% [hz, fps, 1000.0 / maxf(fps, 0.01),
			   suma_fis / maxf(n, 1) * 1000.0 * pasos, pasos])
	get_tree().quit()
