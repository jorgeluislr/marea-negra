class_name MapaTest
extends RefCounted

## Paquete `mapa`: las islas como datos, su carga por distancia y la carta.
##
## Al gestor y a la carta se les llama por GRUPO y por nombre de método, no por su clase: así este
## paquete compila aunque falten, y lo que sale en rojo es la comprobación y no la batería entera
## caída por un error de parseo (ver la nota de `MarcoPruebas.menor_que`).

const ARCHIPIELAGO := "res://assets/islas/archipielago.res"


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("mapa")
	var arch := load(ARCHIPIELAGO) as Archipielago if ResourceLoader.exists(ARCHIPIELAGO) else null
	if not m.comprobar(arch != null and not arch.islas.is_empty(),
			"el archipiélago está en disco y tiene islas"):
		return
	_datos(m, arch)
	await _relieve(m, arbol, arch)
	await _carta(m, arbol, arch)
	await _flechas(m, arbol)


## Lo que se guarda de cada isla y lo que se puede preguntar sin cargarla.
##
## Son dos mil islas: las comprobaciones de todas van AGREGADAS en una línea cada una (cada línea de
## consola cuesta 15-45 ms aquí, ver la memoria consola-cuesta-frames) y dicen cuántas fallan y cuál
## es la primera.
static func _datos(m: MarcoPruebas, arch: Archipielago) -> void:
	m.mayor_que(float(arch.islas.size()), 1000.0, "el archipiélago trae las costas del Caribe")
	var fuera := []
	var sin_costa := []
	var sin_celda := []
	for isla in arch.islas:
		if not arch.mundo.has_point(isla.posicion):
			fuera.append(isla.nombre)
		if isla.contorno.size() < 3:
			sin_costa.append(isla.nombre)
		if not arch.islas_en_celda(arch.celda_de(isla.posicion)).has(isla):
			sin_celda.append(isla.nombre)
	m.comprobar(fuera.is_empty(), "todas caen dentro del mapa", "%d fuera %s" % [fuera.size(), str(fuera.slice(0, 3))])
	m.comprobar(sin_costa.is_empty(), "todas tienen línea de costa", "%d sin ella" % sin_costa.size())
	m.comprobar(sin_celda.is_empty(), "todas están en la celda de su posición", "%d no" % sin_celda.size())

	# La escala, contra la geografía de verdad: Jamaica mide 235 km de este a oeste, que a 1/25 son
	# 9,4 km, y Norman Island está en 18,317 N 64,617 W. Si la proyección o la escala estuvieran mal,
	# esto es lo que se movería.
	var jam := _isla(arch, "Jamaica")
	if m.comprobar(jam != null, "Jamaica está en el archipiélago"):
		var r := jam.limites()
		m.casi(r.size.x / 1000.0, 9.2, 0.6, "Jamaica mide lo que mide a 1/25 (km de este a oeste)")
		m.menor_que(r.get_center().distance_to(arch.de_lat_lon(18.12, -77.3)), 1500.0,
			"y está donde dicen sus coordenadas (m)")
	var nor := _isla(arch, "Norman Island")
	if m.comprobar(nor != null, "Norman Island está en el archipiélago"):
		m.menor_que(nor.limites().get_center().distance_to(arch.de_lat_lon(18.317, -64.617)), 150.0,
			"y está donde dicen sus coordenadas (m)")


static func _isla(arch: Archipielago, nombre: String) -> Isla:
	for isla in arch.islas:
		if isla.nombre == nombre:
			return isla
	return null


## El relieve: las alturas por celdas de 1 km. Que la costa del relieve sea la de la carta, que haya
## tierra donde hay isla y fondo donde no, y que el gestor ponga y quite cada celda sin tirones.
static func _relieve(m: MarcoPruebas, arbol: SceneTree, arch: Archipielago) -> void:
	var g := arbol.get_first_node_in_group("tierra")
	if not m.comprobar(g != null, "hay un gestor de tierra en el mundo"):
		return
	var rel: Object = g.get("relieve")
	if not m.comprobar(rel != null, "con su relieve por celdas"):
		return
	var t := 0.0
	while t < 10.0 and not bool(rel.call("listo")):
		await arbol.process_frame
		t += arbol.root.get_process_delta_time()
	m.comprobar(bool(rel.call("listo")), "el índice del relieve se carga (en otro hilo)", "%.1f s" % t)
	var nor := _isla(arch, "Norman Island")
	var c: Vector2i = rel.call("celda_de", nor.limites().get_center())
	m.comprobar(bool(rel.call("tiene", c)), "la celda de Norman Island tiene relieve", str(c))

	# La costa del relieve es la de la carta: altura cero en los vértices del contorno. Tierra dentro
	# de la isla, fondo a 250 m de ella.
	var peor := 0.0
	for k in nor.contorno:
		peor = maxf(peor, absf(float(rel.call("altura_en", nor.posicion + k))))
	m.menor_que(peor, 0.6, "en la costa de Norman el relieve está a cota cero (m)")
	var cumbre := -INF
	for k in nor.contorno:
		cumbre = maxf(cumbre, float(rel.call("altura_en", nor.posicion + k * 0.3)))
	m.mayor_que(cumbre, 3.0, "Norman asoma sobre el agua (m)")
	m.menor_que(float(rel.call("altura_en", nor.limites().get_center() + Vector2(0, -250))), -3.0,
		"a 250 m de su costa ya es fondo (m)")

	var mat := g.get("material") as ShaderMaterial
	if m.comprobar(mat != null, "la tierra tiene un material compartido"):
		await arbol.process_frame
		m.casi(float(mat.get_shader_parameter("radio_tierra")), Horizonte.radio_tierra, 1.0,
			"y se hunde con el mismo radio que el agua y el barco")
	m.comprobar(g.call("foco_actual") == UtilesPruebas.barco(arbol),
		"sin foco puesto, sigue al barco activo")

	# Lejos: la celda no está; cerca: se construye en un hilo y entra sin tirón; lejos otra vez: se
	# suelta sin tirón. El foco va en coordenadas LOCALES (las del árbol): el gestor las pasa a
	# absolutas con `Origen`.
	var foco := Node3D.new()
	arbol.current_scene.add_child(foco)
	g.set("foco", foco)
	var centro := nor.limites().get_center()
	var o := arbol.root.get_node_or_null("Origen")
	var local := Vector3(centro.x, 0, centro.y) - (Vector3(o.x, 0, o.z) if o != null else Vector3.ZERO)
	foco.global_position = local + Vector3(30000, 0, 0)
	for i in 40:
		await arbol.process_frame
	m.comprobar(g.call("estado_celda", c) == "fuera", "lejos, la celda no está cargada",
		str(g.call("estado_celda", c)))
	await _sin_escribir(arbol)
	foco.global_position = local
	var lento := 0.0
	t = 0.0
	while t < 10.0 and g.call("estado_celda", c) != "cargada":
		await arbol.process_frame
		var dt := arbol.root.get_process_delta_time()
		lento = maxf(lento, dt)
		t += dt
	for i in 20:
		await arbol.process_frame
		lento = maxf(lento, arbol.root.get_process_delta_time())
	m.comprobar(g.call("estado_celda", c) == "cargada", "al acercarse, la celda se carga", "%.2f s" % t)
	m.menor_que(lento * 1000.0, 34.0, "y cargar las celdas cercanas no da tirones (ms del peor frame)")
	var det := g.call("nodo_celda", c) as Node3D
	var malla: Mesh = null
	if m.comprobar(det != null and det.is_inside_tree(), "su malla de detalle está en el mundo"):
		m.comprobar(not det.find_children("*", "CollisionShape3D", true, false).is_empty(),
			"y de cerca tiene colisión")
		for mi in det.find_children("*", "MeshInstance3D", true, false):
			malla = (mi as MeshInstance3D).mesh
	m.mayor_que(float(g.call("siluetas")), 0.0, "y hay siluetas lejanas puestas")
	var sc := g.call("silueta_celda", c) as Node3D
	m.comprobar(sc == null or not sc.visible, "y la de esta celda no se dibuja encima del detalle")

	await _sin_escribir(arbol)
	foco.global_position = local + Vector3(30000, 0, 0)
	lento = 0.0
	t = 0.0
	while t < 5.0 and g.call("estado_celda", c) != "fuera":
		await arbol.process_frame
		var dt := arbol.root.get_process_delta_time()
		lento = maxf(lento, dt)
		t += dt
	m.comprobar(g.call("estado_celda", c) == "fuera", "al alejarse, la celda se suelta", "%.2f s" % t)
	m.comprobar(det == null or not is_instance_valid(det), "y su malla se libera")
	m.menor_que(lento * 1000.0, 34.0, "y soltarla no da tirones (ms del peor frame)")
	if malla != null:
		# Las caras miran hacia ARRIBA. Godot dibuja la cara cuyo (B−A)×(C−A) apunta EN CONTRA de la
		# cámara (sentido horario visto desde ella, como dice su documentación): en un terreno, ese
		# producto apunta abajo. Medido el 17-10-2026 mirando desde arriba; a ras de agua engaña.
		# Va DESPUÉS de las ventanas de tiempo: leer la malla espera al servidor de render.
		var arr := malla.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var buenas := 0
		for k in range(0, ix.size(), 3):
			var n := (v[ix[k + 1]] - v[ix[k]]).cross(v[ix[k + 2]] - v[ix[k]])
			buenas += 1 if n.y < 0.0 else 0
		m.mayor_que(float(buenas) / (ix.size() / 3), 0.99,
			"las caras del terreno miran hacia arriba (fracción)")
		var sup := RenderingServer.mesh_get_surface(malla.get_rid(), 0)
		m.mayor_que(float((sup.get("lods", []) as Array).size()), 1.0,
			"el terreno lleva LOD automático", "%d niveles" % (sup.get("lods", []) as Array).size())
	g.set("foco", null)
	foco.queue_free()
	await arbol.process_frame


## La carta: se abre con M, centrada en el barco; se arrastra con el ratón y se acerca con la
## rueda; la marca del barco está donde el barco y apunta a su proa.
##
## Dónde DEBERÍA caer cada cosa se calcula aquí, a partir de la vista que la carta declara
## (`vista_centro`, `metros_por_pixel`) y de su ventana en pantalla; no se le pregunta a la carta
## dónde ha dibujado la marca para compararlo consigo mismo.
static func _carta(m: MarcoPruebas, arbol: SceneTree, arch: Archipielago) -> void:
	var c := arbol.get_first_node_in_group("carta")
	if not m.comprobar(c != null, "hay una carta en el mundo"):
		return
	m.comprobar(not bool(c.get("abierta")), "la carta empieza cerrada")
	var raton_antes := Input.mouse_mode
	# Abrir la carta navegando no puede dar un tirón: las velas se rompen con frames largos.
	await _sin_escribir(arbol)
	await UtilesPruebas.tecla(arbol, KEY_M)
	var peor := 0.0
	for i in 30:
		await arbol.process_frame
		peor = maxf(peor, arbol.root.get_process_delta_time())
	m.comprobar(bool(c.get("abierta")), "M abre la carta")
	m.menor_que(peor * 1000.0, 34.0, "y abrirla no da tirones (ms del peor frame)")
	m.comprobar(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "con la carta abierta el ratón se ve")
	var carta := c.get("carta") as Carta
	if not m.comprobar(carta != null, "con su recurso de carta"):
		return
	_marco_de_la_imagen(m, carta)
	var costas := c.get("costas") as MeshInstance2D
	m.comprobar(costas != null and costas.mesh != null, "la carta dibuja las costas de todo el archipiélago")
	var ven: Rect2 = c.call("interior")
	var pantalla := arbol.root.get_visible_rect().size
	m.mayor_que(ven.get_area() / (pantalla.x * pantalla.y), 0.5,
		"la ventana de la carta ocupa la mayor parte de la pantalla (fracción)")

	var b := UtilesPruebas.barco(arbol)
	var marca := c.get("marca") as Control
	if b == null or not m.comprobar(marca != null and marca.visible, "la marca del barco se ve"):
		return
	var xz := Vector2(b.global_position.x, b.global_position.z)
	m.menor_que(marca.global_position.distance_to(ven.get_center()), 2.0,
		"al abrirla, la carta se centra en el barco (px)")
	var proa := -b.global_transform.basis.z
	var marca_proa := Vector2(0, -1).rotated(marca.rotation)
	m.menor_que(absf(rad_to_deg(marca_proa.angle_to(Vector2(proa.x, proa.z).normalized()))), 2.0,
		"y la marca apunta a su proa (grados)")

	# La rosa de los vientos: pequeña, dentro de la ventana y quieta en su esquina.
	var rosa := c.get("rosa") as Control
	var rosa_antes := Vector2.ZERO
	if m.comprobar(rosa != null and rosa.visible, "la carta lleva su rosa de los vientos"):
		var rr := rosa.get_global_rect()
		m.comprobar(ven.encloses(rr), "dentro de la ventana", "%s en %s" % [str(rr), str(ven)])
		m.menor_que(rr.size.y / ven.size.y, 0.2, "y pequeña (fracción del alto de la ventana)")
		m.comprobar(rr.get_center().x > ven.get_center().x + ven.size.x * 0.3
			or rr.get_center().x < ven.get_center().x - ven.size.x * 0.3,
			"y arrimada a una esquina")
		rosa_antes = rr.position

	# Arrastrar: la carta va con el ratón. Arrastrar hacia la derecha trae lo que estaba a la
	# izquierda, así que el centro de la vista se mueve al revés que el ratón.
	var mpp: float = c.get("metros_por_pixel")
	var c0: Vector2 = c.get("vista_centro")
	var tiron := Vector2(120, -80)
	await _arrastrar(arbol, ven.get_center(), tiron)
	var c1: Vector2 = c.get("vista_centro")
	m.casi(c1.distance_to(c0 - tiron * mpp), 0.0, mpp,
		"arrastrar desplaza la carta con el ratón (m)")
	xz = Vector2(b.global_position.x, b.global_position.z)
	var esperado := ven.get_center() + (xz - c1) / mpp
	m.menor_que(marca.global_position.distance_to(esperado), 2.0,
		"y la marca del barco sigue sobre el barco (px)")
	if rosa != null:
		m.casi(rosa.get_global_rect().position.distance_to(rosa_antes), 0.0, 0.5,
			"y la rosa no se mueve con la carta (px)")

	# La rueda acerca, y el punto que está bajo el ratón no se mueve.
	var p := ven.get_center() + Vector2(150, 60)
	var bajo := c1 + (p - ven.get_center()) * mpp
	await _rueda(arbol, p, MOUSE_BUTTON_WHEEL_UP)
	var mpp2: float = c.get("metros_por_pixel")
	var c2: Vector2 = c.get("vista_centro")
	m.menor_que(mpp2, mpp * 0.95, "la rueda hacia arriba acerca la carta (m por píxel)")
	m.menor_que((c2 + (p - ven.get_center()) * mpp2).distance_to(bajo), mpp2 * 2.0,
		"y lo que está bajo el ratón se queda bajo el ratón (m)")
	await _rueda(arbol, p, MOUSE_BUTTON_WHEEL_DOWN)
	m.casi(float(c.get("metros_por_pixel")), mpp, mpp * 0.01, "y hacia abajo vuelve a alejarla")

	# No se puede arrastrar la carta fuera del mundo.
	await _arrastrar(arbol, ven.get_center(), Vector2(-4000, 3000))
	m.comprobar(arch.mundo.grow(1.0).has_point(c.get("vista_centro")),
		"arrastrar no saca la vista del mundo", str(c.get("vista_centro")))

	await UtilesPruebas.tecla(arbol, KEY_M)
	await arbol.process_frame
	m.comprobar(not bool(c.get("abierta")), "M la vuelve a cerrar")
	m.comprobar(Input.mouse_mode == raton_antes, "y el ratón vuelve a como estaba")
	# Y al volver a abrirla está otra vez sobre el barco, no donde se dejó arrastrada. (Al principio
	# el barco está casi en el centro del mundo, así que la primera apertura no lo distingue: esta sí,
	# porque la vista se ha llevado al borde.)
	await UtilesPruebas.tecla(arbol, KEY_M)
	await arbol.process_frame
	xz = Vector2(b.global_position.x, b.global_position.z)
	m.casi((c.get("vista_centro") as Vector2).distance_to(xz), 0.0, mpp * 2.0,
		"al reabrirla vuelve a centrarse en el barco (m)")
	await UtilesPruebas.tecla(arbol, KEY_M)
	await arbol.process_frame

	# Navegando lejos, el origen flotante RECENTRA el mundo cada 2 km: el barco vuelve a coordenadas
	# locales cerca de cero sin moverse de su sitio absoluto. La carta tiene que seguir mostrándolo
	# donde está de verdad. El usuario lo vio el 18-10-2026: rumbo a una isla del sur, al rato la
	# carta "volvía" a la salida. Se fuerza un recentrado de 3 km y se compara con lo ABSOLUTO.
	var org := arbol.root.get_node_or_null("Origen")
	if org != null:
		var antes: Vector3 = org.a_global(b.global_position)
		org.recentrar(Vector3(3000, 0, 0))
		await arbol.physics_frame
		await UtilesPruebas.tecla(arbol, KEY_M)
		await arbol.process_frame
		await arbol.process_frame
		m.casi((c.get("vista_centro") as Vector2).distance_to(Vector2(antes.x, antes.z)), 0.0, mpp * 2.0,
			"tras un recentrado del mundo, la carta sigue sobre el barco ABSOLUTO (m)")
		m.menor_que(marca.global_position.distance_to(ven.get_center()), 2.0,
			"y la marca también (px)")
		await UtilesPruebas.tecla(arbol, KEY_M)
		await arbol.process_frame
		org.recentrar(Vector3(-3000, 0, 0))
		await arbol.physics_frame


## Las flechas del viento: junto al barco, fuera de su casco y a ras de agua, también después de
## que el origen flotante recentre el mundo. El usuario vio las dos cosas el 18-10-2026: se
## perdían al rato de navegar, y con la balandra caían encima del barco (la distancia era la de la
## lancha). Y la carta no se descuadra por recentrar muchas veces seguidas.
static func _flechas(m: MarcoPruebas, arbol: SceneTree) -> void:
	var f := arbol.get_first_node_in_group("flechas_viento") as MultiMeshInstance3D
	var b := UtilesPruebas.barco(arbol)
	if not m.comprobar(f != null and f.multimesh != null and b != null, "hay flechas del viento"):
		return
	var sil: Dictionary = b.call("silueta_de_flotacion")
	var media_eslora := (float(sil["hi"]) - float(sil["lo"])) * 0.5
	var tam: float = f.get("tam")
	var org := arbol.root.get_node_or_null("Origen")
	for paso in ["al empezar", "tras recentrar 3 km"]:
		if paso != "al empezar" and org != null:
			org.recentrar(Vector3(3000, 0, 0))
		for i in 3:
			await arbol.process_frame
		var p := f.global_transform * f.multimesh.get_instance_transform(0).origin
		var d := Vector2(p.x - b.global_position.x, p.z - b.global_position.z).length()
		m.mayor_que(d, media_eslora + tam * 0.5, "%s, las flechas no caen sobre el casco (m)" % paso,
			"media eslora %.1f" % media_eslora)
		m.menor_que(d, media_eslora + tam * 3.0, "%s, y están junto a él (m)" % paso)
		m.casi(p.y, Oleaje.nivel + float(f.get("altura")), 0.05, "%s, y a ras de agua (m)" % paso)
	if org != null:
		org.recentrar(Vector3(-3000, 0, 0))
		await arbol.physics_frame

	# Muchos recentrados seguidos: 40 de 2 km, 80 km de navegación. La posición absoluta del barco
	# es origen (metros enteros, doble precisión) + local (pequeña): no tiene por qué derivar.
	var c := arbol.get_first_node_in_group("carta")
	if org == null or c == null:
		return
	# Un marcador QUIETO en el mundo: el barco navega entre recentrado y recentrado y su posición
	# cambia de verdad, así que la deriva se mide en algo que no se mueve.
	var quieto := Node3D.new()
	arbol.current_scene.add_child(quieto)
	quieto.global_position = Vector3(123.4, 0, 567.8)
	var antes: Vector3 = org.a_global(quieto.global_position)
	for i in 40:
		org.recentrar(Vector3(2000, 0, 0))
		await arbol.physics_frame
	var despues: Vector3 = org.a_global(quieto.global_position)
	m.casi(Vector2(despues.x, despues.z).distance_to(Vector2(antes.x, antes.z)), 0.0, 0.01,
		"tras 40 recentrados (80 km) un punto quieto sigue en su sitio absoluto (m)")
	quieto.queue_free()
	await UtilesPruebas.tecla(arbol, KEY_M)
	await arbol.process_frame
	await arbol.process_frame
	var ahora: Vector3 = org.a_global(b.global_position)
	m.casi((c.get("vista_centro") as Vector2).distance_to(Vector2(ahora.x, ahora.z)), 0.0, 0.05,
		"y la carta sigue sobre el barco absoluto (m)")
	await UtilesPruebas.tecla(arbol, KEY_M)
	await arbol.process_frame
	for i in 40:
		org.recentrar(Vector3(-2000, 0, 0))
		await arbol.physics_frame

static func _arrastrar(arbol: SceneTree, desde: Vector2, cuanto: Vector2) -> void:
	var pos := desde
	_boton(MOUSE_BUTTON_LEFT, true, pos)
	await arbol.process_frame
	for i in 4:
		var mv := InputEventMouseMotion.new()
		mv.relative = cuanto / 4.0
		pos += cuanto / 4.0
		mv.position = pos
		mv.global_position = pos
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mv)
		await arbol.process_frame
	_boton(MOUSE_BUTTON_LEFT, false, pos)
	await arbol.process_frame
	await arbol.process_frame


static func _rueda(arbol: SceneTree, donde: Vector2, boton: MouseButton) -> void:
	_boton(boton, true, donde)
	_boton(boton, false, donde)
	await arbol.process_frame
	await arbol.process_frame


static func _boton(boton: MouseButton, pulsado: bool, donde: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = boton
	e.pressed = pulsado
	e.position = donde
	e.global_position = donde
	Input.parse_input_event(e)


## Que el interior del marco (`Carta.rect_interior`) caiga SOBRE la línea interior que está dibujada
## en la imagen. El marco se dibuja en nueve partes cortadas por ese rectángulo: si no cae en la
## línea, las esquinas se cortan por en medio del adorno y los lados se repiten descuadrados. Se
## mira en los píxeles: a lo largo de cada borde, en su tramo central, casi todo tiene que ser
## tinta; un píxel más adentro ya es mar.
static func _marco_de_la_imagen(m: MarcoPruebas, carta: Carta) -> void:
	if not m.comprobar(carta.marco != null, "la carta lleva su marco"):
		return
	var img := carta.marco.get_image()
	img.decompress()
	var r := Rect2i(carta.rect_interior)
	m.comprobar(Rect2i(Vector2i.ZERO, img.get_size()).encloses(r), "y su rectángulo cabe en ella",
		"%s en %s" % [str(r), str(img.get_size())])
	var bordes := {
		"izquierdo": [Vector2i(r.position.x, 0), Vector2i(0, 1)],
		"derecho": [Vector2i(r.end.x, 0), Vector2i(0, 1)],
		"superior": [Vector2i(0, r.position.y), Vector2i(1, 0)],
		"inferior": [Vector2i(0, r.end.y), Vector2i(1, 0)],
	}
	for nombre in bordes:
		var fijo: Vector2i = bordes[nombre][0]
		var dir: Vector2i = bordes[nombre][1]
		var lado := r.size.y if dir.y == 1 else r.size.x
		var inicio := r.position.y if dir.y == 1 else r.position.x
		var tinta := 0
		var n := 0
		for k in range(int(lado * 0.3), int(lado * 0.7)):
			var p := fijo + dir * (inicio + k)
			# El borde puede caer en cualquiera de los dos píxeles de grosor de la línea.
			var oscuro := false
			for d: int in [-1, 0, 1]:
				var q: Vector2i = p + Vector2i(dir.y, dir.x) * d
				if img.get_pixelv(q).get_luminance() < 0.62:
					oscuro = true
			tinta += 1 if oscuro else 0
			n += 1
		m.mayor_que(float(tinta) / n, 0.75,
			"el borde %s de la carta cae sobre la línea del marco (fracción de tinta)" % nombre)


## Deja pasar los frames que absorben lo que la prueba acaba de escribir en consola.
static func _sin_escribir(arbol: SceneTree) -> void:
	for i in 10:
		await arbol.process_frame
