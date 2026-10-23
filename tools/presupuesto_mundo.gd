extends Node
## Cuánto cuesta hoy el mundo y cuánto costaría vegetación y pueblos, para repartir el presupuesto.
##
##     godot --path . --max-fps 150 --windowed --resolution 1920x1080 tools/presupuesto_mundo.tscn
##
## Con el tope de fps PUESTO (sin tope el portátil se calienta). Imprime solo al final: cada `print`
## cuesta 15-45 ms en esta máquina y falsearía los frames (memoria consola-cuesta-frames).
##
## 1. **Hoy**, en la salida (Islas Vírgenes) y en la costa sur de Cuba (lo más denso): ms de CPU y GPU
##    por frame, draw calls, objetos y triángulos, con la tierra y el mar a la vista y ocultos.
## 2. **Tirones**: el foco recorre la costa a 18 m/s (×4) y a 100 m/s; peor frame, p99, y el peor de
##    los frames en que el gestor METE una pieza.
## 3. **Vegetación de prueba** en la costa de Cuba: un árbol de ~200 triángulos y un impostor de dos
##    planos cruzados, en `MultiMesh`, en un solo nodo o troceado en parcelas de 250 m con
##    `visibility_range`, con y sin sombras.
## 4. **Pueblo de prueba**: 200 casas de ~1.000 triángulos como nodos sueltos, como `MultiMesh` y como
##    una sola malla fusionada (lo que sería el HLOD).
##
## Las mallas son de prueba (cajas y esferas): miden el coste de la ESTRATEGIA, no el del arte.

const CUBA := Vector2(19.95, -76.0)
const FRAMES := 150
const PARCELA := 250.0

var _lineas: PackedStringArray = []
var _g: GestorTierra
var _vp: RID


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func():
		push_error("presupuesto_mundo: se acabó el tiempo"); get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(7.0).timeout
	_g = get_tree().get_first_node_in_group("tierra") as GestorTierra
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	await _hasta_quieto(25.0)

	_t("─── 1. HOY ───")
	await _medir_sitio("Salida (Islas Vírgenes)", Vector3(0, 40, -2000))
	var o := get_node("/root/Origen")
	var arch: Archipielago = _g.archipielago
	o.llevar_a(arch.de_lat_lon(CUBA.x, CUBA.y) + Vector2(0, 1200))
	await _hasta_quieto(40.0)
	await _medir_sitio("Costa sur de Cuba", Vector3(0, 40, -2000))

	_t("\n─── 2. TIRONES (foco recorriendo la costa hacia el oeste) ───")
	await _recorrer(18.0, 25.0)
	await _recorrer(100.0, 25.0)
	# Volver a Cuba quieto para lo demás.
	_g.foco = null
	o.llevar_a(arch.de_lat_lon(CUBA.x, CUBA.y) + Vector2(0, 1200))
	await _hasta_quieto(40.0)

	_t("\n─── 3. VEGETACIÓN DE PRUEBA (costa de Cuba, vista desde cubierta) ───")
	await _vegetacion()
	_t("\n─── 4. PUEBLO DE PRUEBA (200 casas a ~1,3 km y a ~250 m) ───")
	await _pueblo()

	print("\n".join(_lineas))
	get_tree().quit()


func _t(s: String) -> void:
	_lineas.append(s)


# ── 1. Hoy ───────────────────────────────────────────────────────────────────────────────────────

func _medir_sitio(nombre: String, mira_rel: Vector3) -> void:
	var cam := _camara(mira_rel)
	var mares := get_tree().get_nodes_in_group("mar")
	var todo := await _medir()
	_g.visible = false
	var sin_tierra := await _medir()
	_g.visible = true
	for m in mares:
		m.visible = false
	var sin_mar := await _medir()
	for m in mares:
		m.visible = true
	cam.queue_free()
	await get_tree().process_frame
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var ram := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	_t("%s — %d celdas de detalle, %d siluetas" % [nombre, (_g.get("_detalle") as Dictionary).size(), _g.siluetas()])
	_t("  todo        : " + _fmt(todo))
	_t("  sin tierra  : " + _fmt(sin_tierra))
	_t("  sin mar     : " + _fmt(sin_mar))
	_t("  tierra cuesta %+.2f ms GPU, %+.2f ms CPU render, %+d draws; mar %+.2f ms GPU"
		% [todo.gpu - sin_tierra.gpu, todo.cpu_r - sin_tierra.cpu_r, int(todo.draws - sin_tierra.draws),
			todo.gpu - sin_mar.gpu])
	_t("  memoria: %.0f MB vídeo, %.0f MB RAM estática" % [vram, ram])


## Medias de FRAMES frames, tras 15 sin medir para que se asiente lo que se acaba de cambiar.
func _medir() -> Dictionary:
	for i in 15:
		await get_tree().process_frame
	var r := {"frame": 0.0, "cpu_r": 0.0, "gpu": 0.0, "draws": 0.0, "obj": 0.0, "tris": 0.0}
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		await get_tree().process_frame
		r.cpu_r += RenderingServer.viewport_get_measured_render_time_cpu(_vp)
		r.gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		r.draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		r.obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		r.tris += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	r.frame = (Time.get_ticks_usec() - t0) / 1000.0
	for k in r:
		r[k] /= FRAMES
	return r


func _fmt(r: Dictionary) -> String:
	return "frame %5.2f ms (pared) | GPU %5.2f | CPU render %5.2f | %4d draws | %4d obj | %6.0f k tris" \
		% [r.frame, r.gpu, r.cpu_r, int(r.draws), int(r.obj), r.tris / 1000.0]


func _camara(mira_rel: Vector3) -> Camera3D:
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	var c := Camera3D.new()
	c.far = 25000.0
	add_child(c)
	c.global_position = b.global_position + Vector3(0, 3, 0)
	c.look_at(b.global_position + mira_rel)
	c.current = true
	return c


# ── 2. Tirones ───────────────────────────────────────────────────────────────────────────────────

func _recorrer(vel: float, segundos: float) -> void:
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	var foco := Node3D.new()
	add_child(foco)
	foco.global_position = b.global_position
	_g.foco = foco
	for i in 10:
		await get_tree().process_frame
	var dts: Array[float] = []
	var con_pieza: Array[float] = []
	var t := 0.0
	var antes := _piezas()
	var metidas := 0
	var u := Time.get_ticks_usec()
	while t < segundos:
		await get_tree().process_frame
		# Reloj de PARED: el delta del motor va suavizado al refresco y no enseña los tirones.
		var u1 := Time.get_ticks_usec()
		var dt := (u1 - u) / 1e6
		u = u1
		foco.global_position.x -= vel * dt
		t += dt
		dts.append(dt * 1000.0)
		var ahora := _piezas()
		if ahora != antes:
			con_pieza.append(dt * 1000.0)
			metidas += 1
		antes = ahora
	dts.sort()
	con_pieza.sort()
	var p := func(a: Array[float], q: float) -> float:
		return a[clampi(int(a.size() * q), 0, a.size() - 1)] if not a.is_empty() else 0.0
	_t("a %3.0f m/s, %.1f km: frame p50 %.1f ms, p99 %.1f, peor %.1f | %d frames con pieza nueva: p50 %.1f, peor %.1f"
		% [vel, vel * segundos / 1000.0, p.call(dts, 0.5), p.call(dts, 0.99), dts.back(),
			metidas, p.call(con_pieza, 0.5), con_pieza.back() if not con_pieza.is_empty() else 0.0])
	_g.foco = null
	foco.queue_free()


func _piezas() -> int:
	return (_g.get("_detalle") as Dictionary).size() * 10000 + _g.siluetas()


# ── 3. Vegetación ────────────────────────────────────────────────────────────────────────────────

func _vegetacion() -> void:
	var o := get_node("/root/Origen")
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	var g0: Vector3 = o.a_global(b.global_position)
	var t0 := Time.get_ticks_msec()
	# Puntos de tierra al norte del barco: 3 × 2,6 km, rejilla de 3 m con jitter, pendiente < 35°.
	var puntos := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var paso := 3.0
	var x := g0.x - 1500.0
	while x < g0.x + 1500.0:
		var z := g0.z - 2800.0
		while z < g0.z - 200.0:
			var px := x + rng.randf_range(-1.2, 1.2)
			var pz := z + rng.randf_range(-1.2, 1.2)
			var h := _g.relieve.altura_en(Vector2(px, pz))
			if h > 1.5:
				var hx := _g.relieve.altura_en(Vector2(px + 2.0, pz)) - h
				var hz := _g.relieve.altura_en(Vector2(px, pz + 2.0)) - h
				if Vector2(hx, hz).length() / 2.0 < 0.7:
					puntos.append(Vector3(px, h, pz))
			z += paso
		x += paso
	# Barajar para que los N primeros estén repartidos.
	var idx := range(puntos.size())
	idx.shuffle()
	var tierra_km2 := puntos.size() * paso * paso / 1e6
	_t("puntos de tierra útiles: %d (%.2f km² de tierra llana en la vista), muestreo %.1f s"
		% [puntos.size(), tierra_km2, (Time.get_ticks_msec() - t0) / 1000.0])

	# Cámara FIJA a 250 m de la costa más cercana, a 5 m del agua, mirando tierra adentro: lo que ve
	# el jugador al acercarse a una isla.
	var cerca := puntos[0]
	for q in puntos:
		if Vector2(q.x - g0.x, q.z - g0.z).length() < Vector2(cerca.x - g0.x, cerca.z - g0.z).length():
			cerca = q
	var dir := Vector3(g0.x - cerca.x, 0, g0.z - cerca.z).normalized()
	var cam := Camera3D.new()
	cam.far = 25000.0
	add_child(cam)
	cam.global_position = o.a_local(Vector3(cerca.x, Oleaje.nivel + 5.0, cerca.z) + dir * 250.0)
	cam.look_at(o.a_local(Vector3(cerca.x, Oleaje.nivel + 25.0, cerca.z) - dir * 600.0))
	cam.current = true

	var arbol := _malla_arbol()
	var cruz := _malla_cruzada()
	var base := await _medir()
	_t("  sin vegetación    : " + _fmt(base))
	# [nombre, [[malla, desde, n, vis_ini, vis_fin, sombras], ...], un_nodo]
	var casos := [
		["árbol ×10k, UN nodo, sombras", [[arbol, 0, 10000, 0.0, 0.0, true]], true],
		["árbol ×40k, parcelas, sin vis_range, sombras", [[arbol, 0, 40000, 0.0, 0.0, true]], false],
		["árbol ×40k, parcelas, vis 600 m, sombras", [[arbol, 0, 40000, 0.0, 600.0, true]], false],
		["árbol ×40k, parcelas, vis 600 m, sin sombras", [[arbol, 0, 40000, 0.0, 600.0, false]], false],
		["cruzado ×160k, parcelas, vis 2500 m, sin sombras", [[cruz, 0, 160000, 0.0, 2500.0, false]], false],
		["MIXTO: árbol ×40k 0-400 m con sombras + cruzado ×160k 350-2500 m",
			[[arbol, 0, 40000, 0.0, 400.0, true], [cruz, 40000, 160000, 350.0, 2500.0, false]], false],
	]
	for c in casos:
		# Base justo antes de cada caso: el barco deriva delante de la cámara fija y una base vieja
		# mide su deriva, no la vegetación.
		base = await _medir()
		var vram0 := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
		var t1 := Time.get_ticks_usec()
		var nodos: Array[Node] = []
		var total := 0
		for capa in c[1]:
			var n: int = mini(capa[2], puntos.size() - capa[1])
			total += n
			nodos.append_array(_sembrar(puntos, idx, capa[1], n, capa[0], not c[2], capa[3], capa[4], capa[5]))
		var montar := (Time.get_ticks_usec() - t1) / 1000.0
		var r := await _medir()
		var vram1 := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
		_t("  %s (%d inst., %d nodos, montado en %.0f ms): GPU %+.2f ms, CPU render %+.2f, %+d draws, %+.0f k tris, %+.1f MB vídeo"
			% [c[0], total, nodos.size(), montar, r.gpu - base.gpu, r.cpu_r - base.cpu_r,
				int(r.draws - base.draws), (r.tris - base.tris) / 1000.0, (vram1 - vram0) / 1048576.0])
		for nd in nodos:
			nd.queue_free()
		await get_tree().process_frame
	cam.queue_free()


## Siembra `n` instancias de `malla` desde el punto `desde`; troceadas por parcela o en un solo nodo.
func _sembrar(puntos: PackedVector3Array, idx: Array, desde: int, n: int, malla: Mesh, trocear: bool,
		vis_ini: float, vis_fin: float, sombras: bool) -> Array[Node]:
	var grupos := {}
	for k in range(desde, desde + n):
		var p := puntos[idx[k]]
		var clave := Vector2i(floori(p.x / PARCELA), floori(p.z / PARCELA)) if trocear else Vector2i.ZERO
		if not grupos.has(clave):
			grupos[clave] = []
		grupos[clave].append(p)
	var nodos: Array[Node] = []
	for clave in grupos:
		var lista: Array = grupos[clave]
		var centro := Vector3(clave.x * PARCELA + PARCELA * 0.5, 0, clave.y * PARCELA + PARCELA * 0.5) 			if trocear else Vector3.ZERO
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = malla
		mm.instance_count = lista.size()
		for i in lista.size():
			var p: Vector3 = lista[i]
			var s := 0.8 + fposmod(p.x * 13.1 + p.z * 7.3, 0.5)
			var bas := Basis(Vector3.UP, fposmod(p.x * 3.7, TAU)).scaled(Vector3.ONE * s)
			mm.set_instance_transform(i, Transform3D(bas, p - centro))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = centro + Vector3(0, Oleaje.nivel, 0)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sombras 			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if vis_fin > 0.0:
			mmi.visibility_range_begin = vis_ini
			mmi.visibility_range_begin_margin = 50.0 if vis_ini > 0.0 else 0.0
			mmi.visibility_range_end = vis_fin
			mmi.visibility_range_end_margin = 50.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_g.add_child(mmi)   # anclado al mapa: coordenadas absolutas
		nodos.append(mmi)
	return nodos


## Árbol de prueba: tronco de 8 lados y copa esférica, ~200 triángulos, 9 m.
func _malla_arbol() -> Mesh:
	var st := SurfaceTool.new()
	var tronco := CylinderMesh.new()
	tronco.top_radius = 0.15; tronco.bottom_radius = 0.25; tronco.height = 6.0
	tronco.radial_segments = 8; tronco.rings = 1
	var copa := SphereMesh.new()
	copa.radius = 2.2; copa.height = 3.0; copa.radial_segments = 12; copa.rings = 7
	st.append_from(tronco, 0, Transform3D(Basis(), Vector3(0, 3, 0)))
	st.append_from(copa, 0, Transform3D(Basis(), Vector3(0, 7, 0)))
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.35, 0.12)
	m.surface_set_material(0, mat)
	return m


## Impostor: dos planos cruzados con recorte alfa (una mancha de copa generada).
func _malla_cruzada() -> Mesh:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 32, y - 22).length() / 22.0
			var tronco := absi(x - 32) < 3 and y > 30
			var a := 1.0 if d < 1.0 - 0.25 * sin(x * 0.9) * cos(y * 0.7) or tronco else 0.0
			img.set_pixel(x, y, Color(0.2, 0.35, 0.12, a))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ang in [0.0, PI * 0.5]:
		var e := Vector3(cos(ang), 0, sin(ang)) * 2.5
		var v := [-e, e, e + Vector3(0, 9, 0), -e + Vector3(0, 9, 0)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_uv(uv[k])
			st.add_vertex(v[k])
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


# ── 4. Pueblo ────────────────────────────────────────────────────────────────────────────────────

func _pueblo() -> void:
	var casa := _malla_casa()
	var tris := 0
	for s in casa.get_surface_count():
		tris += casa.surface_get_array_index_len(s) / 3
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	for dist in [1300.0, 250.0]:
		# El pueblo delante de la cámara, en el agua si hace falta: lo que se mide es dibujarlo.
		var centro := b.global_position + Vector3(0, 0, -dist)
		var pos: Array[Vector3] = []
		for i in 200:
			pos.append(centro + Vector3((i % 20 - 10) * 14.0, 1.0, (i / 20 - 5) * 14.0))
		var cam := _camara(Vector3(0, 0, -dist))
		var base := await _medir()
		_t("a %.0f m — sin pueblo: %s" % [dist, _fmt(base)])
		_t("  casa de prueba: %d tris, %d superficies (paredes + tejado)" % [tris, casa.get_surface_count()])
		var baja := _malla_casa_baja()
		# [nombre, malla, forma, sombras]
		for modo in [["200 nodos sueltos, sombras", casa, "nodos", true],
				["200 nodos sueltos, sin sombras", casa, "nodos", false],
				["MultiMesh, sombras", casa, "multi", true],
				["MultiMesh, sin sombras", casa, "multi", false],
				["HLOD: fusionada BAJA (casas de 20 tris), sin sombras", baja, "fusion", false]]:
			base = await _medir()
			var nodos: Array[Node] = []
			var malla: ArrayMesh = modo[1]
			var sombra := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if modo[3] 				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if modo[2] == "nodos":
				for p in pos:
					var mi := MeshInstance3D.new()
					mi.mesh = malla
					mi.cast_shadow = sombra
					add_child(mi)
					mi.global_position = p
					nodos.append(mi)
			elif modo[2] == "multi":
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = malla
				mm.instance_count = pos.size()
				for i in pos.size():
					mm.set_instance_transform(i, Transform3D(Basis(), pos[i] - centro))
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.cast_shadow = sombra
				add_child(mmi)
				mmi.global_position = centro
				nodos.append(mmi)
			else:
				var arr := ArrayMesh.new()
				for s in malla.get_surface_count():
					var st := SurfaceTool.new()
					for p in pos:
						st.append_from(malla, s, Transform3D(Basis(), p - centro))
					arr.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
					arr.surface_set_material(s, malla.surface_get_material(s))
				var mi := MeshInstance3D.new()
				mi.mesh = arr
				mi.cast_shadow = sombra
				add_child(mi)
				mi.global_position = centro
				nodos.append(mi)
			var r := await _medir()
			_t("  %-52s: GPU %+.2f ms, CPU render %+.2f, %+d draws, %+d obj, %+.0f k tris"
				% [modo[0], r.gpu - base.gpu, r.cpu_r - base.cpu_r, int(r.draws - base.draws),
					int(r.obj - base.obj), (r.tris - base.tris) / 1000.0])
			for nd in nodos:
				nd.queue_free()
			await get_tree().process_frame
		cam.queue_free()


## Casa de prueba: caja subdividida y tejado a dos aguas, dos materiales, ~1.000 triángulos.
func _malla_casa() -> ArrayMesh:
	var pared := BoxMesh.new()
	pared.size = Vector3(8, 5, 6)
	pared.subdivide_width = 7; pared.subdivide_height = 5; pared.subdivide_depth = 5
	var tejado := PrismMesh.new()
	tejado.size = Vector3(9, 3, 7)
	tejado.subdivide_width = 6; tejado.subdivide_height = 4; tejado.subdivide_depth = 6
	var m := ArrayMesh.new()
	var a := StandardMaterial3D.new()
	a.albedo_color = Color(0.85, 0.8, 0.7)
	var t := StandardMaterial3D.new()
	t.albedo_color = Color(0.6, 0.25, 0.15)
	var st := SurfaceTool.new()
	st.append_from(pared, 0, Transform3D(Basis(), Vector3(0, 2.5, 0)))
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	m.surface_set_material(0, a)
	st = SurfaceTool.new()
	st.append_from(tejado, 0, Transform3D(Basis().rotated(Vector3.UP, PI * 0.5), Vector3(0, 6.5, 0)))
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	m.surface_set_material(1, t)
	return m


## La misma casa para verla de lejos: caja y tejado sin subdividir.
func _malla_casa_baja() -> ArrayMesh:
	var pared := BoxMesh.new()
	pared.size = Vector3(8, 5, 6)
	var tejado := PrismMesh.new()
	tejado.size = Vector3(9, 3, 7)
	var casa := _malla_casa()
	var m := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.append_from(pared, 0, Transform3D(Basis(), Vector3(0, 2.5, 0)))
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	m.surface_set_material(0, casa.surface_get_material(0))
	st = SurfaceTool.new()
	st.append_from(tejado, 0, Transform3D(Basis().rotated(Vector3.UP, PI * 0.5), Vector3(0, 6.5, 0)))
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	m.surface_set_material(1, casa.surface_get_material(1))
	return m


func _hasta_quieto(tope: float) -> void:
	var t := 0.0
	while t < tope:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > 2.0 and (_g.get("_pedidas") as Dictionary).is_empty() \
				and (_g.get("_sil_pedidas") as Dictionary).is_empty() \
				and (_g.get("_hechas") as Array).is_empty():
			return
