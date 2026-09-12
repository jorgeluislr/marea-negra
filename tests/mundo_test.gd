class_name MundoTest
extends RefCounted

## Paquete `mundo`: el viento, el selector de embarcación y lo que se rompió al cambiar de
## barco y volver.


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("mundo")

	# --- Viento: lo leen todas las telas cada frame.
	Viento.bamboleo_dir = 0.12
	Viento.variacion_fuerza = 0.45
	var d0: Vector3 = Viento.direccion
	var f_min := INF
	var f_max := -INF
	for i in 240:
		f_min = minf(f_min, Viento.fuerza)
		f_max = maxf(f_max, Viento.fuerza)
		await arbol.process_frame
	m.casi(Viento.direccion.length(), 1.0, 0.001, "la dirección del viento es unitaria")
	m.comprobar(f_max > f_min, "la fuerza varía en ráfagas", "%.2f a %.2f" % [f_min, f_max])
	m.comprobar(absf(Viento.direccion.y) < 0.001, "y sopla en horizontal")

	# --- Selector de embarcación: TAB cambia de barco y el grupo queda con UNO solo. Si queda
	# más de uno, el mar, el HUD y las flechas siguen al que no toca.
	var antes := UtilesPruebas.barco(arbol)
	var nombre_antes := str(antes.get("nombre"))
	# Identidad de los aparejos de este barco, para saber luego si el barco reinstanciado
	# recibió los SUYOS o se le colaron los del anterior.
	var ids_antes := []
	for h in antes.get_children():
		if h.has_method("izar") and h.get("aparejo") != null:
			ids_antes.append((h.get("aparejo") as Resource).get_instance_id())
	await UtilesPruebas.tecla(arbol, KEY_TAB)
	for i in 120:
		await arbol.process_frame
	var ahora := UtilesPruebas.barco(arbol)
	m.comprobar(arbol.get_nodes_in_group("barco_activo").size() == 1,
		"tras TAB hay exactamente un barco activo",
		"%d" % arbol.get_nodes_in_group("barco_activo").size())
	m.comprobar(ahora != antes and str(ahora.get("nombre")) != nombre_antes,
		"y es otro barco", "%s -> %s" % [nombre_antes, str(ahora.get("nombre"))])

	# La vela del casco de una pieza (lancha/barca/goleta) se iza por el mismo camino que la
	# física, aunque su paño lo dibuje el shader.
	var velas_shader := []
	for h in ahora.get_children():
		if h is VelaShader:
			velas_shader.append(h)
	if m.comprobar(velas_shader.size() == 1, "el casco de una pieza trae su VelaShader"):
		var v: Node = velas_shader[0]
		var apa: Variant = v.get("aparejo")
		m.comprobar(apa != null, "con su aparejo")
		m.comprobar(v.esta_izada(), "y arranca izada")

	# --- Dar la vuelta a la flota y volver. Aquí saltó el bug del aparejo compartido: el
	# ángulo de trimado del barco anterior sobrevivía y la mayor abría estirada al 36 %.
	#
	# El viento ROLA entre cambio y cambio a propósito. Con viento fijo todos los barcos trimaban
	# al mismo ángulo, el estado heredado coincidía con el que tocaba y la prueba pasaba aunque
	# el recurso estuviese compartido: no valía para nada.
	for i in 3:
		Viento.direccion_base = Vector3(1, 0, 0) if i % 2 == 0 else Vector3(-1, 0, 0)
		await UtilesPruebas.tecla(arbol, KEY_TAB)
		for j in 120:
			await arbol.process_frame
	var vuelta := UtilesPruebas.barco(arbol)
	m.comprobar(str(vuelta.get("nombre")) == nombre_antes,
		"la vuelta completa devuelve el barco de salida", str(vuelta.get("nombre")))
	# Un sub-recurso de escena se COMPARTE entre instancias salvo que sea local a ella, y el
	# aparejo guarda estado. Esta comprobación es la que de verdad ataja el bug: no depende de
	# que la física llegue a manifestarlo.
	var ids_ahora := []
	for h in vuelta.get_children():
		if h.has_method("izar") and h.get("aparejo") != null:
			ids_ahora.append((h.get("aparejo") as Resource).get_instance_id())
	var compartidos := 0
	for id in ids_ahora:
		if ids_antes.has(id):
			compartidos += 1
	m.comprobar(compartidos == 0 and not ids_ahora.is_empty(),
		"el barco reinstanciado trae SUS aparejos, no los del anterior",
		"%d de %d compartidos" % [compartidos, ids_ahora.size()])

	await UtilesPruebas.estabilizar(arbol, 3.0)
	for t in UtilesPruebas.telas(arbol):
		var e: Dictionary = await UtilesPruebas.estiramiento(arbol, t)
		if e.is_empty():
			continue
		var tope := 0.06 if t is BanderaFisica else 0.02
		m.menor_que(e["medio"], tope,
			"'%s' vuelve sin estirarse" % str(t.get("nombre_malla")))

	# --- El mar. Tres cosas que no se pueden ver de un vistazo y que, cuando fallan, fallan en
	# silencio: que el mar que se DIBUJA sea el mismo que el que se CALCULA, que la malla tenga
	# con qué dibujarlo, y que la mar responda al viento.
	await _mar(m, arbol)


## El mar: el espejo entre shader y GDScript, el mallado y el estado de la mar.
static func _mar(m: MarcoPruebas, arbol: SceneTree) -> void:
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.direccion_base = Vector3(1, 0, 0.3)
	Viento.fuerza_base = 1.0
	await arbol.process_frame
	await arbol.process_frame
	Oleaje.asentar()

	# --- El mar que se ve contra el que se calcula. La altura de la ola está escrita dos veces
	# —en `oleaje.gdshaderinc` y en el autoload— y si divergen el barco flota sobre olas
	# distintas de las que se ven sin que nada avise: ni error, ni aviso, solo un casco que sube
	# cuando el agua baja. Es EL riesgo de tener el oleaje en los dos sitios.
	var puntos := PackedVector2Array()
	var r := RandomNumberGenerator.new()
	r.seed = 20260911
	for i in 48:
		puntos.append(Vector2(r.randf_range(-60.0, 60.0), r.randf_range(-60.0, 60.0)))
	# 10 mm de tolerancia: el empaquetado del espejo redondea a 0,25 mm y los dos frames que
	# tarda en renderizarse mueven la ola corta otro tanto. Un signo cambiado o un tren de más
	# daría del orden de la amplitud, decímetros.
	for modo in [0, 1]:
		var reloj: float = Oleaje.t
		var shader: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(
			arbol, puntos, modo)
		var peor := 0.0
		for i in puntos.size():
			var d: Vector3 = Oleaje.desplazamiento(puntos[i], reloj)
			peor = maxf(peor, absf((d.y if modo == 0 else d.x) - shader[i]))
		m.menor_que(peor, 0.010,
			"el shader y GDScript dan el mismo %s de ola" % ["alto", "arrastre"][modo],
			"peor de %d puntos" % puntos.size())

	# --- Que haya malla con que dibujarla. El shader del agua tenía sus olas desde el primer
	# día y no se vieron nunca: el plano eran cuatro vértices en las esquinas, a 250 m.
	var agua := arbol.get_first_node_in_group("mar") as MeshInstance3D
	if m.comprobar(agua != null and agua.mesh != null, "el agua tiene malla"):
		var arr: Array = agua.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var g := agua.global_transform
		var centro := Vector2(agua.global_position.x, agua.global_position.z)
		var l: Array[float] = []
		for t in idx.size() / 3:
			var a := g * vs[idx[t * 3]]
			var b := g * vs[idx[t * 3 + 1]]
			var c := g * vs[idx[t * 3 + 2]]
			if Vector2((a.x + b.x + c.x) / 3.0, (a.z + b.z + c.z) / 3.0).distance_to(centro) > 25.0:
				continue
			l.append(a.distance_to(b))
			l.append(b.distance_to(c))
		l.sort()
		var celda: float = l[l.size() / 2] if not l.is_empty() else INF
		# Ocho puntos por ola en primer plano: con menos la ola sale poligonal, y por debajo de
		# dos lo que se ve no es la ola sino el patrón que hace con la rejilla.
		m.mayor_que(Oleaje.longitud_mas_corta() / maxf(celda, 0.0001), 8.0,
			"la malla resuelve la ola más corta en primer plano",
			"celda %.2f m" % celda)

	# --- La mar sigue al viento, y el arrastre horizontal sigue a la mar.
	#
	# Lo segundo es lo que caza el fallo que tuvo esto: en Gerstner el agua no solo sube y baja,
	# se corre hacia la cresta, y ese arrastre salía CONSTANTE —3,605 m, el mismo número en
	# calma que con viento fuerte— porque Q se calculó como el tope `1/(k·A·N)`, donde la
	# amplitud se cancela. Se veía desde cubierta como si el barco avanzase y retrocediera.
	var alturas := {}
	for f in [0.15, 1.8]:
		Viento.fuerza_base = f
		await arbol.process_frame
		await arbol.process_frame
		Oleaje.asentar()
		# Recorrido en el ESPACIO y no en el tiempo: la ola larga tarda 4,9 s en pasar, así que
		# un pico a pico medido en un punto durante segundo y medio depende de con qué fase
		# pillaste la ola y da un número distinto cada vez. Una rejilla de 120 m cubre tres
		# longitudes de la más larga de un solo golpe, y sale el mismo número siempre.
		var alto := -INF
		var bajo := INF
		var der := -INF
		var izq := INF
		for i in 24:
			for j in 24:
				var p := Vector2(float(i) * 5.0 - 60.0, float(j) * 5.0 - 60.0)
				var d: Vector3 = Oleaje.desplazamiento(p)
				alto = maxf(alto, d.y); bajo = minf(bajo, d.y)
				der = maxf(der, d.x); izq = minf(izq, d.x)
		alturas[f] = alto - bajo
		# El agua describe círculos: lo que se corre en horizontal no puede pasar de lo que sube.
		m.menor_que(der - izq, alto - bajo,
			"con viento %.2f el arrastre no pasa del alto de la ola" % f,
			"mar de %.2f m" % Oleaje.altura)
	m.mayor_que(float(alturas[1.8]) / maxf(float(alturas[0.15]), 0.001), 4.0,
		"la mar crece con el viento", "%.2f m a %.2f m" % [alturas[0.15], alturas[1.8]])

	# --- La altura se lee donde se pregunta. En Gerstner el punto que acaba sobre `q` no salió
	# de `q`: la ola lo arrastró. Sin resolver ese punto fijo la lectura se va media longitud de
	# onda en la cara de la ola, justo donde más cambia.
	Viento.fuerza_base = 1.0
	await arbol.process_frame
	Oleaje.asentar()
	var peor_vuelta := 0.0
	for i in 24:
		var q := puntos[i]
		var p := q
		for _j in 3:
			var d: Vector3 = Oleaje.desplazamiento(p)
			p = q - Vector2(d.x, d.z)
		var d2: Vector3 = Oleaje.desplazamiento(p)
		peor_vuelta = maxf(peor_vuelta, (p + Vector2(d2.x, d2.z)).distance_to(q))
	m.menor_que(peor_vuelta, 0.02, "la altura se lee en el punto que se pregunta",
		"el punto fijo cierra")

	# --- Las crestas avanzan, y avanzan LEJOS DEL ORIGEN igual que encima de él.
	#
	# Girar el campo de olas corre la fase de cada punto en `k·D·Δángulo`, con D su distancia al
	# origen del mundo, así que la cresta se desplaza a `D·Δángulo/s` encima de su velocidad
	# propia. Tomando la dirección instantánea del viento —que bambolea 0,12 rad a 0,08 Hz— la
	# cresta iba a sus 6 m/s en el origen, entre 0 y 12 a 100 m, y entre **−6 y +18** a 300: el
	# mar acelerándose según navegas y avanzando y retrocediendo. Se mide LEJOS a propósito:
	# encima del origen el efecto vale cero y todo parece correcto.
	Viento.bamboleo_dir = 0.12
	var centro := Vector2(300.0, 0.0)
	var rumbo := Vector2(Viento.direccion_base.x, Viento.direccion_base.z).normalized()
	var vs: Array[float] = []
	var antes := _cresta(centro, rumbo)
	var t := 0.0
	while t < 4.0:
		await arbol.process_frame
		var dt := arbol.root.get_process_delta_time()
		t += dt
		var ahora := _cresta(centro, rumbo)
		var v := (ahora - antes) / maxf(dt, 0.0001)
		antes = ahora
		# Un salto de una cresta a la siguiente no es velocidad: es el máximo cambiando de sitio.
		if absf(v) < 40.0:
			vs.append(v)
	vs.sort()
	m.mayor_que(vs[int(vs.size() * 0.05)] if not vs.is_empty() else -99.0, -0.5,
		"a 300 m del origen las crestas no retroceden",
		"mediana %.2f m/s" % (vs[vs.size() / 2] if not vs.is_empty() else 0.0))
	Viento.bamboleo_dir = 0.0

	await _horizonte(m, arbol)


## La curvatura: lo lejano se hunde, y se hunde IGUAL que el agua sobre la que flota.
##
## El agua se curva en `agua.gdshader` y el barco en `Barco._altura_de_flotacion()`. Son dos
## sitios otra vez, como el oleaje, y con la misma consecuencia si divergen: un barco lejano
## flotando por encima o por debajo de su propio mar, sin que nada avise.
static func _horizonte(m: MarcoPruebas, arbol: SceneTree) -> void:
	# Un barco APARTE, no el del jugador: al del jugador lo persigue la cámara y su distancia
	# nunca crece, que es justo lo que hay que medir aquí.
	var b := (load("res://scenes/barcos/balandra.tscn") as PackedScene).instantiate() as Node3D
	arbol.current_scene.add_child(b)
	b.set("anclado", true)
	for c in b.find_children("*", "Camera3D", true, false):
		c.queue_free()
	for i in 180:
		await arbol.process_frame

	var ojo := arbol.root.get_camera_3d()
	if ojo == null:
		b.queue_free()
		return
	var base: float = b.get("base_y")
	var alto: float = b.get("_alto")
	m.mayor_que(alto, 5.0, "el barco sabe lo que mide de alto", "%.2f m" % alto)

	for d in [2000.0, 20000.0]:
		b.global_position = Vector3(ojo.global_position.x + d, 0, ojo.global_position.z)
		# El reloj del bamboleo a cero: sus 15 cm tapan la curvatura a las distancias cortas.
		b.set("time", 0.0)
		await arbol.physics_frame
		await arbol.physics_frame
		var caida: float = base - b.global_position.y
		m.casi(caida, Horizonte.caida(d), 0.02,
			"a %.0f m el barco se hunde lo que dice la curvatura" % d)
	# A 20 km la caída es de 31 m sobre un barco de 10: no queda nada que dibujar.
	m.comprobar(not b.visible, "y desaparece cuando ni el tope asoma")
	b.queue_free()
	await arbol.process_frame


## Dónde está la cresta más alta a lo largo de `dir`, en metros desde `centro`.
static func _cresta(centro: Vector2, dir: Vector2) -> float:
	var mejor := 0.0
	var mejor_h := -INF
	for i in range(-280, 281):
		var s := float(i) * 0.05
		var h: float = Oleaje.desplazamiento(centro + dir * s).y
		if h > mejor_h:
			mejor_h = h
			mejor = s
	return mejor
