extends Node
## Opción A del relieve: una malla por celda de 1 km, construida en un HILO desde un mapa de alturas
## guardado, con el LOD que genera Godot. Mide lo que cuesta, en el mundo de verdad (mar, barco,
## telas), frente a Terrain3D, que se midió igual y se descartó el 17-10-2026 (ver la memoria islas-y-carta).
##
##     godot --path . tools/coste_relieve.tscn -- [<alturas .r32>]
##
## Las alturas las escribe `blender_src/relieve_caribe.py muestra` (float32 crudo + .json). Por
## defecto, 4 × 4 km de la costa sur del oriente de Cuba a 4 m: 16 celdas de 1 km.
##
## `COSTE_RELIEVE_FOTO=<png>` guarda la vista; `COSTE_CAM_ALTA=1` la toma desde 900 m de altura.
##
## OJO, abierto el 17-10-2026: mirado RASANTE desde el agua a 1,3-6,5 km, el relieve sale con huecos
## (se ven las laderas de detrás y el cielo entre ellas) en las DOS opciones, con cualquier material,
## sin agua y con cualquier plano cercano; desde arriba se ve bien. No decide entre A y B.
##
## Mide, con el tope de fps PUESTO (el portátil no debe correr sin él):
## - cuánto tarda cada celda en el hilo (malla + LOD + colisión) y cuánto en el principal (meterla);
## - el peor frame mientras entran las 16, y en reposo;
## - ms de GPU con el relieve a la vista y sin él;
## - memoria de vídeo que ocupa.

const MUESTRA := "res://fuentes/derivados/muestra/cuba_sureste.r32"
const CELDA_M := 1000.0

var _alturas := PackedFloat32Array()
var _ancho := 0
var _alto := 0
var _paso := 4.0
var _hechas := []
var _mutex := Mutex.new()


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(get_tree().quit.bind(1))
	var args := OS.get_cmdline_user_args()
	var ruta := ProjectSettings.globalize_path(args[0] if not args.is_empty() else MUESTRA)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ruta + ".json"))
	_ancho = int(meta["ancho"]); _alto = int(meta["alto"]); _paso = float(meta["celda"])
	_alturas = FileAccess.get_file_as_bytes(ruta).to_float32_array()
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(7.0).timeout

	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var material: Material = load("res://assets/islas/tierra.tres")
	# El relieve, 2,5 km al este del barco; la cámara, a la altura de cubierta mirándolo.
	var raiz := Node3D.new()
	raiz.position = Vector3(2500.0, Oleaje.nivel, -2000.0)
	add_child(raiz)
	var cam := Camera3D.new()
	cam.far = 25000.0
	add_child(cam)
	cam.global_position = Vector3(1200.0, Oleaje.nivel + 3.0, 0.0)
	if OS.get_environment("COSTE_CAM_ALTA") != "":
		cam.global_position = raiz.global_position + Vector3(-800.0, 900.0, 2000.0)
	cam.look_at(raiz.global_position + Vector3(2000.0, 60.0, 2000.0))
	cam.current = true

	var reposo := await _peor_frame(120)
	var gpu_sin := await _gpu_media(180)
	var vram0 := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)

	# Las 16 celdas, cada una en su hilo; el principal solo las mete, UNA por frame.
	var n := int(_ancho * _paso / CELDA_M)
	var t0 := Time.get_ticks_msec()
	for cz in n:
		for cx in n:
			WorkerThreadPool.add_task(_construir.bind(cx, cz))
	var metidas := 0
	var peor := 0.0
	var principal := []
	while metidas < n * n and Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
		peor = maxf(peor, get_process_delta_time())
		_mutex.lock()
		var lista := _hechas.duplicate()
		_hechas.clear()
		_mutex.unlock()
		if lista.is_empty():
			continue
		# Una por frame: si llegan varias, las demás esperan al siguiente.
		var c: Dictionary = lista.pop_front()
		_mutex.lock()
		_hechas = lista + _hechas
		_mutex.unlock()
		var u := Time.get_ticks_usec()
		var mi := MeshInstance3D.new()
		mi.mesh = c["malla"]
		mi.material_override = material
		mi.position = Vector3(c["cx"] * CELDA_M, 0, c["cz"] * CELDA_M)
		raiz.add_child(mi)
		var cuerpo := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = c["forma"]
		cs.scale = Vector3.ONE * _paso
		cs.position = mi.position + Vector3(CELDA_M * 0.5, 0, CELDA_M * 0.5)
		cuerpo.add_child(cs)
		raiz.add_child(cuerpo)
		principal.append((Time.get_ticks_usec() - u) / 1000.0)
		metidas += 1
		_registro.append(c["ms_hilo"])
	var total := (Time.get_ticks_msec() - t0) / 1000.0
	for i in 30:
		await get_tree().process_frame
		peor = maxf(peor, get_process_delta_time())
	var gpu_con := await _gpu_media(180)
	var vram1 := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var foto := OS.get_environment("COSTE_RELIEVE_FOTO")
	if foto != "":
		get_viewport().get_texture().get_image().save_png(foto)

	_registro.sort()
	principal.sort()
	print("\n─── opción A: malla por celda en un hilo ───")
	print("celdas            : %d de %.0f m a %.0f m (%d × %d alturas cada una)"
		% [n * n, CELDA_M, _paso, int(CELDA_M / _paso) + 1, int(CELDA_M / _paso) + 1])
	print("hilo por celda    : mediana %.0f ms, peor %.0f ms (malla + LOD + colisión)"
		% [_registro[_registro.size() / 2], _registro[-1]])
	print("principal por celda: mediana %.2f ms, peor %.2f ms" % [principal[principal.size() / 2], principal[-1]])
	print("las %d en         : %.1f s" % [n * n, total])
	print("peor frame        : %.1f ms entrando, %.1f ms en reposo" % [peor * 1000.0, reposo])
	print("GPU               : %.2f ms sin relieve, %.2f con él (%+.2f)" % [gpu_sin, gpu_con, gpu_con - gpu_sin])
	print("memoria de vídeo  : %+.1f MB" % ((vram1 - vram0) / 1048576.0))
	print("en disco          : %.0f KB por celda (alturas en media precisión)"
		% (pow(CELDA_M / _paso + 1, 2) * 2 / 1024.0))
	get_tree().quit()


var _registro := []


func _construir(cx: int, cz: int) -> void:
	var u := Time.get_ticks_usec()
	var lado := int(CELDA_M / _paso) + 1
	var verts := PackedVector3Array()
	var normales := PackedVector3Array()
	verts.resize(lado * lado)
	normales.resize(lado * lado)
	var datos := PackedFloat32Array()
	datos.resize(lado * lado)
	for j in lado:
		for i in lado:
			var gx := mini(cx * (lado - 1) + i, _ancho - 1)
			var gz := mini(cz * (lado - 1) + j, _alto - 1)
			var h := _alturas[gz * _ancho + gx]
			verts[j * lado + i] = Vector3(i * _paso, h, j * _paso)
			datos[j * lado + i] = h / _paso
			var hx := _alturas[gz * _ancho + mini(gx + 1, _ancho - 1)] - _alturas[gz * _ancho + maxi(gx - 1, 0)]
			var hz := _alturas[mini(gz + 1, _alto - 1) * _ancho + gx] - _alturas[maxi(gz - 1, 0) * _ancho + gx]
			normales[j * lado + i] = Vector3(-hx, 2.0 * _paso, -hz).normalized()
	var indices := PackedInt32Array()
	for j in lado - 1:
		for i in lado - 1:
			var a := j * lado + i
			indices.append_array([a, a + 1, a + lado, a + 1, a + lado + 1, a + lado])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normales
	arr[Mesh.ARRAY_INDEX] = indices
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(25.0, 60.0, [])
	var malla := im.get_mesh()
	var forma := HeightMapShape3D.new()
	forma.map_width = lado
	forma.map_depth = lado
	forma.map_data = datos
	var c := {"cx": cx, "cz": cz, "malla": malla, "forma": forma,
		"ms_hilo": (Time.get_ticks_usec() - u) / 1000.0}
	_mutex.lock()
	_hechas.append(c)
	_mutex.unlock()


func _peor_frame(frames: int) -> float:
	var peor := 0.0
	for i in frames:
		await get_tree().process_frame
		peor = maxf(peor, get_process_delta_time())
	return peor * 1000.0


func _gpu_media(frames: int) -> float:
	var vp := get_viewport().get_viewport_rid()
	var s := 0.0
	for i in frames:
		await get_tree().process_frame
		s += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	return s / frames
