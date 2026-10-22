class_name HudTest
extends RefCounted

## Paquete `hud`: que lo que ENSEÑA el HUD sea lo que pasa en el juego.
##
## Se lee lo que se ve —el giro de la aguja, el texto de la cartela, la visibilidad del panel, el
## color de un aro— y se compara con el barco medido por su cuenta, no con una variable del HUD
## que podría estar bien mientras el dibujo va por otro lado. Y se maneja con las teclas y el
## ratón del jugador, para que el cableado del input entre en la prueba.
##
## No nombra ninguna clase del HUD: busca el nodo por su nombre. Así el paquete compila aunque el
## HUD no exista, y el fallo sale como fallo y no como una batería cortada en verde.
##
## Partido en escenarios (`-- hud/rosa`), cada uno se prepara solo y deja el barco como estaba.

const NUDOS_POR_M_S := 1.943844


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("hud")
	var b := UtilesPruebas.barco(arbol)
	if not m.comprobar(b != null, "hay un barco en el grupo 'barco_activo'"):
		return
	var hud := _hud(arbol)
	if not m.comprobar(hud != null, "el mundo tiene el HUD nuevo (nodo HUD con su Rosa)"):
		return
	if m.escenario("rosa"):
		await _rosa(m, arbol, b, hud)
	if m.escenario("cartela"):
		await _cartela(m, arbol, b, hud)
	if m.escenario("estado"):
		await _estado(m, arbol, b, hud)
	if m.escenario("bateria"):
		await _bateria(m, arbol, b, hud)
	if m.escenario("danos"):
		await _danos(m, arbol, b, hud)


static func _hud(arbol: SceneTree) -> Node:
	for n in arbol.root.find_children("HUD", "CanvasLayer", true, false):
		if n.get_node_or_null("Rosa") != null:
			return n
	return null


## Rumbo del barco en grados de carta: 0 al norte (−Z), 90 al este (+X), en sentido horario.
static func _rumbo(b: Node3D) -> float:
	var p := -b.global_transform.basis.z
	return fposmod(rad_to_deg(atan2(p.x, -p.z)), 360.0)


## De dónde VIENE el viento, en grados de carta. `Viento.direccion` es hacia dónde sopla.
static func _viento_desde() -> float:
	var d: Vector3 = Viento.direccion
	return fposmod(rad_to_deg(atan2(-d.x, d.z)), 360.0)


static func _dif_angular(a: float, b: float) -> float:
	return absf(wrapf(a - b, -180.0, 180.0))


# La aguja del rumbo marca la proa y la del viento de dónde viene, leídas del GIRO de las agujas
# que se dibujan. Se hace virar el barco con la tecla para que el rumbo de partida no coincida por
# casualidad con lo que la aguja marque de serie, y se compara en dos rumbos distintos.
static func _rosa(m: MarcoPruebas, arbol: SceneTree, b: Node3D, hud: Node) -> void:
	await UtilesPruebas.al_timon(arbol)
	b.set("anclado", false)
	var rosa := hud.get_node("Rosa")
	var aguja := rosa.get_node_or_null("AgujaRumbo") as Control
	var veleta := rosa.get_node_or_null("AgujaViento") as Control
	if not m.comprobar(aguja != null and veleta != null, "la rosa tiene sus dos agujas"):
		return
	# Dos vientos distintos, para que una veleta fija en el primero no pase en el segundo.
	var vientos := [Vector3(1, 0, 0.3).normalized(), Vector3(-0.4, 0, 1).normalized()]
	for vuelta in 2:
		await UtilesPruebas.navegar(arbol, 3.0, vientos[vuelta])
		# Timón a babor un rato ANTES de leer: el rumbo de partida es 0 y una aguja quieta en 0
		# pasaba la primera lectura por casualidad.
		var e := InputEventKey.new()
		e.keycode = KEY_A
		e.physical_keycode = KEY_A
		e.pressed = true
		Input.parse_input_event(e)
		for i in 120:
			await arbol.physics_frame
		e = e.duplicate()
		e.pressed = false
		Input.parse_input_event(e)
		await arbol.process_frame
		m.menor_que(_dif_angular(aguja.rotation_degrees, _rumbo(b)), 1.0,
			"la aguja marca el rumbo real (vuelta %d)" % vuelta,
			"aguja %.1f°, proa %.1f°" % [fposmod(aguja.rotation_degrees, 360.0), _rumbo(b)])
		m.menor_que(_dif_angular(veleta.rotation_degrees, _viento_desde()), 1.0,
			"la veleta marca de dónde viene el viento (vuelta %d)" % vuelta,
			"veleta %.1f°, viento del %.1f°" % [fposmod(veleta.rotation_degrees, 360.0),
				_viento_desde()])
	b.set("anclado", true)


# Nombre, tipo y nudos. Los nudos se comparan con la velocidad del casco convertida aquí, y con el
# barco andando para que un "0,0" fijo no pase.
static func _cartela(m: MarcoPruebas, arbol: SceneTree, b: Node3D, hud: Node) -> void:
	await UtilesPruebas.al_timon(arbol)
	b.set("anclado", false)
	var cartela := hud.get_node_or_null("Cartela") as Control
	var nombre := cartela.find_child("Nombre", true, false) as Label if cartela != null else null
	var tipo := cartela.find_child("Tipo", true, false) as Label if cartela != null else null
	# Los nudos van en su propio círculo al lado de la cartela, como en la maqueta, no dentro.
	var nudos := hud.get_node_or_null("Corredera/Nudos") as Label
	if not m.comprobar(nombre != null and tipo != null and nudos != null,
			"la cartela tiene nombre y tipo, y la corredera los nudos"):
		return
	await UtilesPruebas.navegar(arbol, 6.0, Vector3(1, 0, 0.3).normalized())
	await arbol.process_frame
	m.comprobar(nombre.text == str(b.get("nombre")), "la cartela lleva el nombre del barco",
		"'%s' / '%s'" % [nombre.text, b.get("nombre")])
	m.comprobar(str(b.get("tipo")) != "" and tipo.text.to_lower() == str(b.get("tipo")).to_lower(),
		"la cartela lleva el tipo del barco", "'%s' / '%s'" % [tipo.text, b.get("tipo")])
	# Nombre y tipo en UNA línea y centrados en el alto de la cartela: no caben dos líneas. Se mide
	# el renglón real del texto (su caja con la letra puesta), no el del nodo.
	m.comprobar(str(b.get("nombre")).to_lower() != str(b.get("tipo")).to_lower(),
		"el barco lleva un nombre propio de ejemplo", "'%s'" % b.get("nombre"))
	await arbol.process_frame
	var centro_y := cartela.get_global_rect().get_center().y
	for l: Label in [nombre, tipo]:
		if not l.is_visible_in_tree():
			m.comprobar(false, "%s se ve en la cartela" % l.name)
			continue
		var alto_letra := l.get_theme_font("font").get_height(l.get_theme_font_size("font_size"))
		var arriba := l.get_global_rect().position.y
		match l.vertical_alignment:
			VERTICAL_ALIGNMENT_CENTER:
				arriba += (l.size.y - alto_letra) * 0.5
			VERTICAL_ALIGNMENT_BOTTOM:
				arriba += l.size.y - alto_letra
		m.menor_que(absf(arriba + alto_letra * 0.5 - centro_y), 3.0,
			"%s centrado en el alto de la cartela (px)" % l.name)
	var v := float(b.get("velocidad")) * NUDOS_POR_M_S
	var leido := nudos.text.replace(",", ".").to_float()
	m.mayor_que(v, 1.0, "el barco anda para la prueba de nudos", "%.2f nudos" % v)
	m.casi(leido, v, 0.15, "la cartela marca los nudos del casco", "texto '%s'" % nudos.text)
	b.set("anclado", true)


# Cada icono de estado sigue a la maniobra hecha CON LA TECLA, ida y vuelta.
static func _estado(m: MarcoPruebas, arbol: SceneTree, b: Node3D, hud: Node) -> void:
	await UtilesPruebas.al_timon(arbol)
	var casos := [["VelaProa", KEY_W, "vela_delantera"], ["VelaPopa", KEY_S, "vela_trasera"],
		["Ancla", KEY_SPACE, "anclado"]]
	for c in casos:
		var icono := hud.get_node_or_null("Estado/%s" % c[0])
		if not m.comprobar(icono != null and "activo" in icono, "hay icono %s" % c[0]):
			continue
		for vez in 2:
			await UtilesPruebas.tecla(arbol, c[1])
			await arbol.process_frame
			m.comprobar(bool(icono.get("activo")) == bool(b.get(c[2])),
				"el icono %s sigue a la tecla (%d)" % [c[0], vez],
				"icono %s, barco %s" % [icono.get("activo"), b.get(c[2])])
	# Travesía: un triángulo de «play» por cada vez de tiempo — 1, 2 o 4 —, leído del icono.
	var trav := hud.get_node_or_null("Estado/Travesia")
	var mando := b.get_node_or_null(^"MandoJugador")
	var tr: Node = mando.get_node_or_null(^"Travesia") if mando != null else null
	if m.comprobar(trav != null and "triangulos" in trav and tr != null,
			"el icono de travesía dibuja triángulos"):
		var vistos := []
		for n in [2, 4, 1]:
			tr.call("poner", n)
			await arbol.process_frame
			await arbol.process_frame
			vistos.append(int(tr.get("multiplicador")))
			m.comprobar(int(trav.get("triangulos")) == int(tr.get("multiplicador")),
				"travesía ×%d: tantos triángulos como veces" % int(tr.get("multiplicador")),
				"%d triángulos" % int(trav.get("triangulos")))
			# Centrados A LA VISTA: el centro de masas de la tinta en el centro del disco. Centrar la
			# caja deja un triángulo corrido hacia su base, que es lo que vio el usuario.
			if trav.has_method("triangulos_dibujados") and trav.has_method("centro_disco"):
				var suma := Vector2.ZERO
				var area := 0.0
				for tri: PackedVector2Array in trav.call("triangulos_dibujados"):
					var a := absf((tri[1] - tri[0]).cross(tri[2] - tri[0])) * 0.5
					suma += (tri[0] + tri[1] + tri[2]) / 3.0 * a
					area += a
				var cen: Vector2 = trav.call("centro_disco")
				m.menor_que((suma / maxf(area, 0.0001) - cen).length(), 0.5,
					"travesía ×%d: los triángulos centrados en el disco (px)" % int(tr.get("multiplicador")))
			else:
				m.comprobar(false, "el icono dice dónde pinta los triángulos")
		m.comprobar(vistos.has(2) or vistos.has(4), "la travesía llegó a acelerar para la prueba",
			str(vistos))
	# Las imágenes de Meshy están puestas: una ruta rota deja el marcador provisional sin avisar.
	for n in ["VelaProa", "VelaPopa", "Ancla", "Timon", "Batalla"]:
		var ic := hud.get_node_or_null("Estado/%s" % n)
		m.comprobar(ic != null and ic.get("icono") is Texture2D and ic.get("marco") is Texture2D,
			"el icono %s lleva su imagen y su marco" % n)
	var timon := hud.get_node_or_null("Estado/Timon")
	m.comprobar(timon != null and timon.get("icono_inactivo") is Texture2D,
		"el timón tiene icono de cubierta")
	m.comprobar(hud.get_node("Rosa").get("esfera") is Texture2D, "la rosa lleva su esfera")
	m.comprobar(hud.get_node("Cartela").get("fondo") is Texture2D, "la cartela lleva su pergamino")
	m.comprobar(hud.get_node_or_null("Corredera") != null
		and hud.get_node("Corredera").get("fondo") is Texture2D, "la corredera lleva su marco")
	m.comprobar(hud.get_node_or_null("Bateria") != null
		and hud.get_node("Bateria").get("icono_canon") is Texture2D, "la batería pinta los cañones")
	var batalla := hud.get_node_or_null("Estado/Batalla")
	if m.comprobar(batalla != null and "activo" in batalla, "hay icono Batalla"):
		await UtilesPruebas.tecla(arbol, KEY_B)
		m.comprobar(bool(batalla.get("activo")) and bool(b.get("modo_battle")),
			"el icono de batalla se enciende con B")
		await UtilesPruebas.tecla(arbol, KEY_B)
		m.comprobar(not bool(batalla.get("activo")), "y se apaga con B")
	b.set("anclado", true)


# El panel de batería solo con modo batalla; una marca por pieza, en su banda; y al disparar con
# el ratón las de la banda apuntada pasan a recargar y la munición baja lo que salió.
static func _bateria(m: MarcoPruebas, arbol: SceneTree, b: Node3D, hud: Node) -> void:
	await UtilesPruebas.al_timon(arbol)
	b.set("modo_battle", false)
	await arbol.process_frame
	var panel := hud.get_node_or_null("Bateria") as CanvasItem
	if not m.comprobar(panel != null, "hay panel de batería"):
		return
	m.comprobar(not panel.is_visible_in_tree(), "fuera de batalla el panel no se ve")
	await UtilesPruebas.tecla(arbol, KEY_B)
	await arbol.process_frame
	m.comprobar(panel.is_visible_in_tree(), "con B el panel se ve")

	var canones: Array = b.call("canones_de", "babor") + b.call("canones_de", "estribor")
	var marcas: Array = panel.call("marcas") if panel.has_method("marcas") else []
	m.comprobar(marcas.size() == canones.size(), "una marca por cañón",
		"%d marcas, %d cañones" % [marcas.size(), canones.size()])
	if marcas.size() != canones.size():
		b.set("modo_battle", false)
		return
	# Cada marca va en su banda: la de estribor a la derecha del eje del dibujo (proa arriba).
	var centro_x: float = (panel as Control).size.x * 0.5
	var bien := 0
	for mk in marcas:
		var c: Node = mk.get("canon")
		var lado_dibujo := signf((mk as Control).position.x + (mk as Control).size.x * 0.5 - centro_x)
		if c != null and lado_dibujo == (1.0 if c.call("banda") == "estribor" else -1.0):
			bien += 1
	m.comprobar(bien == marcas.size(), "cada marca está en la banda de su cañón",
		"%d de %d" % [bien, marcas.size()])

	# Esperar a que todo esté cargado, y disparar con el ratón la banda apuntada.
	for i in 400:
		if canones.all(func(c): return c.call("listo")):
			break
		await arbol.process_frame
	var banda := str(b.get("banda_apuntada"))
	var antes := int(b.get("municion"))
	var etiqueta := panel.get_node_or_null("Municion") as Label
	var clic := InputEventMouseButton.new()
	clic.button_index = MOUSE_BUTTON_LEFT
	clic.pressed = true
	Input.parse_input_event(clic)
	await arbol.process_frame
	clic = clic.duplicate()
	clic.pressed = false
	Input.parse_input_event(clic)
	await arbol.process_frame
	await arbol.process_frame
	var salieron := antes - int(b.get("municion"))
	m.mayor_que(float(salieron), 0.0, "el clic dispara la banda apuntada", "%d piezas" % salieron)
	var recargando := 0
	var cargadas_fuera := 0
	for mk in marcas:
		var c: Node = mk.get("canon")
		var carga := float(mk.get("carga"))
		if c.call("banda") == banda:
			if carga < 0.5 and not bool(mk.get("lista")):
				recargando += 1
		elif bool(mk.get("lista")):
			cargadas_fuera += 1
	m.comprobar(recargando == salieron, "las marcas de la banda que disparó pasan a recargar",
		"%d de %d" % [recargando, salieron])
	m.comprobar(cargadas_fuera == marcas.size() - canones.filter(
		func(c): return c.call("banda") == banda).size(),
		"las de la otra banda siguen listas")
	if m.comprobar(etiqueta != null, "hay etiqueta de munición"):
		m.comprobar(etiqueta.text.to_int() == int(b.get("municion")),
			"la munición del panel baja con el disparo", "'%s' / %d" % [etiqueta.text, b.get("municion")])
	# Y la carga avanza con el tiempo hasta volver a lista.
	var mk0: Node = null
	for mk in marcas:
		if mk.get("canon").call("banda") == banda:
			mk0 = mk
	var c0 := float(mk0.get("carga"))
	for i in 60:
		await arbol.process_frame
	m.mayor_que(float(mk0.get("carga")), c0, "el anillo de carga se va llenando",
		"%.2f → %.2f" % [c0, float(mk0.get("carga"))])
	b.set("modo_battle", false)
	await arbol.process_frame
	m.comprobar(not panel.is_visible_in_tree(), "al salir de batalla el panel se esconde")
	b.set("municion", antes)


# Las zonas de la silueta de daños se tiñen por la integridad del barco: verde sano, amarillo algo
# tocado, rojo crítico. El color se lee del dibujo de la zona.
static func _danos(m: MarcoPruebas, arbol: SceneTree, b: Node3D, hud: Node) -> void:
	var sil := hud.get_node_or_null("Danos")
	if not m.comprobar(sil != null and sil.has_method("color_de"), "hay silueta de daños"):
		return
	var integ = b.get("integridad")
	if not m.comprobar(integ is Dictionary and (integ as Dictionary).has("popa"),
			"el barco expone su integridad por zonas"):
		return
	var previo := (integ as Dictionary).duplicate()
	for caso in [[1.0, "verde"], [0.5, "amarillo"], [0.1, "rojo"]]:
		integ["popa"] = caso[0]
		await arbol.process_frame
		await arbol.process_frame
		var col: Color = sil.call("color_de", "popa")
		var tono := _tono(col)
		m.comprobar(tono == caso[1], "popa al %d %% se ve %s" % [int(caso[0] * 100), caso[1]],
			"sale %s (%s)" % [tono, col])
	m.comprobar(_tono(sil.call("color_de", "proa")) == "verde", "las demás zonas no cambian")
	for k in previo:
		integ[k] = previo[k]


static func _tono(c: Color) -> String:
	if c.s < 0.3:
		return "otro"
	var h := c.h * 360.0
	if h < 25.0 or h > 340.0:
		return "rojo"
	if h < 70.0:
		return "amarillo"
	if h < 170.0:
		return "verde"
	return "otro"
