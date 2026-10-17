extends Node

## Por qué el capitán de IA no dispara, y por qué corrige el rumbo a tirones. Tres bloques,
## porque son tres fallos distintos y desde fuera se ven igual —un enemigo que se pega y no
## tira—, pero se arreglan en sitios distintos:
##
##   1. **El alcance que CREE contra el que TIENE.** El capitán coloca su puesto de tiro a
##      `_alcance_real()` del enemigo, y ese número sale de medir la pieza con la cuña a cero.
##      Si el montaje llega mucho más lejos metiendo cuña, el capitán se pega al enemigo sin que
##      nada más lo delate: navega bien, apunta bien y pelea a la distancia equivocada.
##   2. **La ventana de tiro.** Con las dos balandras ancladas y la banda presentada, cuánto se
##      queda el tiro CORTO o LARGO y cuánto se va a la banda, a cada distancia. Es lo único que
##      separa "no llega" de "no afina": las dos se ven como cero disparos.
##   3. **La brusquedad del timón.** En un duelo de verdad, cuántas veces el timón salta de una
##      banda a la otra a tope y a qué velocidad iba el barco cuando lo hizo. El umbral de
##      `_lento()` está en 0,3 × `velocidad_max`, así que un barco que navegue justo ahí alterna
##      entre la ley proporcional y la de "no cruces el ojo" y se ve como un volantazo.
##
## No mide tela, así que vale con `--headless`:
##     godot --path . --headless tools/porque_no_dispara.tscn

## Altura de la lámina de agua, la del `Water` de `main_world.tscn`. Sin ella el tiro cae donde
## no es y los tres bloques miden otro juego (ver la nota de `tools/duelo.gd`).
const MAR := -0.8820801
const ESPERA := 4.0
const DURACION_DUELO := 60.0
const SEPARACION := 300.0
## Distancias a las que se prueba la ventana de tiro, en metros.
const DISTANCIAS := [40.0, 70.0, 110.0, 160.0, 220.0, 300.0]
## Segundos que se mira cada distancia. Más que una recarga (5 s) a propósito: con menos se ve
## la primera andanada y no si vuelve a tirar.
const VENTANA := 8.0
## Duración de la caza contra un barco fondeado, en segundos. La misma que usa la prueba.
const DURACION_CAZA := 45.0


func _ready() -> void:
	_viento_fijo()
	await _bloque_alcance()
	await _bloque_ventana()
	await _bloque_contra_fondeado()
	await _bloque_timon()
	get_tree().quit(0)


# ── 1. El alcance que cree, contra el que tiene ──────────────────────────────
func _bloque_alcance() -> void:
	print("\n═══ 1. El alcance que cree, contra el que tiene ═══")
	var b := await _soltar_balandra(Vector3.ZERO, true)
	var cap := _capitan_de(b)
	_adrizar(b)
	await _esperar(1.0)

	var piezas: Array = b.call("canones_de", "estribor")
	if piezas.is_empty():
		print("  sin piezas de artillería")
		return
	var p = piezas[0]
	var e0: float = float(p.get("elevacion"))
	print("  el capitán coloca su puesto de tiro a %.1f m del enemigo" % float(cap.call("alcance")))
	var maximo := 0.0
	for g in [-3.0, 0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0]:
		p.set("elevacion", g)
		var boca: Vector3 = p.call("boca_global")
		var cae: Vector3 = p.call("punto_de_caida")
		var d := Vector2(cae.x - boca.x, cae.z - boca.z).length()
		maximo = maxf(maximo, d)
		print("    cuña %5.1f° → %6.1f m" % [g, d])
	p.set("elevacion", e0)
	print("  alcance máximo %.1f m; pelea al %.0f %% de él"
		% [maximo, 100.0 * float(cap.call("alcance")) / maxf(maximo, 0.01)])
	b.queue_free()
	await get_tree().process_frame


# ── 2. La ventana de tiro ────────────────────────────────────────────────────
## Las dos ancladas y la atacante con la banda presentada, que es la postura en la que el
## capitán ya no tiene nada que maniobrar: lo único que queda es la puntería fina. Así el
## residuo que salga es de la cuña y del espeque, no de estar mal colocado.
func _bloque_ventana() -> void:
	print("\n═══ 2. La ventana de tiro: la puntería fina, con la banda ya presentada ═══")
	print("  %8s %-9s %7s %7s %9s %9s %s"
		% ["dist", "banda", "cuña", "espeque", "largo", "través", "disparos en 8 s"])
	for d in DISTANCIAS:
		var atacante := await _soltar_balandra(Vector3.ZERO, true)
		var blanco := await _soltar_balandra(Vector3(d, 0.0, 0.0), false)
		_adrizar(atacante)
		_adrizar(blanco)
		var cap := _capitan_de(atacante)
		# El contador va en un Array y no en un int porque **las lambdas de GDScript capturan
		# por VALOR**: con `var tiros := 0` el disparo incrementa su propia copia y la tabla sale
		# con cero disparos aunque la batería esté tirando sin parar.
		var tiros := [0]
		for n in atacante.find_children("*", "", true, false):
			if n.has_method("disparar") and n.has_signal("disparo"):
				n.connect("disparo", func(_dd: Vector3, _h: Vector3): tiros[0] += 1)

		# Se les sujeta el ancla, el rumbo Y LA POSICIÓN todos los frames: el capitán leva el
		# ancla en su `_zafarrancho`, así que sin sujetarlas las dos balandras se van a navegar y
		# lo que se mide ya no es la puntería fina sino la maniobra. Sin fijar la posición no
		# basta con fijar el rumbo: en los segundos que tardan en montarse, la atacante ya ha
		# arrancado y el blanco le queda 59° a popa del través en vez de por el costado.
		# Con proa al norte (−Z) y el enemigo en +X, lo tiene justo por el través de estribor.
		var mejor := INF
		var largo := NAN
		var traves := NAN
		var t := 0.0
		while t < VENTANA:
			_viento_fijo()
			atacante.set("anclado", true)
			blanco.set("anclado", true)
			atacante.global_rotation.y = 0.0
			blanco.global_rotation.y = 0.0
			atacante.global_position.x = 0.0
			atacante.global_position.z = 0.0
			blanco.global_position.x = d
			blanco.global_position.z = 0.0
			var r: Dictionary = cap.call("residuo_de_tiro")
			# Sólo cuenta con alguna pieza cargada: recargando, el residuo no existe y anotarlo
			# diría que la puntería es infinitamente mala cuando lo que pasa es que acaba de
			# disparar.
			if int(r["listas"]) > 0 and is_finite(float(r["largo"])):
				var e := absf(float(r["largo"])) + absf(float(r["traves"]))
				if e < mejor:
					mejor = e
					largo = float(r["largo"])
					traves = float(r["traves"])
			t += get_process_delta_time()
			await get_tree().process_frame

		if d == DISTANCIAS[0]:
			_ficha_de_la_banda(atacante, blanco)
		# La banda que el capitán ha apuntado, y la puntería de ESA banda: mirar siempre
		# estribor esconde justo el fallo de apuntar con la batería que no mira al enemigo.
		var banda: String = String(atacante.get("banda_apuntada"))
		var piezas: Array = atacante.call("canones_de", banda)
		var cuna := float(piezas[0].get("elevacion")) if not piezas.is_empty() else NAN
		var espeque := float(piezas[0].get("giro_lateral")) if not piezas.is_empty() else NAN
		# El DISPARO es la señal de que el tiro cubrió: el capitán sólo suelta la andanada cuando
		# la bala cae dentro de la elipse del casco enemigo, así que contar disparos mide lo mismo
		# que preguntar "¿cubre?" y además no se lo pierde. Preguntarlo desde fuera sí: al
		# muestrear se lee el frame siguiente, con las piezas ya recargando.
		print("  %6.0f m %-9s %6.2f° %6.2f° %+8.2f m %+8.2f m %8d"
			% [d, banda, cuna, espeque, largo, traves, tiros[0]])
		atacante.queue_free()
		blanco.queue_free()
		await get_tree().process_frame


## Pieza a pieza, en los ejes del BARCO: dónde está su boca, hacia dónde mira el ánima y hacia
## dónde cae el blanco. Los tres ángulos se cuentan desde el través de estribor y positivos hacia
## la PROA, que es la única forma de leer de un vistazo si el espeque satura porque el blanco cae
## fuera de su carrera o porque el ánima arranca torcida.
func _ficha_de_la_banda(atacante: Node3D, blanco: Node3D) -> void:
	var inv := atacante.global_transform.affine_inverse()
	for c in atacante.call("canones_de", "estribor"):
		var boca: Vector3 = inv * (c.call("boca_global") as Vector3)
		var animo: Vector3 = atacante.global_transform.basis.inverse() \
			* (c.call("direccion_global") as Vector3)
		var al_blanco: Vector3 = inv * blanco.global_position - boca
		print("    %-22s boca (%+.2f, %+.2f) | ánima %+7.2f° | blanco %+7.2f° | espeque %+6.2f°"
			% [c.name, boca.x, boca.z, rad_to_deg(atan2(-animo.z, animo.x)),
			rad_to_deg(atan2(-al_blanco.z, al_blanco.x)), float(c.get("giro_lateral"))])


# ── 2 bis. Un enemigo suelto contra un barco fondeado ────────────────────────
## El escenario de la prueba `ia / presenta la banda`: el jugador fondeado y el enemigo libre a
## 180 m. Es el caso en que un capitán puede orbitar eternamente sin llegar a presentar el
## costado, y desde fuera se ve igual que uno que no sabe apuntar — el barco navega, se acerca y
## no dispara. Lo que hay que mirar es la DEMORA: los grados entre el través y el blanco, porque
## el espeque sólo tiene 15° y fuera de esa ventana no hay tiro posible por bien que se apunte.
func _bloque_contra_fondeado() -> void:
	# El mismo viento que la prueba: en +Z, con el enemigo en +X del fondeado.
	_dir_viento = Vector3(0, 0, 1)
	print("\n═══ 2 bis. Enemigo suelto contra un barco fondeado, viento en +Z, %.0f s ═══" % DURACION_CAZA)
	var fondeado := await _soltar_balandra(Vector3.ZERO, false)
	var cazador := await _soltar_balandra(Vector3(180.0, 0.0, 0.0), true)
	var tiros := [0]
	for n in cazador.find_children("*", "", true, false):
		if n.has_method("disparar") and n.has_signal("disparo"):
			n.connect("disparo", func(_dd: Vector3, _h: Vector3): tiros[0] += 1)
	var cap := _capitan_de(cazador)

	print("  %5s %8s %-10s %9s %11s %7s %7s %7s %s"
		% ["t", "dist", "maniobra", "demora", "través", "vel", "f.vien", "caña", "disparos"])
	print("  (demora 0° = por la proa, 90° = por el través, que es donde se puede disparar)")
	var t := 0.0
	var siguiente := 0.0
	while t < DURACION_CAZA:
		_viento_fijo()
		fondeado.set("anclado", true)
		if t >= siguiente:
			siguiente += 5.0
			var local: Vector3 = cazador.global_transform.affine_inverse() \
				* fondeado.global_position
			# Demora desde la PROA: 0° por la proa, 90° por el través, 180° por la popa. Desde la
			# proa y no desde el través porque así no hay que envolver el ángulo, y envolviéndolo
			# mal salen demoras de 267° que no quieren decir nada.
			var demora := absf(rad_to_deg(Vector2(0, -1).angle_to(Vector2(local.x, local.z))))
			var r: Dictionary = cap.call("residuo_de_tiro")
			print("  %5.1f %8.1f %-10s %8.1f° %9s %7.2f %7.2f %7.2f %8d"
				% [t, cazador.global_position.distance_to(fondeado.global_position),
				String(cap.call("maniobra_actual")).left(10), demora,
				("%.2f m" % float(r["traves"])) if is_finite(float(r["traves"])) else "recargando",
				float(cazador.get("velocidad")), float(cazador.call("factor_viento")),
				float(cazador.get("orden_timon")), tiros[0]])
		t += get_process_delta_time()
		await get_tree().process_frame
	print("  total %d disparos en %.0f s" % [tiros[0], DURACION_CAZA])
	fondeado.queue_free()
	cazador.queue_free()
	_dir_viento = Vector3(1, 0, 0)
	await get_tree().process_frame


# ── 3. La brusquedad del timón ───────────────────────────────────────────────
## Dos capitanes peleando de verdad, y de la caña sólo dos cosas: cuántos VOLANTAZOS da —pasar
## de una banda a la otra con el timón a más de medio, que es lo que se ve desde fuera— y a qué
## velocidad iba el barco en cada uno. La velocidad es la mitad de la respuesta: si los
## volantazos caen todos alrededor de 0,3 × `velocidad_max`, el que los causa es el umbral de
## `_lento()` y no la táctica.
func _bloque_timon() -> void:
	print("\n═══ 3. La brusquedad del timón, en un duelo de %.0f s ═══" % DURACION_DUELO)
	var a := await _soltar_balandra(Vector3.ZERO, true, "azul")
	var b := await _soltar_balandra(Vector3(SEPARACION, 0.0, 0.0), true, "rojo")
	a.global_rotation.y = deg_to_rad(90.0)
	b.global_rotation.y = deg_to_rad(-90.0)
	a.set("anclado", false)
	b.set("anclado", false)

	var barcos := [a, b]
	var previo := [0.0, 0.0]
	var volantazos := [0, 0]
	var suma_cambio := [0.0, 0.0]
	var velocidades: Array[Array] = [[], []]
	var t := 0.0
	while t < DURACION_DUELO:
		_viento_fijo()
		t += get_process_delta_time()
		for i in 2:
			var o: float = float(barcos[i].get("orden_timon"))
			suma_cambio[i] += absf(o - previo[i])
			if signf(o) != signf(previo[i]) and absf(o) > 0.5 and absf(previo[i]) > 0.5:
				volantazos[i] += 1
				velocidades[i].append(float(barcos[i].get("velocidad")))
			previo[i] = o
		await get_tree().process_frame

	for i in 2:
		var maxima: float = float(barcos[i].get("velocidad_max"))
		var v: Array = velocidades[i]
		var media := 0.0
		for x in v:
			media += x
		media = media / float(v.size()) if not v.is_empty() else NAN
		print("  barco %d: %d volantazos, %.2f de recorrido de caña por segundo"
			% [i, volantazos[i], suma_cambio[i] / DURACION_DUELO])
		print("            velocidad media en el volantazo %.2f m/s (el umbral de _lento() está en %.2f)"
			% [media, maxima * 0.3])
	print("  distancia final %.1f m" % a.global_position.distance_to(b.global_position))


# ── Andamiaje ────────────────────────────────────────────────────────────────
func _soltar_balandra(donde: Vector3, con_capitan: bool, bando := "enemigo") -> Node3D:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	var b := esc.instantiate() as Node3D
	b.set("altura_mar", MAR)
	if con_capitan:
		# El capitán se cuelga ANTES de entrar al árbol: `Barco._ready` recorre sus hijos.
		var cap := CapitanIA.new()
		cap.name = "Capitan"
		cap.bando = bando
		b.add_child(cap)
	add_child(b)
	b.global_position = Vector3(donde.x, b.global_position.y, donde.z)
	b.set("anclado", true)
	await _esperar(ESPERA)
	return b


## Casco adrizado: sin la ola y sin las dos escoras de navegar. Medir alturas y ángulos de tiro
## con el casco tumbado mide la escora, no la puntería (ver `tools/alza_por_banda.gd`).
func _adrizar(b: Node3D) -> void:
	b.set("obediencia_escora", 0.0)
	b.set("obediencia_cabeceo", 0.0)
	b.set("brazo_giro", 0.0)
	b.set("brazo_velico", 0.0)


func _capitan_de(b: Node3D) -> Node:
	return b.get_node_or_null(^"Capitan")


func _esperar(s: float) -> void:
	var t := 0.0
	while t < s:
		_viento_fijo()
		t += get_process_delta_time()
		await get_tree().process_frame


## Viento fijo. La DIRECCION es una variable de la herramienta porque el bloque 2 bis reproduce
## el escenario de la prueba, que sopla en +Z, y con el viento en otro sitio la geometria del
## combate es otra: el puesto de tiro se elige contra el viento y el rumbo de la andanada tambien.
var _dir_viento := Vector3(1, 0, 0)


func _viento_fijo() -> void:
	# Asignar `Viento.direccion` no fija nada: el autoload la recalcula cada frame desde la BASE.
	Viento.direccion_base = _dir_viento
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	Viento.fuerza_base = 1.0
