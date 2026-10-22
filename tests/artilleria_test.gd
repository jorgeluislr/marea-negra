class_name ArtilleriaTest
extends RefCounted

## Paquete `artilleria`: que los cañones estén DONDE tienen que estar, medido contra el casco
## real y no contra las cifras con que se colocaron.
##
## Las tres cosas que se rompen en silencio al mover una pieza o cambiar de barco: que la
## cureña quede flotando o hundida en la cubierta, que la boca se quede DENTRO del costado
## (dispararía contra su propia madera) y que el ánima quede por debajo de la regala, que en
## esta balandra es lo que decide que el montaje sea a barbeta: la obra muerta solo levanta
## 0,41 m sobre cubierta y no hay sitio para portas.
##
## Partido en ESCENARIOS que se pueden pedir sueltos (`-- artilleria/fuego`). Comparten una
## sola preparación, la del paquete —adrizar el casco—, que se hace pidas lo que pidas.


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("artilleria")
	var b := UtilesPruebas.barco(arbol)
	if not m.comprobar(b != null, "hay un barco en el grupo 'barco_activo'"):
		return

	var previo: Dictionary = await _adrizar(arbol, b)
	var canones: Array[Node] = []
	for h in b.find_children("*", "", true, false):
		if h.has_method("disparar") and h.has_method("banda"):
			canones.append(h)
	if m.comprobar(canones.size() == 4, "la balandra monta sus cuatro cañones",
			"%d" % canones.size()):
		if m.escenario("montaje"):
			_montaje(m, b, canones)
		if m.escenario("cuna"):
			await _cuna(m, arbol, b, canones)
		if m.escenario("espeque"):
			await _espeque(m, arbol, canones)
		if m.escenario("baterias"):
			await _baterias(m, arbol, b)
		if m.escenario("fuego"):
			await _fuego(m, arbol, b, canones)
	_devolver(b, previo)


# **Todo este paquete se mide con el casco ADRIZADO.** Desde que el barco cabecea y escora
# —con la ola, con el viento en las velas y con la fuerza centrífuga del giro—, cualquier
# altura tomada en ejes de mundo lleva dentro la inclinación: con 2,75° de escora una pieza
# perfectamente asentada daba 23 mm de desnivel entre sus ruedas, y con los 9° que mete el
# viento de través, 124 mm y el tubo de sotavento por debajo de su propia regala. Adrizar es
# más simple y menos frágil que pasar cada medida a ejes del barco, y responde a la pregunta
# que de verdad se hace aquí: si la pieza está bien montada en su cubierta y si el tiro sale
# por donde debe.
#
# Son las tres causas por separado, no vale con una: las obediencias solo apagan la ola.
#
# Es la preparación del PAQUETE y no de cada escenario porque adrizar cuesta hasta 6 s y todos la
# necesitan igual. Al acabar se devuelven los valores: antes se quedaban a cero y todo lo que
# corría después lo hacía con un casco que no escoraba.
static func _adrizar(arbol: SceneTree, b: Node) -> Dictionary:
	var previo := {}
	for k in ["obediencia_escora", "obediencia_cabeceo", "brazo_velico", "brazo_giro"]:
		previo[k] = b.get(k)
		b.set(k, 0.0)
	# Y se ESPERA A QUE SE ADRICE, no un número de frames a ojo: el casco llega a la horizontal
	# oscilando, así que un segundo después todavía le queda parte de lo que tenía, y eso son
	# milímetros de desnivel entre las ruedas.
	#
	# **En los DOS ejes.** Esperaba solo a la escora, y con el cabeceo de verdad que el casco tiene
	# desde que flota por puntos eso dejaba 9 mm de desnivel contra un tope de 5: las ruedas de una
	# cureña están separadas a lo largo Y a lo ancho, así que las inclina cualquiera de los dos.
	var adrizando := 0.0
	while adrizando < 6.0 and (absf(b.global_transform.basis.get_euler().z) > 0.0008
			or absf(b.global_transform.basis.get_euler().x) > 0.0008):
		await arbol.process_frame
		adrizando += arbol.root.get_process_delta_time()
	return previo


static func _devolver(b: Node, previo: Dictionary) -> void:
	for k in previo:
		b.set(k, previo[k])
	b.set("modo_battle", false)


static func _montaje(m: MarcoPruebas, b: Node, canones: Array[Node]) -> void:
	var babor := 0
	var estribor := 0
	for c in canones:
		if String(c.call("banda")) == "babor":
			babor += 1
		else:
			estribor += 1
	m.comprobar(babor == 2 and estribor == 2, "dos por banda",
		"%d babor / %d estribor" % [babor, estribor])

	var espacio := (b as Node3D).get_world_3d().direct_space_state
	for c in canones:
		var n3 := c as Node3D
		var nom := String(n3.name)

		# --- Apoya en cubierta: rayo hacia abajo desde el eje de la cureña. La capa 3 (bit 4)
		# es la de los colisionadores de cubierta que levanta `Barco`.
		var desde := n3.global_position + Vector3.UP * 0.6
		var par := PhysicsRayQueryParameters3D.create(desde, desde + Vector3.DOWN * 2.5)
		par.collision_mask = 4
		par.hit_from_inside = false
		var golpe := espacio.intersect_ray(par)
		if m.comprobar(not golpe.is_empty(), "%s: hay cubierta bajo el cañón" % nom):
			var hueco: float = n3.global_position.y - float(golpe["position"].y)
			# El esperado sale de las CONSTANTES de la pieza, no de un número escrito aquí: al
			# bajar de a 4 a a 3 libras esto habría seguido pasando con 0,395 por pura
			# tolerancia, que es una prueba que ya no comprueba nada. Se suma el dormido porque
			# es sólo visual —no lleva colisionador— y el rayo lo atraviesa hasta la cubierta.
			var esperado: float = Canon.ALTO * 0.5 + float(c.get("altura_dormido"))
			m.casi(hueco, esperado, 0.02, "%s: la cureña apoya a su altura" % nom)

		# --- La boca sale fuera del costado. Se mide contra el CASCO (capa 2, bit 2): un rayo
		# desde la boca hacia crujía tiene que encontrar madera, y otro hacia fuera, nada.
		var boca: Vector3 = n3.call("boca_global")
		var hacia_dentro := -n3.global_transform.basis.x.normalized() \
			if String(c.call("banda")) == "estribor" else n3.global_transform.basis.x.normalized()
		var p2 := PhysicsRayQueryParameters3D.create(boca, boca + hacia_dentro * 0.05)
		p2.collision_mask = 2
		m.comprobar(espacio.intersect_ray(p2).is_empty(),
			"%s: la boca no está metida en la madera" % nom)

		# --- A barbeta: lo que tiene que pasar por encima de la regala es el TUBO, no su eje.
		# Comprobar el eje dejaba pasar una pieza con la generatriz de abajo metida 2,9 cm en la
		# tabla, que es exactamente lo que se coló y se veía desde fuera como un cañón clavado
		# en el costado.
		var altura_regala: float = float(b.call("altura_regala_en", n3.global_position))
		m.comprobar(boca.y - Canon.RADIO_TUBO - altura_regala > 0.0,
			"%s: el TUBO pasa sobre la regala" % nom,
			"bajo del tubo %.3f vs regala %.3f" % [boca.y - Canon.RADIO_TUBO, altura_regala])

		# --- Las CUATRO ruedas apoyan. Un rayo desde el centro no vale: la pieza puede tener
		# tres en la cubierta y la cuarta al aire sobre la borda, y el centro seguir dando bien.
		# Las ruedas van en el espacio del MODELO, que en estribor está girado media vuelta.
		var sueltas := 0
		var alto := -INF
		var bajo := INF
		for w in (c.call("ruedas_globales") as Array):
			var pr := PhysicsRayQueryParameters3D.create(w + Vector3.UP * 0.9, w + Vector3.DOWN * 0.9)
			pr.collision_mask = 4
			if espacio.intersect_ray(pr).is_empty():
				sueltas += 1
			# La altura que importa es la de la RUEDA, no la del suelo que hay debajo: la
			# cubierta es plana, así que medir el suelo daba 0,000 de desnivel mientras la
			# pieza estaba inclinada 4° y con dos ruedas enterradas en el dormido.
			alto = maxf(alto, w.y)
			bajo = minf(bajo, w.y)
		m.comprobar(sueltas == 0, "%s: las cuatro ruedas encuentran suelo" % nom,
			"%d al aire" % sueltas)
		m.menor_que(alto - bajo, 0.005, "%s: las cuatro ruedas al mismo nivel" % nom)

	sin_estorbos(m, b, canones)


# ── La cuña de puntería: eleva el TUBO y nada más ─────────────────────────
# Es lo que justifica haber separado el tubo de la cureña en el modelo. Con la pieza de
# una sola malla, elevar 4° dejaba 4,9 cm de desnivel entre ruedas.
static func _cuna(m: MarcoPruebas, arbol: SceneTree, b: Node, canones: Array[Node]) -> void:
	var pz := canones[0] as Node3D
	# En el espacio del BARCO, no del mundo: entre las dos medidas pasan frames y el casco
	# navega y cabecea. Midiendo en global daba 1,36 m de "movimiento de la cureña" que era
	# el barco entero. Es el mismo aviso que trae el proyecto para medir telas.
	var ruedas_antes: Array[Vector3] = []
	for w in (pz.call("ruedas_globales") as Array):
		ruedas_antes.append((b as Node3D).to_local(w))
	var boca_antes: Vector3 = pz.call("boca_global")
	var caida_antes: Vector3 = pz.call("punto_de_caida")
	pz.set("elevacion", 8.0)
	for i in 5:
		await arbol.process_frame
	var boca_luego: Vector3 = pz.call("boca_global")
	m.mayor_que(boca_luego.y - boca_antes.y, 0.02, "la cuña sube la boca del tubo")
	var movida := 0.0
	var j := 0
	for w in (pz.call("ruedas_globales") as Array):
		movida = maxf(movida, (b as Node3D).to_local(w).distance_to(ruedas_antes[j]))
		j += 1
	m.menor_que(movida, 0.001, "y la cureña no se mueve")
	var caida_luego: Vector3 = pz.call("punto_de_caida")
	m.mayor_que(caida_luego.distance_to(pz.global_position)
		- caida_antes.distance_to(pz.global_position), 5.0, "y alarga el alcance")
	pz.set("elevacion", 0.0)

	# --- Y hace lo MISMO en las dos bandas. Lo de arriba mira una sola pieza, y con una sola
	# pieza esta comprobación no descubre nada: la elevación llevaba un signo por banda —el
	# mismo que ya se le quitó al espeque— y con la cuña a +8° estribor subía el ánima 8,00° y
	# babor la BAJABA 8,00°, o sea 355 m de alcance contra 13. El jugador lo notó como que el
	# ratón apuntaba al revés por babor y como que el barco tiraba más lejos por estribor: son
	# el mismo fallo. Se mide el ángulo sobre el HORIZONTE, que no depende de a qué banda mire
	# la pieza, y con el casco adrizado, que es lo que hace este paquete desde el principio.
	for c in canones:
		var q := c as Node3D
		q.set("elevacion", 0.0)
	for i in 5:
		await arbol.process_frame
	var llano: Array[float] = []
	for c in canones:
		llano.append(_sobre_horizonte(c as Node3D))
	for c in canones:
		(c as Node3D).set("elevacion", 8.0)
	for i in 5:
		await arbol.process_frame
	var j2 := 0
	for c in canones:
		var q := c as Node3D
		var sube := _sobre_horizonte(q) - llano[j2]
		j2 += 1
		m.casi(sube, 8.0, 0.3, "%s: la cuña sube el ánima, tire a la banda que tire (%.2f°)"
			% [q.name, sube])
	for c in canones:
		(c as Node3D).set("elevacion", 0.0)
	for i in 5:
		await arbol.process_frame


# El giro lateral, en cambio, SÍ mueve la pieza entera: es lo que se hacía con espeques.
static func _espeque(m: MarcoPruebas, arbol: SceneTree, canones: Array[Node]) -> void:
	var pz := canones[0] as Node3D
	var dir_antes: Vector3 = pz.call("direccion_global")
	pz.set("giro_lateral", 12.0)
	for i in 5:
		await arbol.process_frame
	var giro := rad_to_deg(dir_antes.angle_to(pz.call("direccion_global")))
	m.casi(giro, 12.0, 1.0, "el espeque gira la pieza a los lados")
	pz.set("giro_lateral", 0.0)
	for i in 5:
		await arbol.process_frame


# ── Selección de banda ────────────────────────────────────────────────────
# Fuera del modo battle las flechas NO deben tocar la artillería: si respondieran, se
# cambiaría de batería sin querer mientras se maniobra.
static func _baterias(m: MarcoPruebas, arbol: SceneTree, b: Node) -> void:
	b.set("banda_apuntada", "estribor")
	b.set("modo_battle", false)
	await UtilesPruebas.tecla(arbol, KEY_LEFT)
	for i in 10:
		await arbol.process_frame
	m.comprobar(String(b.get("banda_apuntada")) == "estribor",
		"sin modo battle las flechas no cambian de batería", String(b.get("banda_apuntada")))

	await UtilesPruebas.tecla(arbol, KEY_B)
	for i in 10:
		await arbol.process_frame
	if m.comprobar(bool(b.get("modo_battle")), "B entra en modo battle"):
		await UtilesPruebas.tecla(arbol, KEY_LEFT)
		for i in 10:
			await arbol.process_frame
		m.comprobar(String(b.get("banda_apuntada")) == "babor", "flecha izquierda apunta a babor",
			String(b.get("banda_apuntada")))
		await UtilesPruebas.tecla(arbol, KEY_RIGHT)
		for i in 10:
			await arbol.process_frame
		m.comprobar(String(b.get("banda_apuntada")) == "estribor", "flecha derecha apunta a estribor",
			String(b.get("banda_apuntada")))
	b.set("modo_battle", false)


# ── Fuego ─────────────────────────────────────────────────────────────────
# La comprobación que de verdad discrimina: que la GUÍA no mienta. Se le pregunta a la
# pieza dónde va a caer el tiro, se dispara de verdad y se mira dónde cayó. Si la línea que
# ve el jugador se calcula con otra fórmula que la bala, esto lo caza.
static func _fuego(m: MarcoPruebas, arbol: SceneTree, b: Node, canones: Array[Node]) -> void:
	b.set("banda_apuntada", "estribor")
	var pieza := canones_de(canones, "estribor")[0] as Node3D
	# Lo previsto es donde ACABA LA GUÍA (`trayectoria`), que es lo que ve el jugador. Desde que la
	# bala cae en la ola y no en el plano (19-10-2026), `punto_de_caida` —el plano, que es lo que usa
	# el capitán para afinar— se separaba 2,06 m de la caída real con un tiro rasante.
	var guia: PackedVector3Array = pieza.call("trayectoria")
	var previsto: Vector3 = guia[guia.size() - 1] if not guia.is_empty() \
		else pieza.call("punto_de_caida")
	m.mayor_que(previsto.distance_to(pieza.global_position), 10.0,
		"el tiro previsto cae lejos del barco")

	var caidas: Array[Vector3] = []
	var anota := func(donde: Vector3, _que: Node): caidas.append(donde)
	for c in canones:
		c.connect("impacto", anota)
	var balas_antes: int = int(b.get("municion"))
	var salieron: int = int(b.call("disparar_banda"))
	m.comprobar(salieron == 2, "dispara las dos piezas de la banda", "%d" % salieron)
	m.comprobar(int(b.get("municion")) == balas_antes - 2, "y gasta dos balas",
		"%d → %d" % [balas_antes, int(b.get("municion"))])
	var esperando := 0
	while caidas.is_empty() and esperando < 600:
		await arbol.process_frame
		esperando += 1
	if m.comprobar(not caidas.is_empty(), "la bala llega a impactar"):
		var real: Vector3 = caidas[0]
		m.menor_que(Vector2(real.x - previsto.x, real.z - previsto.z).length(), 1.0,
			"la guía acierta dónde cae la bala")

	# Recarga: una pieza recién disparada no vuelve a tirar.
	m.comprobar(int(b.call("disparar_banda")) == 0, "no se dispara mientras recarga")
	for c in canones:
		c.disconnect("impacto", anota)


static func canones_de(todos: Array[Node], que_banda: String) -> Array[Node]:
	var sale: Array[Node] = []
	for c in todos:
		if String(c.call("banda")) == que_banda:
			sale.append(c)
	return sale


## Que ningún bulto de la estiba se plante donde va una pieza. Se comprueba porque el síntoma
## es desconcertante: el cañón no "se hunde", queda montado sobre la caja y el rayo que busca
## la cubierta encuentra suelo por ENCIMA del propio cañón.
static func sin_estorbos(m: MarcoPruebas, b: Node, canones: Array[Node]) -> void:
	var bultos := b.get_node_or_null(^"Cargamento")
	if bultos == null:
		return
	for c in canones:
		var n3 := c as Node3D
		var caja_c := AABB(n3.position - Vector3(0.95, 0.36, 0.32), Vector3(1.90, 0.72, 0.64))
		for bulto in bultos.get_children():
			var b3 := bulto as Node3D
			if b3 == null:
				continue
			var caja_b := AABB(b3.position - Vector3(0.35, 0.35, 0.35), Vector3(0.70, 0.70, 0.70))
			m.comprobar(not caja_c.intersects(caja_b),
				"%s libre de '%s'" % [n3.name, b3.name])


## Grados que levanta el ánima de una pieza sobre el horizonte. Positivo = apunta al cielo.
## Va contra el HORIZONTE y no contra el barco a propósito: es lo único que se puede comparar
## entre dos piezas que miran a bandas contrarias.
static func _sobre_horizonte(c: Node3D) -> float:
	var d: Vector3 = c.call("direccion_global")
	return rad_to_deg(asin(clampf(d.normalized().y, -1.0, 1.0)))
