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

	await _textura_del_mar(m, arbol)
	await _espuma(m, arbol)
	await _estela(m, arbol)
	await _recorte_del_agua(m, arbol)
	await _horizonte(m, arbol)
	await _horizonte(m, arbol)


## Que el agua no sea un espejo: la pendiente que tiene la superficie, contra la que el viento le
## pide.
##
## **Cox y Munk (1954)** midieron el brillo del sol sobre el mar desde avión y de ahí sacaron la
## pendiente cuadrática media de la superficie: `0,003 + 0,00512·U`, con U el viento en m/s. Es
## la cifra que separa un mar de un cristal, y casi toda está en olas de menos de un metro, que
## la malla no tiene con qué dibujar — por eso va en la normal y, lo que ni en la normal cabe, en
## la rugosidad. Se mira en dos sitios a propósito:
##
## - **cerca**, la pendiente tiene que estar DIBUJADA, en la normal: si estuviera solo en la
##   rugosidad el agua se vería mate y lisa, que no es lo que se pide;
## - **lejos**, el detalle no cabe en el píxel, y lo que se apaga en la normal tiene que
##   reaparecer en la rugosidad. Si no, la pendiente se pierde con la distancia y el mar lejano
##   vuelve a ser un espejo, que es justo donde más se nota.
static func _textura_del_mar(m: MarcoPruebas, arbol: SceneTree) -> void:
	Viento.fuerza_base = 1.0
	await arbol.process_frame
	await arbol.process_frame
	Oleaje.asentar()
	await arbol.process_frame
	var u: float = Viento.fuerza * Viento.velocidad_m_s
	var cox_munk := 0.003 + 0.00512 * u
	var puntos := PackedVector2Array()
	var r := RandomNumberGenerator.new()
	r.seed = 20261017
	for i in UtilesPruebas.ESPEJO_MUESTRAS:
		puntos.append(Vector2(r.randf_range(-40.0, 40.0), r.randf_range(-40.0, 40.0)))
	# Cerca: a 5 m, píxel de 5 mm. Lejos: a 600 m, píxel de metro y medio.
	for caso in [{"n": "cerca", "dist": 5.0, "huella": 0.005},
			{"n": "lejos", "dist": 600.0, "huella": 1.5}]:
		var d: float = caso["dist"]
		var h: float = caso["huella"]
		var sx: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, puntos, 4, d, h)
		var sz: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, puntos, 5, d, h)
		var sr: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, puntos, 6, d, h)
		var dibujada := 0.0
		var oculta := 0.0
		for i in puntos.size():
			dibujada += sx[i] * sx[i] + sz[i] * sz[i]
			oculta += sr[i]
		dibujada /= puntos.size()
		oculta /= puntos.size()
		var detalle := "dibujada %.4f + en rugosidad %.4f, Cox-Munk %.4f a %.1f m/s" % [
			dibujada, oculta, cox_munk, u]
		var total := (dibujada + oculta) / cox_munk
		m.mayor_que(total, 0.6, "%s, el agua tiene la pendiente que pide el viento" % caso["n"],
			detalle)
		m.menor_que(total, 1.6, "%s, y no mucha más" % caso["n"], detalle)
		if caso["n"] == "cerca":
			# La parte de olas de más de unos centímetros se tiene que VER en la normal.
			m.mayor_que(dibujada / cox_munk, 0.3, "cerca, buena parte está dibujada en la normal",
				detalle)

	# --- La cresta es agua fina y se aclara; el valle no.
	#
	# Los puntos se BUSCAN, no se sortean. Sorteados en ±40 m, lo que caía dentro dependía del
	# instante: las olas van en grupos, y según el reloj había crestas de 0,8 m o de 0,3 m. El tono
	# satura al 30 % de la altura NOMINAL, así que con un trozo de mar bajo la "cresta" más débil se
	# quedaba en el umbral: 0,207-0,208 en la batería entera (0,450 corriendo `mundo` solo), y
	# 0,198 / 0,179 en cuanto la batería llegó aquí unos segundos antes o después (origen flotante,
	# 17-10-2026). Era la muestra, no el agua. Ahora se toman las 32 crestas y los 32 valles más
	# marcados de 200 × 200 m, y las alturas con el MISMO reloj que se le pasa al shader.
	var reloj: float = Oleaje.t
	var rejilla: Array = []
	for ix in range(-100, 101, 2):
		for iz in range(-100, 101, 2):
			var q := Vector2(ix, iz)
			rejilla.append([Oleaje.desplazamiento(q, reloj).y, q])
	rejilla.sort_custom(func(a, b): return a[0] > b[0])
	var muestra := PackedVector2Array()
	var alturas := PackedFloat32Array()
	var mitad: int = UtilesPruebas.ESPEJO_MUESTRAS / 2
	for i in mitad:
		for e in [rejilla[i], rejilla[rejilla.size() - 1 - i]]:
			muestra.append(e[1])
			alturas.append(e[0])
	var tono: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, muestra, 7)
	# La cresta, por la altura a la que llega ESTE mar y no por un umbral fijo: con uno fijo puede no
	# caer ningún punto encima, y la comprobación pasa sin mirar nada.
	var alto_max := -INF
	for y in alturas:
		alto_max = maxf(alto_max, y)
	var en_cresta := INF
	var crestas := 0
	var en_valle := 0.0
	for i in muestra.size():
		var y: float = alturas[i]
		if y > 0.7 * alto_max:
			en_cresta = minf(en_cresta, tono[i])
			crestas += 1
		elif y < 0.0:
			en_valle = maxf(en_valle, tono[i])
	m.mayor_que(en_cresta if crestas > 0 else 0.0, 0.2, "la cresta se aclara",
		"la menos clara de %d crestas, a %.2f m o más" % [crestas, 0.7 * alto_max])
	m.menor_que(en_valle, 0.01, "y el valle no", "el más claro de los valles")


## Que la espuma de las crestas cubra la parte del mar que el viento rompe, y no más.
##
## **Monahan y O'Muircheartaigh (1980)** midieron la fracción de mar cubierta de borreguillos
## contra el viento: `3,84·10⁻⁶ · U^3,41`, U en m/s. A 16 m/s es un 4,9 %; en calma, nada. Es lo
## que separa una espuma que sale donde rompe la ola de una que pinta las crestas de blanco por
## estar altas. Se mira en MUCHOS puntos (512, sobre 300 m) porque un 5 % con 64 son tres.
##
## Se mide el BLANCO MEDIO —la media de la espuma, de 0 a 1— y no cuántos puntos pasan de la
## mitad: la espuma es encaje con huecos, y lo que Monahan midió desde el aire es cuánto mar se
## ve blanco, que es la integral.
static func _espuma(m: MarcoPruebas, arbol: SceneTree) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 20261018
	var fracciones := {}
	for f in [0.15, 1.0, 1.8]:
		Viento.fuerza_base = f
		await arbol.process_frame
		await arbol.process_frame
		Oleaje.asentar()
		await arbol.process_frame
		# El viento que levanta la mar que se VE (Pierson-Moskowitz, `Hs = 0,21·U²/g`), no el
		# nominal: esta mar está a propósito por debajo de su viento, y con el nominal la espuma
		# salía exagerada (5 % con brisa, 48 % con mar dura).
		var u: float = sqrt(Oleaje.altura * 9.81 / 0.21)
		var monahan := 3.84e-6 * pow(u, 3.41)
		var blanco := 0.0
		var total := 0
		for pasada in 8:
			var puntos := PackedVector2Array()
			for i in UtilesPruebas.ESPEJO_MUESTRAS:
				puntos.append(Vector2(r.randf_range(-150.0, 150.0), r.randf_range(-150.0, 150.0)))
			var esp: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, puntos, 8)
			for v in esp:
				total += 1
				blanco += clampf(v, 0.0, 1.0)
		var fr := blanco / maxf(total, 1)
		fracciones[f] = fr
		var detalle := "%.1f %% del mar, Monahan %.1f %% a %.1f m/s" % [100.0 * fr, 100.0 * monahan, u]
		if f < 0.5:
			m.menor_que(fr, 0.005, "en calma no hay espuma", detalle)
		else:
			m.mayor_que(fr / monahan, 0.5, "con viento %.2f la espuma cubre lo que rompe" % f, detalle)
			m.menor_que(fr / monahan, 2.0, "y no más", detalle)
	m.mayor_que(float(fracciones[1.8]), float(fracciones[1.0]),
		"más viento, más espuma", "%.1f %% contra %.1f %%" % [100.0 * fracciones[1.8], 100.0 * fracciones[1.0]])
	Viento.fuerza_base = 1.0
	await arbol.process_frame
	Oleaje.asentar()


## La estela con la forma del barco: lo que deja un casco, no una piedra.
##
## Se monta un rastro SINTÉTICO —un casco de 10 m de flotación y 2,4 de manga que ha navegado
## 10 s en línea recta hacia +X a 4,5 m/s— y se lee lo que dibuja el shader del agua con el
## mismo `Estela.aplicar()` que usa el juego. Así se mide la forma sin navegar, y el número no
## depende de la mar ni del rumbo que haya quedado del paquete anterior.
##
## Lo que había eran anillos que se abrían a 1,6 m/s desde cada posición del barco: no sabían
## hacia dónde iba ni lo ancho que era.
static func _estela(m: MarcoPruebas, arbol: SceneTree) -> void:
	var manga := 2.4
	var eslora := 10.0
	var vel := 4.5
	var anchos := PackedFloat32Array()
	for k in 32:
		# Medio ancho que se cierra en las puntas, como un casco.
		var u := float(k) / 31.0 * 2.0 - 1.0
		anchos.append(manga * 0.5 * sqrt(maxf(1.0 - pow(absf(u), 3.0), 0.0)))
	var est := Estela.new()
	est.fijar_casco(anchos, -eslora * 0.5, eslora * 0.5)
	est.recta(Vector2.ZERO, Vector2(1, 0), vel, 10.0)
	# La proa está en x = +5 y la popa en x = −5.

	# --- 1. Tras la popa, una banda de agua revuelta del ancho del CASCO. Se mide el perfil de
	# espuma a través del rastro, promediado a lo largo de 4 m (la espuma es encaje y un corte
	# solo cae en un hueco), y su anchura a media altura.
	var ys := PackedFloat32Array()
	for i in 64:
		ys.append(-6.0 + 12.0 * float(i) / 63.0)
	var perfil := PackedFloat32Array()
	perfil.resize(ys.size())
	perfil.fill(0.0)
	var cortes := [-13.0, -13.5, -14.0, -14.5, -15.0, -15.5, -16.0, -16.5]
	for x in cortes:
		var ps := PackedVector2Array()
		for y in ys:
			ps.append(Vector2(x, y))
		var esp: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, ps, 9, 0.0, 0.01, est)
		for i in ys.size():
			perfil[i] += esp[i] / cortes.size()
	var pico := 0.0
	for v in perfil:
		pico = maxf(pico, v)
	var ancho_banda := 0.0
	if pico > 0.02:
		var dentro := 0
		for v in perfil:
			if v > pico * 0.5:
				dentro += 1
		ancho_banda = float(dentro) * 12.0 / 63.0
	m.mayor_que(ancho_banda / manga, 0.7, "tras la popa la estela es tan ancha como el casco",
		"%.2f m de banda con %.2f m de manga, espuma %.2f" % [ancho_banda, manga, pico])
	m.menor_que(ancho_banda / manga, 1.8, "y no mucho más",
		"%.2f m de banda con %.2f m de manga" % [ancho_banda, manga])

	# --- 2. Los brazos de Kelvin, a 19,47° del rumbo desde la PROA. Corte a corte por detrás de
	# la proa, a qué distancia del rastro está la ola más alta, y el ángulo con SU distancia a la
	# proa. Juntar los cortes y tomar un máximo común daba 16,9° con la estela bien hecha: la ola
	# se apaga con la distancia y el máximo caía siempre en el corte más cercano a la proa.
	var ys_k := PackedFloat32Array()
	for i in 64:
		ys_k.append(2.0 + 18.0 * float(i) / 63.0)
	var angulos: Array[float] = []
	var mejor_h := 0.0
	for dx in 12:
		var s_b := 26.0 + float(dx) * 0.8
		var ps := PackedVector2Array()
		for y in ys_k:
			ps.append(Vector2(5.0 - s_b, y))
		var h: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, ps, 10, 0.0, 0.01, est)
		var pico_h := 0.0
		var pico_y := 0.0
		for i in ys_k.size():
			if absf(h[i]) > pico_h:
				pico_h = absf(h[i])
				pico_y = ys_k[i]
		mejor_h = maxf(mejor_h, pico_h)
		# Un corte que cae en el nodo de la onda no tiene ola que medir.
		if pico_h > 0.005:
			angulos.append(rad_to_deg(atan2(pico_y, s_b)))
	angulos.sort()
	var angulo: float = angulos[angulos.size() / 2] if not angulos.is_empty() else 0.0
	m.mayor_que(mejor_h, 0.01, "la estela levanta olas de Kelvin", "%.3f m" % mejor_h)
	m.casi(angulo, 19.47, 2.0, "y abren a 19,47° desde la proa",
		"mediana de %d cortes entre 26 y 35 m tras la proa" % angulos.size())

	# --- 3. Nada por delante de la proa.
	var delante := PackedVector2Array()
	for i in 32:
		delante.append(Vector2(8.0 + float(i % 4), -3.0 + 6.0 * float(i / 4) / 7.0))
	var esp_d: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, delante, 9, 0.0, 0.01, est)
	var h_d: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, delante, 10, 0.0, 0.01, est)
	var peor_d := 0.0
	var peor_hd := 0.0
	for i in delante.size():
		peor_d = maxf(peor_d, esp_d[i])
		peor_hd = maxf(peor_hd, absf(h_d[i]))
	m.menor_que(peor_d, 0.05, "por delante de la proa no hay espuma", "%.3f" % peor_d)
	m.menor_que(peor_hd, 0.002, "ni ola", "%.4f m" % peor_hd)

	# --- 4. Espuma pegada al costado, más en la proa, y no a tres metros de él.
	var costado := PackedVector2Array()
	var lejos := PackedVector2Array()
	for i in 16:
		var x := 2.0 + 2.0 * float(i) / 15.0
		var hw: float = manga * 0.5 * sqrt(maxf(1.0 - pow(absf(x / 5.0), 3.0), 0.0))
		costado.append(Vector2(x, hw + 0.15))
		costado.append(Vector2(x, -hw - 0.15))
		lejos.append(Vector2(-1.0 + float(i) * 0.2, hw + 3.0))
		lejos.append(Vector2(-1.0 + float(i) * 0.2, -hw - 3.0))
	var esp_c: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, costado, 9, 0.0, 0.01, est)
	var esp_l: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, lejos, 9, 0.0, 0.01, est)
	var media_c := 0.0
	var peor_l := 0.0
	for i in costado.size():
		media_c += esp_c[i] / costado.size()
		peor_l = maxf(peor_l, esp_l[i])
	m.mayor_que(media_c, 0.2, "la proa aparta el agua con espuma junto al costado",
		"%.2f de media a 15 cm del forro" % media_c)
	m.menor_que(peor_l, 0.05, "y no a tres metros del costado", "%.3f" % peor_l)

	# --- 4b. La estela empieza con la POPA del casco, no detrás del timón: a 20 cm del forro, en
	# el cuarto de popa, el agua ya sale revuelta.
	var aleta := PackedVector2Array()
	for i in 16:
		var x := -2.5 - 2.4 * float(i) / 15.0
		var hw: float = manga * 0.5 * sqrt(maxf(1.0 - pow(absf(x / 5.0), 3.0), 0.0))
		aleta.append(Vector2(x, hw + 0.2))
		aleta.append(Vector2(x, -hw - 0.2))
	var esp_a: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, aleta, 9, 0.0, 0.01, est)
	var media_a := 0.0
	for v in esp_a:
		media_a += v / esp_a.size()
	m.mayor_que(media_a, 0.35, "la estela nace en el cuarto de popa, pegada al casco",
		"%.2f de media a 20 cm del forro" % media_a)

	# --- 4c. Y se ACABA donde se acaba el rastro. Medía la distancia al tramo más cercano como
	# distancia de lado, y pasado el final eso sigue siendo cero a lo largo de la prolongación
	# del último tramo: la banda seguía en línea recta más allá de donde el barco había pasado, y
	# al envejecer la curva de un giro lo que quedaba era esa recta — "se endereza", dijo el
	# usuario. 10 s a 4,5 m/s: la popa ha pasado hasta x = −50.
	var mas_alla := PackedVector2Array()
	for i in 32:
		mas_alla.append(Vector2(-58.0 - float(i % 8) * 4.0, -1.0 + float(i / 8) * 0.6))
	var esp_m: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, mas_alla, 9, 0.0, 0.01, est)
	var h_m: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, mas_alla, 10, 0.0, 0.01, est)
	var peor_m := 0.0
	var peor_hm := 0.0
	for i in mas_alla.size():
		peor_m = maxf(peor_m, esp_m[i])
		peor_hm = maxf(peor_hm, absf(h_m[i]))
	m.menor_que(peor_m, 0.02, "más allá del final del rastro no hay banda", "%.3f" % peor_m)
	m.menor_que(peor_hm, 0.002, "ni ola", "%.4f m" % peor_hm)

	# --- 5. Parado no deja estela.
	est.recta(Vector2.ZERO, Vector2(1, 0), 0.0, 10.0)
	var rejilla := PackedVector2Array()
	for i in 64:
		rejilla.append(Vector2(-20.0 + float(i % 8) * 4.0, -6.0 + float(i / 8) * 1.7))
	var esp_p: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, rejilla, 9, 0.0, 0.01, est)
	var peor_p := 0.0
	for v in esp_p:
		peor_p = maxf(peor_p, v)
	m.menor_que(peor_p, 0.02, "un barco parado no deja estela", "%.3f" % peor_p)


## Que el recorte del agua tape el mar por donde se ve —las escotillas— y no pueda asomar por
## fuera del casco.
##
## **Se comprueba la GEOMETRÍA, no la foto, y es una decisión.** El recorte lo hace el shader
## descartando fragmentos, y desde GDScript no se puede preguntar si un fragmento se descartó: hay
## que fotografiar. Se intentó, y fotografiar dentro de la batería salió mal dos veces —contando
## píxeles azules la cifra bailaba entre 2 y 30 % según la ola y la luz, y comparar la misma vista
## con el recorte y sin él obliga a congelar el tiempo, lo que colgó la batería entera. Lo que se
## mira aquí es lo que de verdad se rompe. Mirarlo de verdad es cosa de `tools/por_la_rejilla.tscn`
## (medido en temporal: 16-18 % de mar a la vista sin recorte contra 0,9-2,7 % con él, y ese resto
## es el herraje de la propia rejilla).
static func _recorte_del_agua(m: MarcoPruebas, arbol: SceneTree) -> void:
	var b := UtilesPruebas.barco(arbol)
	if b == null:
		return
	var caja: Array = b.call("caja_recorte")
	if not m.comprobar(caja.size() == 2, "el barco saca del modelo la caja con que recorta el agua"):
		return
	var lo: Vector3 = caja[0]
	var hi: Vector3 = caja[1]

	# Que se quede DENTRO del casco es lo que impide que asome por el costado, y no hay margen que
	# vigilar: la caja y el casco están los dos en ejes del barco, así que giran juntos y lo que
	# está dentro lo está en cualquier pose. Antes el recorte tomaba su planta del casco y
	# cualquier escora lo sacaba por el forro.
	var manga_casco := 0.0
	for w in (b.call("perfil_de_flotacion") as PackedFloat32Array):
		manga_casco = maxf(manga_casco, w)
	# Se compara contra el casco EN LA FLOTACIÓN, que es donde más estrecho es de todo lo que la
	# caja abarca: la caja va de 0,65 a 1,64 y ahí arriba el casco se abre hasta 1,9 de semimanga.
	# Y no se pide margen de sobra —salen 0,25 m por banda— porque no hay nada que se desplace: lo
	# que está dentro del casco en ejes del barco lo está en cualquier pose.
	m.menor_que(maxf(absf(lo.x), absf(hi.x)), manga_casco,
		"la caja del recorte se queda dentro del casco",
		"%.2f m de semimanga contra %.2f del casco en la flotación"
			% [maxf(absf(lo.x), absf(hi.x)), manga_casco])

	# Que la caja ABARQUE la lámina es lo que hace que el agua que entra se borre. Antes aquí se
	# pedía que el suelo de la bodega quedara por ENCIMA del agua, y eso dejó de ser cierto al
	# subir el calado a 0,70 — ni tenía que serlo: una bodega por debajo de la flotación es lo
	# normal en un barco, y el recorte es justo lo que hace las veces de forro estanco.
	#
	# Y el techo importa igual: por encima de él no se recorta, que es lo que evita dejar un
	# agujero de agua bajo un casco levantado sobre una ola.
	var lamina: float = Oleaje.nivel - float(b.get("altura_flotacion"))
	m.comprobar(lamina > lo.y and lamina < hi.y,
		"y la caja abarca la lámina, que es el agua que hay que borrar",
		"lámina en %.2f, caja de %.2f a %.2f" % [lamina, lo.y, hi.y])

	# Y que cubra todas las escotillas, que es por donde se ve el agua.
	var al_barco := b.global_transform.affine_inverse()
	var dentro := 0
	var escotillas := b.find_children("escotilla_*", "MeshInstance3D", true, false)
	for n in escotillas:
		var mi := n as MeshInstance3D
		var p: Vector3 = al_barco * (mi.global_transform * mi.mesh.get_aabb().get_center())
		if p.x > lo.x and p.x < hi.x and p.z > lo.z and p.z < hi.z:
			dentro += 1
	m.comprobar(not escotillas.is_empty() and dentro == escotillas.size(),
		"y aun así llega a todas las escotillas",
		"%d de %d" % [dentro, escotillas.size()])


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
	var alto: float = b.get("_alto")
	m.mayor_que(alto, 5.0, "el barco sabe lo que mide de alto", "%.2f m" % alto)

	for d in [2000.0, 20000.0]:
		b.global_position = Vector3(ojo.global_position.x + d, 0, ojo.global_position.z)
		# El reloj del bamboleo a cero: sus 15 cm tapan la curvatura a las distancias cortas.
		b.set("time", 0.0)
		await arbol.physics_frame
		await arbol.physics_frame
		# Contra la altura que la OLA le pide, no contra `altura_flotacion`: desde la fase 2 el
		# casco sube y baja con el mar, así que restar el valor de reposo mide la ola además de
		# la curvatura. `_y_mar` es justo lo que flotaría sin curvatura.
		var caida: float = float(b.get("_y_mar")) - b.global_position.y
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
