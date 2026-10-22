class_name MunicionTest
extends RefCounted

## Paquete `municion`: la bala como objeto que se VE y que DAÑA donde pega.
##
## Lo que se rompe en silencio y por eso se prueba:
##
##   · **Que lo que se ve no sea lo que vuela.** La bala vuela por la parábola analítica (la de la
##     guía); si la malla se mueve por su cuenta —interpolada, integrada—, el jugador ve una bola
##     que no va donde va el tiro, y ninguna otra prueba lo caza.
##   · **Que el agua donde cae no sea el mar que se dibuja.** Cayendo en un plano fijo, la
##     salpicadura sale en el aire sobre un seno o dentro de una cresta.
##   · **Que el impacto acabe en otra zona.** Un tiro a la flotación de estribor tiene que bajar
##     ESTRIBOR y abrir vía, y no tocar babor ni el aparejo. Y uno que cruza la caja del barco por
##     donde ya no hay casco (la esquina de proa) tiene que seguir de largo.
##   · **Que el daño no tenga efecto.** Un aparejo tocado da menos superficie de vela; tres vías de
##     agua contra unas bombas que achican vía y media hunden el barco.
##   · **Que la munición elegida no sea la que sale.** Tres tipos, tecla Q, y cada uno con su
##     alcance (la palanqueta llega a la mitad) y su reserva.
##
## Los blancos son una balandra ENEMIGA fondeada al lado, como en el paquete `ia`, y los tiros los
## suelta la prueba con `Bala` directamente, apuntados a puntos sacados de la geometría del propio
## barco (su flotación, su palo, su casco) y no escritos a mano.
##
## Las clases nuevas se cargan por ruta (`load`) y no por nombre: si una no existe o no compila,
## este paquete falla en sus comprobaciones y la batería sigue, en vez de no compilar entera.

const RUTA_MUNICION := "res://scripts/barco/municion.gd"
const DISTANCIA_TIRO := 25.0
const VEL := 110.0
const G := 9.8


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("municion")
	var mio := UtilesPruebas.barco(arbol)
	if not m.comprobar(mio != null, "hay un barco en el grupo 'barco_activo'"):
		return
	_viento(arbol)
	mio.set("anclado", true)

	if m.escenario("vuelo"):
		await _vuelo(m, arbol, mio)
	if m.escenario("tamano"):
		await _tamano(m, arbol)
	if m.escenario("municiones"):
		await _municiones(m, arbol, mio)

	var quiere_blanco := false
	for e in ["flotacion", "aire", "aparejo", "hud", "hundimiento"]:
		if m._pide.is_empty() or m._pide.has("municion") or m._pide.has("municion/" + e):
			quiere_blanco = true
	if not quiere_blanco:
		return
	var enemigo := await _soltar_blanco(arbol, mio)
	if not m.comprobar(enemigo != null, "se puede fondear una balandra de blanco"):
		return
	m.comprobar(enemigo.has_method("reparar") and enemigo.has_method("vias_de_agua"),
		"el barco tiene modelo de daños (reparar, vias_de_agua)")
	if m.escenario("flotacion"):
		await _flotacion(m, arbol, enemigo)
	if m.escenario("aire"):
		await _aire(m, arbol, enemigo)
	if m.escenario("aparejo"):
		await _aparejo(m, arbol, enemigo)
	if m.escenario("hud"):
		await _hud(m, arbol, mio)
	# El último: deja el blanco en el fondo.
	if m.escenario("hundimiento"):
		await _hundimiento(m, arbol, enemigo)
	_retirar(enemigo)
	_reparar(mio)


# ── Vuelo: la bola que se ve está en la parábola ────────────────────────────
static func _vuelo(m: MarcoPruebas, arbol: SceneTree, mio: Node3D) -> void:
	var balas: Array[Node] = []
	var ver := func(n: Node): if n is Bala: balas.append(n)
	arbol.node_added.connect(ver)
	var impactos: Array[Dictionary] = []
	var anota := func(donde: Vector3, _contra: Node):
		# El mar que se dibuja, leído EN EL MISMO PASO del impacto: un frame después la ola es otra.
		impactos.append({"donde": donde, "mar": Oleaje.altura_en(Vector2(donde.x, donde.z))})
	for c in mio.call("canones_de", "estribor"):
		(c as Node).connect("impacto", anota)
		(c as Node).set("elevacion", 3.0)
	mio.set("banda_apuntada", "estribor")
	mio.set("municion", 60)
	var salieron := int(mio.call("disparar_banda"))
	await arbol.process_frame
	arbol.node_added.disconnect(ver)
	if not m.comprobar(salieron > 0 and not balas.is_empty(), "sale una bala al disparar",
			"%d piezas, %d balas" % [salieron, balas.size()]):
		return
	var bala := balas[0] as Bala
	var mallas := bala.find_children("*", "MeshInstance3D", true, false)
	if m.comprobar(not mallas.is_empty(), "la bala lleva una malla visible"):
		var malla := mallas[0] as MeshInstance3D
		var esfera := malla.mesh as SphereMesh
		m.comprobar(esfera != null and absf(esfera.radius - 0.038) < 0.005,
			"la rasa es una bola de 76 mm (a 3 libras)",
			"radio %.3f" % (esfera.radius if esfera != null else -1.0))
		# La malla se mira en el reloj del RENDER, que es cuando se ve. La horizontal de la
		# parábola es lineal en t, así que de ella sale el instante y de ahí dónde debía estar.
		var peor := 0.0
		var peor_fisica := 0.0
		var vistas := 0
		var t := 0.0
		while is_instance_valid(bala) and is_instance_valid(malla) and t < 6.0:
			var p0: Vector3 = bala.get("_p0")
			var v0: Vector3 = bala.get("_v0")
			var vh := Vector2(v0.x, v0.z)
			var q: Vector3 = malla.global_position
			var tt := (Vector2(q.x, q.z) - Vector2(p0.x, p0.z)).dot(vh) / vh.length_squared()
			if tt > 0.0 and malla.is_visible_in_tree():
				peor = maxf(peor, q.distance_to(Bala.punto(p0, v0, tt)))
				vistas += 1
			peor_fisica = maxf(peor_fisica, bala.global_position.distance_to(
				Bala.punto(p0, v0, float(bala.get("_t")))))
			t += arbol.root.get_process_delta_time()
			await arbol.process_frame
		m.mayor_que(float(vistas), 20.0, "la bala se ve durante el vuelo", "%d frames" % vistas)
		m.menor_que(peor, 0.01, "la bola que se ve está en la parábola en cada frame",
			"peor %.4f m" % peor)
		m.menor_que(peor_fisica, 0.001, "y la bala, en cada paso de física")
	# El agua donde cae es la ola que se dibuja, no un plano.
	var espera := 0.0
	while impactos.is_empty() and espera < 6.0:
		espera += arbol.root.get_process_delta_time()
		await arbol.process_frame
	for c in mio.call("canones_de", "estribor"):
		(c as Node).disconnect("impacto", anota)
		(c as Node).set("elevacion", 0.0)
	if m.comprobar(not impactos.is_empty(), "la bala cae al agua"):
		var i: Dictionary = impactos[0]
		var donde: Vector3 = i["donde"]
		m.casi(donde.y, float(i["mar"]), 0.03, "cae en la ola de `Oleaje.altura_en`, no en un plano")
		var hay := false
		for n in arbol.current_scene.find_children("Salpicadura*", "", true, false):
			if n is Node3D and (n as Node3D).global_position.distance_to(donde) < 1.0:
				hay = true
		m.comprobar(hay, "salta una salpicadura donde cae")


# ── Tamaño en pantalla: de lejos no baja de unos píxeles, de cerca es la de verdad ──
## Una rasa de 7,6 cm a 100 m ocupa 0,7 px en 1080p y un perdigón 0,3: no se ven. La bola se
## dibuja más grande cuanto más lejos esté de la cámara, lo justo para no bajar de
## `Bala.PIXELES_MIN`, y de cerca con su tamaño real. Se mide lo que DIBUJA: el diámetro de la
## malla por su escala, proyectado con la cámara que mira.
static func _tamano(m: MarcoPruebas, arbol: SceneTree) -> void:
	var cam := arbol.root.get_viewport().get_camera_3d()
	if not m.comprobar(cam != null, "hay cámara"):
		return
	var M = load(RUTA_MUNICION)
	for tipo in ["rasa", "metralla"]:
		for dist in [6.0, 100.0, 300.0]:
			var b := Bala.new()
			b.name = "BalaDeTamano"
			arbol.current_scene.add_child(b)
			var frente := -cam.global_transform.basis.z
			var p: Vector3 = cam.global_position + frente * float(dist)
			# Quieta en el sitio (sin velocidad ni gravedad no hay; basta un frame).
			b.lanzar(p, frente * 0.001, -1000.0, M.de(tipo) if M != null else null)
			await arbol.process_frame
			var px := _pixeles(cam, b)
			var radio: float = (M.de(tipo).radio if M != null else 0.038)
			var real_px := 2.0 * radio / _metros_por_pixel(cam, float(dist))
			if dist < 10.0:
				m.casi(px, real_px, real_px * 0.05, "%s a %.0f m: tamaño real" % [tipo, dist],
					"%.1f px" % px)
			else:
				# 2 px y no 3: con 3 el usuario la veía demasiado grande (20-10-2026).
				m.casi(px, 2.0, 0.1, "%s a %.0f m: se ve con 2 px" % [tipo, dist],
					"la real daría %.2f" % real_px)
			b.queue_free()


static func _metros_por_pixel(cam: Camera3D, dist: float) -> float:
	var alto := float(cam.get_viewport().get_visible_rect().size.y)
	return 2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5) / alto


## Diámetro en píxeles de la bola que se dibuja: el de su malla por la escala del nodo que la lleva.
static func _pixeles(cam: Camera3D, b: Node) -> float:
	var mallas := b.find_children("*", "MeshInstance3D", true, false)
	if mallas.is_empty():
		return 0.0
	var mi := mallas[0] as MeshInstance3D
	var esfera := mi.mesh as SphereMesh
	if esfera == null:
		return 0.0
	var escala: float = mi.global_transform.basis.get_scale().x
	var dist := cam.global_position.distance_to(mi.global_position)
	return 2.0 * esfera.radius * escala / _metros_por_pixel(cam, dist)


# ── Munición: tres tipos, tecla Q, alcance y reserva propios ────────────────
static func _municiones(m: MarcoPruebas, arbol: SceneTree, mio: Node3D) -> void:
	if not m.comprobar("municion_actual" in mio and "pertrechos" in mio,
			"el barco lleva tipo de munición y pertrechos"):
		return
	# La Q la lee el mando, y el mando solo manda con el jugador al timón.
	await UtilesPruebas.al_timon(arbol)
	mio.set("modo_battle", true)
	await arbol.process_frame
	m.comprobar(String(mio.get("municion_actual")) == "rasa", "sale cargando rasa")
	var orden: Array[String] = []
	for i in 3:
		await UtilesPruebas.tecla(arbol, KEY_Q)
		orden.append(String(mio.get("municion_actual")))
	m.comprobar(orden == ["palanqueta", "metralla", "rasa"], "la Q pasa rasa → palanqueta → metralla → rasa",
		", ".join(orden))

	var pieza := (mio.call("canones_de", "estribor") as Array)[0] as Node
	var rasa := float(pieza.call("alcance_a", Canon.ELEVACION_MAX))
	mio.set("municion_actual", "palanqueta")
	var palanqueta := float(pieza.call("alcance_a", Canon.ELEVACION_MAX))
	m.comprobar(palanqueta > rasa * 0.4 and palanqueta < rasa * 0.6,
		"la palanqueta llega a la mitad que la rasa", "%.0f m contra %.0f" % [palanqueta, rasa])

	# Reservas separadas: tirar palanqueta no gasta rasa.
	var pert: Dictionary = (mio.get("pertrechos") as Dictionary).duplicate()
	await _recargar(arbol, mio)
	mio.set("banda_apuntada", "estribor")
	mio.call("disparar_banda")
	var ahora: Dictionary = mio.get("pertrechos")
	m.comprobar(int(ahora["palanqueta"]) == int(pert["palanqueta"]) - 2
		and int(ahora["rasa"]) == int(pert["rasa"]),
		"la palanqueta sale de su reserva y no de la de rasa",
		"%s → %s" % [pert, ahora])
	m.comprobar(int(mio.get("municion")) == int(ahora["palanqueta"]),
		"`municion` es la reserva del tipo cargado")

	# La metralla: un disparo son muchos perdigones.
	mio.set("municion_actual", "metralla")
	await _recargar(arbol, mio)
	var balas: Array[Node] = []
	var ver := func(n: Node): if n is Bala: balas.append(n)
	arbol.node_added.connect(ver)
	pieza.call("disparar")
	await arbol.process_frame
	arbol.node_added.disconnect(ver)
	m.mayor_que(float(balas.size()), 5.0, "una pieza de metralla suelta muchos perdigones",
		"%d" % balas.size())
	mio.set("municion_actual", "rasa")
	mio.set("modo_battle", false)


static func _recargar(arbol: SceneTree, b: Node3D) -> void:
	var espera := 0.0
	while espera < 8.0:
		var listas := true
		for c in b.call("canones_de", "estribor"):
			listas = listas and bool((c as Node).call("listo"))
		if listas:
			return
		espera += arbol.root.get_process_delta_time()
		await arbol.process_frame


# ── Flotación de estribor: daña ESA zona, abre vía, deja agujero ────────────
static func _flotacion(m: MarcoPruebas, arbol: SceneTree, e: Node3D) -> void:
	_reparar(e)
	var z := _z_de_zona(e, 0.5)
	var y := _y_agua_local(e, Vector3(0.0, 0.0, z)) + 0.10
	var g := await _tiro_lateral(arbol, e, 1.0, y, z)
	if not m.comprobar(_es_de(g.get("contra"), e), "el tiro a la flotación toca el barco",
			"%s" % g):
		return
	var integ: Dictionary = e.get("integridad")
	m.casi(float(integ["estribor"]), 0.9, 0.001, "baja estribor una bala de rasa")
	m.comprobar(float(integ["babor"]) == 1.0 and float(integ["proa"]) == 1.0
		and float(integ["popa"]) == 1.0 and float(integ["aparejo"]) == 1.0,
		"y no toca otra zona", "%s" % integ)
	m.comprobar(_vias(e) == 1, "abre una vía de agua",
		"%d" % _vias(e))
	var donde: Vector3 = g["donde"]
	var agujero := false
	for d in e.find_children("*", "Decal", true, false):
		if (d as Node3D).global_position.distance_to(donde) < 0.3:
			agujero = true
	m.comprobar(agujero, "deja un agujero en el casco donde pegó")
	var astillas := false
	for n in arbol.current_scene.find_children("Astillas*", "", true, false):
		if n is Node3D and (n as Node3D).global_position.distance_to(donde) < 1.0:
			astillas = true
	m.comprobar(astillas, "y saltan astillas")
	# Una vía sola la achican las bombas.
	await _esperar(arbol, 3.0)
	m.casi(_num(e, "agua_embarcada"), 0.0, 0.001, "una vía sola la achican las bombas")
	# Por encima de la flotación no abre vía.
	var gz := e.to_global(Vector3(0.0, 0.0, z))
	var regala := e.to_local(Vector3(gz.x, float(e.call("altura_regala_en", gz)), gz.z)).y
	var g2 := await _tiro_lateral(arbol, e, 1.0, regala - 0.45, z)
	if m.comprobar(_es_de(g2.get("contra"), e), "un tiro a la obra muerta toca el barco"):
		m.casi(float((e.get("integridad") as Dictionary)["estribor"]), 0.8, 0.001,
			"vuelve a bajar estribor")
		m.comprobar(_vias(e) == 1, "pero no abre otra vía")


# ── La caja no es el casco: por la esquina de proa la bala sigue ────────────
## El punto de aire se busca CORTANDO los triángulos del casco y la cubierta con la recta del tiro,
## no por el vértice más a proa de una franja de alturas: este casco tiene triángulos largos, la
## roda se inclina, y la superficie entre dos vértices va más a proa que cualquiera de ellos. Con
## los vértices el tiro "al aire" daba en la roda.
static func _aire(m: MarcoPruebas, arbol: SceneTree, e: Node3D) -> void:
	_reparar(e)
	var cs := e.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	var caja := cs.shape as BoxShape3D if cs != null else null
	if not m.comprobar(caja != null, "se mide la caja del barco"):
		return
	var proa_caja: float = cs.position.z - caja.size.z * 0.5
	var agua := _y_agua_local(e, Vector3.ZERO)
	var tope: float = cs.position.y + caja.size.y * 0.5
	# La altura con MÁS aire delante de la roda, entre medio metro sobre el agua y la regala: con
	# una altura fija el hueco quedaba en 0,32 m contra 0,30 pedidos, y un margen así es como nace
	# una prueba intermitente (el casco cabecea mientras la bala vuela).
	var mejor_y := agua + 0.5
	var mejor_roda := -INF
	var y := agua + 0.5
	while y < tope - 0.3:
		var roda := _roda_a(e, y, proa_caja)
		if roda > mejor_roda:
			mejor_roda = roda
			mejor_y = y
		y += 0.25
	if not m.mayor_que(mejor_roda - proa_caja, 0.3, "hay aire entre la roda y la caja",
			"roda %.2f, caja %.2f, a %.2f sobre el agua" % [mejor_roda, proa_caja, mejor_y - agua]):
		return
	var g := await _tiro_lateral(arbol, e, 1.0, mejor_y, (mejor_roda + proa_caja) * 0.5, 0.0,
		null, 0.0)
	m.comprobar(not _es_de(g.get("contra"), e),
		"una bala que cruza la caja por donde no hay casco no toca el barco", "%s" % g)
	var integ: Dictionary = e.get("integridad")
	m.comprobar(integ.values().all(func(v): return float(v) == 1.0), "ni lo daña", "%s" % integ)


## La primera z, desde la cara de proa de la caja hacia popa, en que una recta de través a la
## altura `y` (ejes del barco) corta la madera del casco o de la cubierta.
static func _roda_a(e: Node3D, y: float, proa_caja: float) -> float:
	var tris := PackedVector3Array()
	for nombre in ["casco_lod0", "cubierta_min", "bodega"]:
		for mi in e.find_children(nombre, "MeshInstance3D", true, false):
			var malla := mi as MeshInstance3D
			var tr := e.global_transform.affine_inverse() * malla.global_transform
			var caras := malla.mesh.get_faces()
			for i in range(0, caras.size(), 3):
				var a := tr * caras[i]
				var b := tr * caras[i + 1]
				var c := tr * caras[i + 2]
				if minf(a.y, minf(b.y, c.y)) <= y and maxf(a.y, maxf(b.y, c.y)) >= y 						and minf(a.z, minf(b.z, c.z)) < proa_caja + 2.0:
					tris.append_array([a, b, c])
	var z := proa_caja + 0.02
	while z < proa_caja + 2.0:
		for i in range(0, tris.size(), 3):
			if Geometry3D.segment_intersects_triangle(Vector3(3.0, y, z), Vector3(-3.0, y, z),
					tris[i], tris[i + 1], tris[i + 2]) != null:
				return z
		z += 0.02
	return z


# ── Aparejo: un tiro al palo baja el aparejo y la vela empuja menos ─────────
static func _aparejo(m: MarcoPruebas, arbol: SceneTree, e: Node3D) -> void:
	_reparar(e)
	if not m.comprobar(e.has_method("superficie_velica"), "el barco dice su superficie vélica útil"):
		return
	e.call("set_vela_delantera", true)
	e.call("set_vela_trasera", true)
	var sana := float(e.call("superficie_velica"))
	# El palo, por su colisionador: `PerchasSolidas` mide el eje de la malla al montar, y el tramo
	# central cae a media altura del mástil. El AABB de la malla no sirve: va con piel y su caja
	# está en ejes del esqueleto.
	var tramos := e.find_children("Percha_mastil_v3", "StaticBody3D", true, false)
	if not m.comprobar(not tramos.is_empty(), "el blanco tiene palo"):
		return
	var t4 := (tramos[0] as Node).get_node_or_null(^"T4") as Node3D
	if not m.comprobar(t4 != null, "con su tramo central"):
		return
	var centro := e.to_local(t4.global_position)
	var y := centro.y
	var g := await _tiro_lateral(arbol, e, 1.0, y, centro.z, centro.x)
	if not m.comprobar(_es_de(g.get("contra"), e), "el tiro al palo toca el barco", "%s" % g):
		return
	var integ: Dictionary = e.get("integridad")
	m.casi(float(integ["aparejo"]), 0.96, 0.001, "una rasa en el palo baja el aparejo")
	m.comprobar(float(integ["babor"]) == 1.0 and float(integ["estribor"]) == 1.0
		and float(integ["proa"]) == 1.0 and float(integ["popa"]) == 1.0,
		"y no el casco", "%s" % integ)
	m.comprobar(_vias(e) == 0, "ni abre vía")
	m.casi(float(e.call("superficie_velica")), sana * 0.96, 0.001,
		"el aparejo tocado da menos superficie de vela")
	# La palanqueta es para el aparejo: rompe más que la rasa.
	var M = load(RUTA_MUNICION)
	if m.comprobar(M != null, "existe la clase Municion"):
		var antes := float((e.get("integridad") as Dictionary)["aparejo"])
		var g2 := await _tiro_lateral(arbol, e, 1.0, y, centro.z, centro.x, M.de("palanqueta"))
		if m.comprobar(_es_de(g2.get("contra"), e), "la palanqueta al palo toca el barco"):
			var baja := antes - float((e.get("integridad") as Dictionary)["aparejo"])
			m.mayor_que(baja, 0.04 * 2.0, "la palanqueta rompe más aparejo que la rasa",
				"baja %.3f" % baja)


# ── HUD: la vía de agua y la munición cargada se ven ────────────────────────
static func _hud(m: MarcoPruebas, arbol: SceneTree, mio: Node3D) -> void:
	var siluetas := arbol.current_scene.find_children("Danos", "Control", true, false)
	var paneles := arbol.current_scene.find_children("Bateria", "Control", true, false)
	if not m.comprobar(not siluetas.is_empty() and not paneles.is_empty(), "el HUD está montado"):
		return
	var sil := siluetas[0]
	var pan := paneles[0]
	if not m.comprobar(sil.has_method("vias_en") and "municion_mostrada" in pan,
			"el HUD sabe pintar vías de agua y la munición cargada"):
		return
	_reparar(mio)
	var z := _z_de_zona(mio, 0.5)
	var g := await _tiro_lateral(arbol, mio, -1.0, _y_agua_local(mio, Vector3(0, 0, z)) + 0.10, z)
	if m.comprobar(_es_de(g.get("contra"), mio), "un tiro a la flotación de babor del jugador"):
		await arbol.process_frame
		m.comprobar(int(sil.call("vias_en", "babor")) == 1 and int(sil.call("vias_en", "estribor")) == 0,
			"la silueta marca la vía en babor", "%d / %d" % [int(sil.call("vias_en", "babor")),
				int(sil.call("vias_en", "estribor"))])
	mio.set("modo_battle", true)
	for tipo in ["palanqueta", "metralla", "rasa"]:
		mio.set("municion_actual", tipo)
		await arbol.process_frame
		await arbol.process_frame
		m.comprobar(String(pan.get("municion_mostrada")) == tipo, "el panel muestra la %s" % tipo)
	mio.set("modo_battle", false)
	_reparar(mio)


# ── Hundimiento: más vías que bombas hunden el barco ────────────────────────
static func _hundimiento(m: MarcoPruebas, arbol: SceneTree, e: Node3D) -> void:
	_reparar(e)
	for f in [0.4, 0.5, 0.6]:
		var z := _z_de_zona(e, f)
		await _tiro_lateral(arbol, e, 1.0 if f != 0.5 else -1.0,
			_y_agua_local(e, Vector3(0, 0, z)) + 0.10, z)
	if not m.comprobar(_vias(e) == 3, "tres tiros a la flotación, tres vías",
			"%d" % _vias(e)):
		return
	var a0 := _num(e, "agua_embarcada")
	await _esperar(arbol, 3.0)
	var a1 := _num(e, "agua_embarcada")
	m.mayor_que(a1 - a0, 0.01, "con tres vías las bombas no dan abasto y entra agua",
		"%.3f → %.3f" % [a0, a1])
	# Se acelera el caudal para no esperar un minuto: es un parámetro del escenario, no un umbral.
	e.set("caudal_via", 0.5)
	var t := 0.0
	while t < 15.0 and not _num(e, "hundido") > 0.0:
		t += arbol.root.get_process_delta_time()
		await arbol.process_frame
	m.comprobar(_num(e, "hundido") > 0.0, "al llenarse se hunde", "%.1f s" % t)
	await _esperar(arbol, 8.0)
	var r := float(e.call("altura_regala_en", e.global_position))
	var mar := Oleaje.altura_en(Vector2(e.global_position.x, e.global_position.z))
	m.menor_que(r, mar, "y la regala acaba bajo el agua", "regala %.2f, mar %.2f" % [r, mar])


# ── Utilidades ───────────────────────────────────────────────────────────────
## Un tiro que llega al punto (`x_obj`, `y`, `z`) en ejes del barco desde `DISTANCIA_TIRO` por la
## banda `lado` (+1 estribor, −1 babor). Sin `x_obj` apunta al COSTADO en la flotación, que es lo
## primero que encuentra. Sale 2,5 m más alto y baja: un tiro rasante a ras de agua podría morir
## en una cresta antes de llegar, y eso mediría el mar y no el impacto.
static func _tiro_lateral(arbol: SceneTree, e: Node3D, lado: float, y: float, z: float,
		x_obj := NAN, municion = null, subida := 2.5) -> Dictionary:
	if is_nan(x_obj):
		x_obj = _semi_manga(e, z) * lado
	var hasta := e.to_global(Vector3(x_obj, y, z))
	var desde := e.to_global(Vector3(DISTANCIA_TIRO * lado, y + subida, z))
	var vel := _velocidad_para(desde, hasta)
	var b := Bala.new()
	b.name = "BalaDePrueba"
	var sale := {}
	b.impacto.connect(func(donde: Vector3, contra: Node):
		sale["donde"] = donde
		sale["contra"] = contra)
	arbol.current_scene.add_child(b)
	if municion != null:
		b.call("lanzar", desde, vel, Oleaje.nivel, municion)
	else:
		b.lanzar(desde, vel, Oleaje.nivel)
	var t := 0.0
	while sale.is_empty() and t < 4.0:
		t += arbol.root.get_process_delta_time()
		await arbol.process_frame
	await arbol.process_frame
	return sale


static func _velocidad_para(desde: Vector3, hasta: Vector3) -> Vector3:
	var d := hasta - desde
	var tt := Vector2(d.x, d.z).length() / VEL
	return d / tt + Vector3.UP * (0.5 * G * tt)


## z, en ejes del barco, de la fracción `f` de su eslora en la flotación (0 = roda, 1 = codaste).
static func _z_de_zona(e: Node3D, f: float) -> float:
	var s: Dictionary = e.call("silueta_de_flotacion")
	return lerpf(float(s["lo"]), float(s["hi"]), f)


## Medio ancho del casco en la flotación a una z de sus ejes.
static func _semi_manga(e: Node3D, z: float) -> float:
	var s: Dictionary = e.call("silueta_de_flotacion")
	var a: PackedFloat32Array = s["ancho"]
	var f := clampf((z - float(s["lo"])) / (float(s["hi"]) - float(s["lo"])), 0.0, 1.0)
	var k := f * float(a.size() - 1)
	var i := mini(int(k), a.size() - 2)
	return lerpf(a[i], a[i + 1], k - float(i))


## Altura de la lámina en ejes del barco sobre un punto suyo.
static func _y_agua_local(e: Node3D, p_local: Vector3) -> float:
	var g := e.to_global(p_local)
	return e.to_local(Vector3(g.x, Oleaje.altura_en(Vector2(g.x, g.z)), g.z)).y


## Las llamadas al modelo de daños pasan por aquí para que, sin él, cada escenario FALLE en su
## comprobación y no se corte con un error de llamada a un método que no existe.
static func _reparar(b: Node) -> void:
	if b.has_method("reparar"):
		b.call("reparar")


static func _vias(b: Node) -> int:
	return int(b.call("vias_de_agua")) if b.has_method("vias_de_agua") else -1


static func _num(b: Node, prop: String) -> float:
	var v = b.get(prop)
	return float(v) if v != null else NAN


static func _es_de(n, barco: Node) -> bool:
	var x: Node = n as Node if n is Node else null
	while x != null:
		if x == barco:
			return true
		x = x.get_parent()
	return false


static func _esperar(arbol: SceneTree, s: float) -> void:
	var t := 0.0
	while t < s:
		t += arbol.root.get_process_delta_time()
		await arbol.process_frame


static func _viento(_arbol: SceneTree) -> void:
	Viento.direccion_base = Vector3(1, 0, 0)
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	Viento.fuerza_base = 1.0


static func _soltar_blanco(arbol: SceneTree, mio: Node3D) -> Node3D:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	if esc == null:
		return null
	var b := esc.instantiate() as Node3D
	b.name = "Blanco"
	mio.get_parent().add_child(b)
	b.remove_from_group("barco_activo")
	b.global_position = mio.global_position + Vector3(0.0, 0.0, 120.0)
	b.global_position.y = mio.global_position.y
	b.set("anclado", true)
	for i in 180:
		await arbol.process_frame
	return b


static func _retirar(b: Node3D) -> void:
	if b != null and is_instance_valid(b):
		var p := b.get_parent()
		if p != null:
			p.remove_child(b)
		b.queue_free()
