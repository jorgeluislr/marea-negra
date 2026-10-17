extends Node
## Lo que cuesta el relieve del Caribe en el juego: tirones al entrar y salir celdas, ms de GPU y
## memoria, en la zona más densa (la costa sur de Cuba).
##
##     godot --path . tools/coste_tierra.tscn
##
## Lleva el barco allí con el origen flotante (`Origen.llevar_a`), espera a que cargue lo cercano y:
## 1. mide la GPU con la tierra a la vista y oculta, desde la cubierta, con el tope de fps PUESTO;
## 2. mueve el foco a `VELOCIDAD` m/s a lo largo de la costa durante `SEGUNDOS` —mucho más rápido que
##    la balandra, para que entren y salgan celdas a ritmo de navegación rápida— y apunta el peor
##    frame, cuántas celdas de detalle y siluetas hay y la memoria de vídeo.
##
## `COSTE_TIERRA_FOTO=<png>` guarda la vista.

const DESTINO_LAT_LON := Vector2(19.95, -76.0)   # costa sur de Cuba, Sierra Maestra
const VELOCIDAD := 100.0
const SEGUNDOS := 30.0


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(get_tree().quit.bind(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(7.0).timeout
	var g := get_tree().get_first_node_in_group("tierra") as GestorTierra
	var o := get_node("/root/Origen")
	var arch: Archipielago = g.archipielago
	# Mar adentro frente a la costa: 1,2 km al sur del punto.
	var destino := arch.de_lat_lon(DESTINO_LAT_LON.x, DESTINO_LAT_LON.y) + Vector2(0, 1200)
	o.llevar_a(destino)
	await _hasta_quieto(g, 20.0)

	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var cam := get_viewport().get_camera_3d()
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	var mira := Camera3D.new()
	mira.far = 25000.0
	add_child(mira)
	mira.global_position = b.global_position + Vector3(0, 3, 0)
	mira.look_at(b.global_position + Vector3(0, 40, -2000))
	mira.current = true
	var gpu_con := await _gpu(180)
	var foto := OS.get_environment("COSTE_TIERRA_FOTO")
	if foto != "":
		get_viewport().get_texture().get_image().save_png(foto)
	g.visible = false
	var gpu_sin := await _gpu(180)
	g.visible = true
	mira.queue_free()
	if cam != null:
		cam.current = true

	# Navegación rápida a lo largo de la costa (hacia el oeste).
	var foco := Node3D.new()
	add_child(foco)
	foco.global_position = b.global_position
	g.foco = foco
	var vram0 := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var peor := 0.0
	var t := 0.0
	var max_detalle := 0
	var max_siluetas := 0
	while t < SEGUNDOS:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		foco.global_position.x -= VELOCIDAD * dt
		peor = maxf(peor, dt)
		t += dt
		max_detalle = maxi(max_detalle, (g.get("_detalle") as Dictionary).size())
		max_siluetas = maxi(max_siluetas, g.siluetas())
	var vram1 := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)

	print("\n─── relieve del Caribe, costa sur de Cuba ───")
	print("celdas en disco    : %d" % g.relieve.celdas())
	print("GPU desde cubierta : %.2f ms con tierra, %.2f sin ella (%+.2f)" % [gpu_con, gpu_sin, gpu_con - gpu_sin])
	print("navegando a %.0f m/s durante %.0f s (%.1f km):" % [VELOCIDAD, SEGUNDOS, VELOCIDAD * SEGUNDOS / 1000.0])
	print("  peor frame       : %.1f ms" % (peor * 1000.0))
	print("  celdas de detalle: hasta %d a la vez; siluetas: hasta %d" % [max_detalle, max_siluetas])
	print("  memoria de vídeo : %.0f MB al final (%+.0f durante el viaje)"
		% [vram1 / 1048576.0, (vram1 - vram0) / 1048576.0])
	get_tree().quit()


## Espera a que no quede nada pedido ni por meter.
func _hasta_quieto(g: GestorTierra, tope: float) -> void:
	var t := 0.0
	while t < tope:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > 2.0 and (g.get("_pedidas") as Dictionary).is_empty() \
				and (g.get("_sil_pedidas") as Dictionary).is_empty() \
				and (g.get("_hechas") as Array).is_empty():
			return


func _gpu(frames: int) -> float:
	var vp := get_viewport().get_viewport_rid()
	var s := 0.0
	for i in frames:
		await get_tree().process_frame
		s += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	return s / frames
