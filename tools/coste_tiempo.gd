extends Node

## Cuánto cuesta ACELERAR LA TRAVESÍA y qué se rompe, a cada multiplicador.
##
##     godot --path . tools/coste_tiempo.tscn -- <modo> <N>
##
## Un caso por proceso, porque una tela que se rompe no se recupera y estropearía los siguientes.
## Modos:
##   - `grandes`: `Engine.time_scale = N` sin más. Godot da los MISMOS pasos de física por segundo
##     real, cada uno N veces más largo.
##   - `pasos`: `time_scale = N` y la física a 60·N Hz, para que el paso siga siendo 1/60 s de
##     juego. Son N veces más pasos por frame; `max_physics_steps_per_frame` se sube a 64.
##   - `abstracto`: tiempo normal y el barco empujado (N−1) veces su propia velocidad en cada paso.
##     Las telas siguen montadas: dice cuánto aguantan las anclas que corren, no cuánto cuesta.
##
## `pasos` es exactamente lo que hace la navegación rápida del juego (`Travesia`, la T).
##
## Medido el 18-10-2026 (balandra a 3,3 m/s; con el juego del usuario abierto a la vez, así que
## los fps bailan entre 60 y 112 con la misma carga):
##
##     pasos ×2 / ×4        fps 61 / 55-113   ×2 / ×4 reales     3-8 aristas, 18 mm (= base)
##     pasos ×8 / ×16       fps 7             se queda en ×7,7   techo de ~460 pasos/s
##     grandes ×2 / ×4 / ×8 fps 112           ×N                 48 / 160 / 420 aristas, hasta 30 cm
##     abstracto ×16 / ×32  fps 113 / 61      52 / 104 m/s       6-10 aristas, 24-26 mm
##
## Por eso la T no pasa de ×4. Se mide navegando de través con viento fijo, con el tope de fps PUESTO (120), que es como juega
## el usuario: lo que se ve es si el juego llega a dar los pasos que le pide el multiplicador.
## Imprime una línea `RESULTADO` con todo, para juntar las tiradas.

const VENTANA := 6.0       ## Segundos reales que se mide cada caso.
const RECUPERA := 5.0      ## Segundos reales a ×1 después, para ver si las telas se recomponen.

var _modo := "pasos"
var _n := 1.0
var _b: Node3D
var _empujar := false


func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func():
		push_error("coste_tiempo: se acabo el tiempo"); get_tree().quit(1))
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1: _modo = a[0]
	if a.size() >= 2: _n = float(a[1])
	Engine.max_fps = 120
	get_window().size = Vector2i(960, 540)
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	_medir()


func _fijar_viento() -> void:
	Viento.direccion_base = Vector3(1, 0, 0)    # de través: el barco sale con proa a −Z
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	Viento.fuerza_base = 1.0


func _process(_d: float) -> void:
	_fijar_viento()
	if _b != null and is_instance_valid(_b):
		_b.set("anclado", false)


func _physics_process(delta: float) -> void:
	if _empujar and _b is CharacterBody3D:
		var v := (_b as CharacterBody3D).velocity
		_b.global_position += Vector3(v.x, 0.0, v.z) * (_n - 1.0) * delta


func _telas() -> Array:
	var l := []
	for v in _b.get_children():
		if v.has_method("datos_depuracion") and not v.datos_depuracion().is_empty():
			l.append(v)
	return l


## {malas, peor_m} del peor paño en este paso de física.
func _estiramiento() -> Vector2:
	var malas := 0
	var peor := 0.0
	for t in _telas():
		var d: Dictionary = t.datos_depuracion()
		var c: SoftBody3D = d["cuerpo"]
		var ar: PackedInt32Array = d["aristas"]
		var l0: PackedFloat32Array = d["largo0"]
		for e in l0.size():
			var largo := c.get_point_transform(ar[e * 2]).distance_to(
				c.get_point_transform(ar[e * 2 + 1]))
			var f := absf(largo - l0[e]) / maxf(l0[e], 0.0001)
			peor = maxf(peor, absf(largo - l0[e]))
			if f > 0.25:
				malas += 1
	return Vector2(malas, peor)


func _medir() -> void:
	# Que las telas nazcan, el mar fino entre y el barco coja arrancada.
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 14000:
		await get_tree().process_frame
		if _b == null:
			var l := get_tree().get_nodes_in_group("barco_activo")
			if not l.is_empty():
				_b = l[0]
	var base := _estiramiento()
	for i in 10:
		await get_tree().process_frame   # ventana sin escribir: la consola cuesta frames

	match _modo:
		"grandes":
			Engine.time_scale = _n
		"pasos":
			Engine.max_physics_steps_per_frame = 64
			Engine.physics_ticks_per_second = int(60 * _n)
			Engine.time_scale = _n
		"abstracto":
			_empujar = true
	await get_tree().create_timer(1.0, true, false, true).timeout   # 1 s real de transición

	var frames := PackedFloat32Array()
	var pasos0 := Engine.get_physics_frames()
	var tb0: float = _b.get("time")
	var p0 := Origen.a_global(_b.global_position)
	var malas := 0
	var peor := 0.0
	var escora := 0.0
	var r0 := Time.get_ticks_usec()
	var ult := r0
	var muestra := 0
	while Time.get_ticks_usec() - r0 < int(VENTANA * 1e6):
		await get_tree().process_frame
		var ahora := Time.get_ticks_usec()
		frames.append((ahora - ult) / 1000.0)
		ult = ahora
		escora = maxf(escora, absf(rad_to_deg(float(_b.get("_escora")))))
		muestra += 1
		if muestra % 15 == 0:
			await get_tree().physics_frame
			var e := _estiramiento()
			malas = maxi(malas, int(e.x))
			peor = maxf(peor, e.y)
	var seg := (Time.get_ticks_usec() - r0) / 1e6
	var pasos_s := (Engine.get_physics_frames() - pasos0) / seg
	var juego_s := (float(_b.get("time")) - tb0) / seg
	var m_s := Origen.a_global(_b.global_position).distance_to(p0) / seg
	var dt_fis := get_physics_process_delta_time()

	# Vuelta a ×1 y a ver si se recomponen.
	_empujar = false
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	await get_tree().create_timer(RECUPERA).timeout
	var tras := _estiramiento()

	frames.sort()
	var p95 := frames[int(frames.size() * 0.95)] if frames.size() > 0 else 0.0
	var peor_f := frames[frames.size() - 1] if frames.size() > 0 else 0.0
	print("RESULTADO modo=%s N=%.0f fps=%.1f p95_ms=%.1f peor_ms=%.1f pasos_s=%.0f dt_fis=%.4f "
		% [_modo, _n, frames.size() / seg, p95, peor_f, pasos_s, dt_fis]
		+ "juego_s=%.2f m_s=%.2f escora_max=%.1f base_malas=%d base_peor_m=%.3f "
		% [juego_s, m_s, escora, int(base.x), base.y]
		+ "malas=%d peor_m=%.3f tras_malas=%d tras_peor_m=%.3f"
		% [malas, peor, int(tras.x), tras.y])
	get_tree().quit()
