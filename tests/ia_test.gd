class_name IaTest
extends RefCounted

## Paquete `ia`: que un `CapitanIA` gobierne de verdad el barco que le toca, sepa ceñir cuando
## el enemigo está a barlovento, y dispare presentando la banda en vez de a bulto.
##
## Las tres cosas que se rompen en silencio aquí, y que no dan ningún error en consola:
##
##   · **Que el mando se comparta.** Hoy la entrada vive dentro de `Barco` y `Input` es global,
##     así que dos barcos obedecen las mismas teclas (medido: los dos giraron +25,78° idénticos,
##     `tools/quien_obedece.tscn`). Un capitán de IA es imposible mientras eso siga así, y el
##     síntoma en el juego no es un error sino un enemigo que vira cuando viras tú.
##   · **Que el capitán no ciña.** Si pide el rumbo directo al enemigo y el enemigo está a
##     barlovento, se queda de proa al viento sin avanzar. No falla nada: simplemente el barco
##     enemigo parece tonto y no llega nunca.
##   · **Que dispare sin presentar la banda.** Los cañones son fijos al costado, así que un tiro
##     con el enemigo por la proa no puede tocar. Contar disparos no lo detecta —salen igual—;
##     hay que medir el ÁNGULO al enemigo en el instante del disparo.
##
## El enemigo se instancia aquí y no en `main_world.tscn` a propósito: el mundo del juego es de
## un barco y estas pruebas no deben cambiarlo.

## Cuánto se le da a cada escenario. Son segundos de juego y por tanto de reloj: es lo que
## cuesta que una balandra a 9 m/s recorra unos cientos de metros. No se puede acortar sin
## medir otra cosa.
##
## Y los bucles cuentan TIEMPO, no frames. `for i in int(45 * 60)` sólo son 45 s si el juego va
## a 60 fps clavados, y esta batería corre con ventana y con vsync: a 144 Hz son 18,7 s. El
## error no se ve —la prueba sigue dando verde o rojo, sólo que midiendo otra cosa— y aquí hacía
## que una pelea de "45 s" diera para dos andanadas y que un enemigo "de 40 s" de ceñida ganase
## la mitad del barlovento que le tocaba.
const T_MANDO := 4.0
const T_CENIDA := 40.0
const T_COMBATE := 45.0


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("ia")
	var mio := UtilesPruebas.barco(arbol)
	if not m.comprobar(mio != null, "hay un barco del jugador"):
		return

	# El nivel y la semilla se FIJAN: los capitanes los toman de `Ajustes`, que se carga del
	# `user://ajustes.cfg` del jugador, y la batería no puede depender de lo que él haya elegido.
	var ajustes := arbol.root.get_node_or_null(^"Ajustes")
	var nivel0 := String(ajustes.get("dificultad")) if ajustes != null and "dificultad" in ajustes else ""
	var semilla0 := int(ajustes.get("semilla")) if ajustes != null and "semilla" in ajustes else 0
	if nivel0 != "":
		ajustes.set("dificultad", "normal")
		ajustes.set("semilla", 1)

	await _mando_no_compartido(m, arbol, mio)
	await _cine_a_barlovento(m, arbol, mio)
	await _pelea_dentro_de_su_alcance(m, arbol, mio)
	await _presenta_la_banda(m, arbol, mio)
	await _sale_del_ojo(m, arbol, mio)
	await _elige_municion(m, arbol, mio)
	await _dificultad(m, arbol, mio)
	if nivel0 != "":
		ajustes.set("dificultad", nivel0)
		ajustes.set("semilla", semilla0)


# ── 1. El mando no se comparte ───────────────────────────────────────────────
## El capitán ordena timón a una banda y sólo SU barco tiene que girar. Es la prueba de que los
## controles salieron de `Barco`: mientras la entrada viva ahí, el enemigo gira con el jugador y
## el jugador gira con el enemigo.
static func _mando_no_compartido(m: MarcoPruebas, arbol: SceneTree, mio: Node3D) -> void:
	var enemigo := await _soltar_enemigo(arbol, mio, 250.0)
	if not m.comprobar(enemigo != null, "se puede instanciar un barco enemigo"):
		return
	var cap := enemigo.get_node_or_null(^"Capitan")
	if not m.comprobar(cap != null, "el enemigo lleva un CapitanIA"):
		return
	m.comprobar("orden_timon" in enemigo,
		"el barco expone `orden_timon` (los controles salieron de Barco)")

	# Con ARRANCADA, y de través: el timón gobierna con el agua que pasa por la pala, y un barco
	# recién nacido está parado. Esto antes pasaba porque el casco arrancaba a 2 m/s² constantes y a
	# los 4 s ya iba lanzado; con la resistencia del agua arranca como un barco, y el rumbo con que
	# nacía —heredado de lo que dejase el paquete anterior— decidía si andaba o no: 0,6° de giro.
	_viento(Vector3(1, 0, 0))
	enemigo.global_rotation = Vector3.ZERO
	var t := 0.0
	while t < 6.0:
		enemigo.set("anclado", false)
		t += arbol.root.get_process_delta_time()
		await arbol.process_frame
	var rumbo_mio := mio.global_rotation.y
	var rumbo_suyo := enemigo.global_rotation.y
	# Timón a tope, dado como ORDEN y no como tecla: es lo que hace la IA.
	t = 0.0
	while t < T_MANDO:
		enemigo.set("orden_timon", 1.0)
		enemigo.set("anclado", false)
		t += arbol.root.get_process_delta_time()
		await arbol.process_frame
	var giro_suyo := absf(rad_to_deg(wrapf(enemigo.global_rotation.y - rumbo_suyo, -PI, PI)))
	var giro_mio := absf(rad_to_deg(wrapf(mio.global_rotation.y - rumbo_mio, -PI, PI)))
	m.mayor_que(giro_suyo, 10.0, "el enemigo obedece la orden de timón de SU capitán")
	m.menor_que(giro_mio, 3.0, "el barco del jugador no se entera de esa orden")
	_retirar(enemigo)


# ── 2. Ciñe cuando el blanco está a barlovento ───────────────────────────────
## Se le pone el enemigo justo de donde viene el viento, que es el caso imposible: el rumbo
## directo cae dentro de la zona muerta (40° en la balandra) y no propulsa.
##
## Se miden DOS cosas y hacen falta las dos: que gane barlovento (si no, no sirve de nada) y que
## nunca se quede parado de proa al viento. Sólo la primera dejaría pasar un capitán que llega de
## milagro tras quedarse clavado medio minuto; sólo la segunda, uno que navega precioso hacia
## ninguna parte.
##
## Aquí HUBO una tercera —"ha dado al menos una virada"— y se quitó porque el escenario no la
## garantiza: trazando la ceñida se ve que el enemigo hace los 40 s en la misma amura y aun así
## gana sus 42 m, porque en cuanto se ha desplazado de la línea el punto de cita deja de caer en
## la zona muerta y lo alcanza de una bordada. Eso es navegar bien, no un fallo. Y además
## `viradas()` sólo cuenta los cambios de amura: volver al rumbo directo pasa por `_bordada = 0` y
## no se cuenta. La comprobación daba verde corriendo el paquete suelto y roja en la batería
## entera —tres de tres— porque el estado de la mar es otro, que es la firma de una prueba que
## depende del escenario y no del código.
##
## Lo que se mide es el TERRENO GANADO A BARLOVENTO, no la distancia al otro barco, y esa es la
## diferencia entre medir la ceñida y medir otra cosa: ciñendo se navega en zigzag, así que la
## distancia directa sube y baja con cada bordada. Y con la distancia se medía además el alcance
## de los cañones — el capitán se planta al llegar a su distancia de tiro y deja de acercarse,
## que es lo correcto —, así que el listón dependía de un número de artillería.
##
## Y por eso el enemigo sale a 600 m: desde 300 no tiene que ceñir nada, porque su distancia de
## tiro son ya 253 m. La prueba cazó exactamente eso cuando la distancia de combate subió.
static func _cine_a_barlovento(m: MarcoPruebas, arbol: SceneTree, mio: Node3D) -> void:
	_viento(Vector3(1, 0, 0))
	# El jugador queda a barlovento del enemigo: el viento sopla hacia +X, así que barlovento es
	# −X. El enemigo tendrá que ceñir para llegar hasta él.
	var enemigo := await _soltar_enemigo(arbol, mio, 0.0)
	if enemigo == null:
		return
	enemigo.global_position = mio.global_position + Vector3(600.0, 0.0, 0.0)
	# El escenario se FIJA entero, no se hereda. Esta comprobación mide cuánto barlovento gana el
	# enemigo persiguiendo al jugador, así que depende de dónde esté el jugador y de con qué amura
	# nace el enemigo — y las dos cosas venían de lo que hubiese dejado el paquete anterior. Medido:
	# corriendo el paquete `ia` solo daba 42,0-42,6 m y con `tela` delante 0,3-3,0, con el enemigo
	# navegando perfectamente (0,0 s de fachada) pero sin ganar terreno, porque perseguía un objetivo
	# que se le iba. Es la misma fragilidad que ya obligó a estrechar la bordada a 25 m.
	mio.global_rotation = Vector3.ZERO
	enemigo.global_rotation = Vector3.ZERO
	mio.set("anclado", true)
	mio.set("gobierno", true)
	var cap := enemigo.get_node_or_null(^"Capitan")
	# Se le estrecha la escalera de bordadas a propósito: con los 60 m de serie, que haya o no
	# una virada dentro de la ventana depende de qué amura le tocó al nacer, y la comprobación
	# salió 1, 1 y 0 en tres tiradas seguidas. Con 25 m la ceñida zigzaguea de verdad en 40 s,
	# que es lo que esta prueba quiere ver. Lo que mide no es el ancho: es que sepa virar.
	if cap != null:
		cap.set("ancho_bordada", 25.0)

	var x0: float = enemigo.global_position.x
	var parado := 0.0
	# Cuántas veces la proa CRUZA el ojo del viento, contra cuántas viradas ordena el capitán. Con
	# la inercia de guiñada el capitán empezaba la virada, perdía arrancada a mitad, la regla de
	# "lento, no cruces el ojo" la convertía en virada en redondo, y en cuanto recobraba arrancada
	# volvía a intentarla: un ciclo de 6 s con la proa entre −114° y −123° y sin cruzar nunca.
	var origen_v := Vector2(-1.0, 0.0)
	var lado_previo := 0.0
	var cruces := 0
	var viradas0 := int(cap.call("viradas")) if cap != null else 0
	var t := 0.0
	while t < T_CENIDA:
		_viento(Vector3(1, 0, 0))
		enemigo.set("anclado", false)
		mio.set("anclado", true)
		var dt := arbol.root.get_process_delta_time()
		# Parado es sin propulsión Y sin arrancada. Cruzar el ojo virando también va sin propulsión,
		# y desde que el casco tiene inercia de guiñada eso dura de verdad —medido, 13 s en una
		# virada que entra a 1,6 m/s y sale a 1,2—: contarlo como "clavado" mide la virada, no el
		# fallo. Con 0,5 m/s el barco aún gobierna; por debajo el timón ya no muerde.
		if float(enemigo.call("factor_viento")) < 0.05 and absf(float(enemigo.get("velocidad"))) < 0.5:
			parado += dt
		var pr := -enemigo.global_transform.basis.z
		var pv := Vector2(pr.x, pr.z).normalized()
		if pv.dot(origen_v) > 0.0:
			var lado := signf(pv.x * origen_v.y - pv.y * origen_v.x)
			if lado_previo != 0.0 and lado != 0.0 and lado != lado_previo:
				cruces += 1
			if lado != 0.0:
				lado_previo = lado
		t += dt
		await arbol.process_frame
	# Barlovento es −X, así que lo ganado es cuánto ha bajado su X.
	var ganado: float = x0 - enemigo.global_position.x

	# El listón va en FRACCIÓN de lo que el barco puede andar en la tirada, no en metros: lo que se
	# afirma es que GANA barlovento, no cuánto, y un número absoluto se pone rojo el día que se
	# toque la velocidad del casco sin que la IA tenga nada que ver. Pasó: `velocidad_max` bajó de
	# 9 a 4,5 m/s —la velocidad de casco real de esta balandra son 4,03— y lo ganado cayó de 42 a
	# 21 m, exactamente la mitad, con el capitán haciéndolo igual de bien. Un capitán roto da cero
	# o negativo.
	var puede: float = float(enemigo.get("velocidad_max")) * 40.0
	m.mayor_que(ganado, puede * 0.1, "ciñendo, el enemigo gana terreno a barlovento",
		"%.0f m en %.0f s" % [ganado, T_CENIDA])
	m.menor_que(parado, T_CENIDA * 0.25, "no se queda de proa al viento",
		"%.1f s de %.0f" % [parado, T_CENIDA])
	var ordenadas := (int(cap.call("viradas")) if cap != null else 0) - viradas0
	m.comprobar(cruces >= ordenadas, "la virada que empieza la termina",
		"%d viradas ordenadas, la proa cruzó el ojo %d veces" % [ordenadas, cruces])
	_retirar(enemigo)


# ── 3. Pelea dentro de su alcance, no pegado ─────────────────────────────────
## El capitán coloca su puesto de tiro a `_alcance_real()` del enemigo, así que ESE número es la
## distancia a la que pelea. Sale de medir la propia pieza, y eso es lo correcto; lo que se
## comprueba aquí es que se mida **con la cuña que va a usar** y no con el tubo a cero.
##
## Con la cuña a cero el alcance de esta balandra son 59 m y metiendo cuña llega a 490: el
## capitán peleaba al **15 %** de su alcance, o sea pegado al enemigo, y desde fuera eso se ve
## como un barco que se echa encima en vez de cañonear. No lo delata nada más —navega bien y
## apunta bien—, y por eso hace falta medirlo aquí. Medido con `tools/porque_no_dispara.tscn`.
##
## El listón es la MITAD porque es lo que deja margen de corrección a los dos lados: desde el
## medio de la carrera de la cuña se puede alargar y acortar el tiro, y desde el tope de abajo
## sólo se puede alargar.
static func _pelea_dentro_de_su_alcance(m: MarcoPruebas, arbol: SceneTree, mio: Node3D) -> void:
	var enemigo := await _soltar_enemigo(arbol, mio, 250.0)
	if enemigo == null:
		return
	var cap := enemigo.get_node_or_null(^"Capitan")
	var piezas: Array = enemigo.call("canones_de", "estribor")
	if not m.comprobar(cap != null and not piezas.is_empty(),
			"el enemigo lleva capitán y artillería"):
		_retirar(enemigo)
		return
	var p: Canon = piezas[0]
	# El alcance máximo del MONTAJE, preguntándoselo a la pieza con su propia cuña a tope. El
	# tope sale de la pieza (`Canon.ELEVACION_MAX`) y no de un número escrito aquí: el día que
	# el afuste admita más cuña, esta prueba lo sigue sola.
	var maximo := p.alcance_a(Canon.ELEVACION_MAX)
	var cree: float = float(cap.call("alcance"))
	m.mayor_que(cree / maxf(maximo, 0.01), 0.4,
		"pelea dentro de su alcance y no pegado al enemigo",
		"se coloca a %.0f m de un alcance máximo de %.0f (%.0f %%)"
			% [cree, maximo, 100.0 * cree / maxf(maximo, 0.01)])
	_retirar(enemigo)


# ── 4. Presenta la banda, apunta con ella y dispara ──────────────────────────
## Los cañones son fijos al costado, así que la única puntería posible es el rumbo del barco. Se
## anota el ángulo proa-enemigo en el INSTANTE de cada disparo, enganchándose a la señal de cada
## pieza: mirarlo después no vale, porque el barco sigue girando.
##
## Y de la misma pelea salen otras tres cosas, porque las tres se rompen en silencio y las tres
## se ven desde fuera como "un enemigo que no hace nada":
##
##   · **Cuántas veces dispara.** Con dos piezas por banda y 5 s de recarga, una pelea de 45 s da
##     para muchas andanadas. Que dispare UNA vez no prueba que sepa cañonear — y la
##     comprobación anterior se conformaba con eso.
##   · **Que apunte la batería que da al enemigo.** La banda se elegía por cuál tenía más piezas
##     cargadas, así que en cuanto disparaba la buena se pasaba a la otra: apuntaba a babor con
##     el enemigo a estribor, el espeque saturaba en sus 15° y el tiro caía a 120-320 m del
##     blanco. Medido con `tools/porque_no_dispara.tscn`, 4 de 6 distancias.
##   · **Que el timón no dé volantazos.** Pasar de una banda a la otra con la caña a tope es lo
##     que se ve como una corrección brusca. El umbral de `_lento()` no tenía histéresis, así que
##     un barco navegando justo en él alternaba entre dos leyes de gobierno: **1.176 volantazos
##     en 60 s** a 2,78 m/s, con el umbral en 2,70.
static func _presenta_la_banda(m: MarcoPruebas, arbol: SceneTree, mio: Node3D) -> void:
	_viento(Vector3(0, 0, 1))
	var enemigo := await _soltar_enemigo(arbol, mio, 180.0)
	if enemigo == null:
		return
	mio.set("anclado", true)
	# **Nace de través al viento y con la proa al blanco**, para que tenga que maniobrar y presentar
	# la banda. Nacía con el rumbo de la escena (0), que con este viento es la proa en el OJO y el
	# blanco ya por el través: se quedaba clavado ahí como una batería flotante y soltaba 18 tiros.
	# La prueba premiaba el bloqueo — cuando el capitán aprendió a salir del ojo ciando (21-10-2026)
	# cayó 80° para coger arrancada, perdió la demora y bajó a 6. Salir del ojo tiene su propia
	# prueba (`_sale_del_ojo`); esta mide la artillería.
	enemigo.global_rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)
	enemigo.set("velocidad", 0.0)
	enemigo.set("velocity", Vector3.ZERO)
	enemigo.set("_guinada", 0.0)

	var angulos: Array[float] = []
	for n in enemigo.find_children("*", "", true, false):
		if n.has_method("disparar") and n.has_signal("disparo"):
			n.connect("disparo", func(_d: Vector3, _h: Vector3):
				angulos.append(_angulo_al_blanco(enemigo, mio)))

	var volantazos := 0
	var previo := 0.0
	var banda_bien := 0
	var banda_mal := 0
	var t := 0.0
	while t < T_COMBATE:
		_viento(Vector3(0, 0, 1))
		enemigo.set("anclado", false)
		var orden: float = float(enemigo.get("orden_timon"))
		if signf(orden) != signf(previo) and absf(orden) > 0.5 and absf(previo) > 0.5:
			volantazos += 1
		previo = orden
		# ¿Apunta la banda que bate al blanco? Sólo cuenta cuando ALGUNA la bate: con el enemigo
		# por la proa o por la popa no hay respuesta correcta y contarlo sería ruido.
		var demora := _angulo_al_blanco(enemigo, mio)
		if demora > 40.0 and demora < 140.0:
			var local: Vector3 = enemigo.global_transform.affine_inverse() * mio.global_position
			var toca := "estribor" if local.x > 0.0 else "babor"
			if String(enemigo.get("banda_apuntada")) == toca:
				banda_bien += 1
			else:
				banda_mal += 1
		t += arbol.root.get_process_delta_time()
		await arbol.process_frame

	if not m.comprobar(not angulos.is_empty(), "el enemigo llega a abrir fuego",
			"%d disparos" % angulos.size()):
		_retirar(enemigo)
		return
	var peor := 0.0
	var de_proa := 0
	for a in angulos:
		peor = maxf(peor, absf(a - 90.0))
		if a < 40.0:
			de_proa += 1
	m.menor_que(peor, 45.0, "todos los disparos salen con la banda presentada",
		"el peor a %.0f° de la perpendicular, %d disparos" % [peor, angulos.size()])
	m.comprobar(de_proa == 0, "ninguna andanada con el enemigo por la proa",
		"%d de %d" % [de_proa, angulos.size()])
	m.mayor_que(float(angulos.size()), 8.0, "cañonea, no pega un tiro suelto",
		"%d disparos en %.0f s" % [angulos.size(), T_COMBATE])
	var vistas := banda_bien + banda_mal
	m.mayor_que(float(banda_bien) / maxf(float(vistas), 1.0), 0.8,
		"apunta la batería que bate al blanco",
		"%d de %d frames con el blanco por el costado" % [banda_bien, vistas])
	m.menor_que(float(volantazos), 20.0, "el timón no da volantazos",
		"%d cambios de banda con la caña a tope en %.0f s" % [volantazos, T_COMBATE])
	_retirar(enemigo)


# ── 5. Sale del ojo del viento ciando ────────────────────────────────────────
## Parado y con la proa clavada en el ojo, que es como nace una balandra en `tools/duelo.tscn` y
## como queda tras perder una virada. El casco CÍA (`Barco.cia_en_el_ojo`) y con arrancada atrás
## la caña obra al revés, así que el capitán tiene que meterla al contrario para abatir.
##
## Medido con `tools/capitan_en_el_ojo.tscn` antes del arreglo: **60 s de 60 en la zona muerta,
## 58 ciando, no sale**, en los cuatro casos. Dos fallos: aproado exacto pedía caña 0 (el lado
## salía del signo de un ángulo nulo y de una bordada que valía 0), y ciando metía la caña como si
## fuera avante — desde 4° la proa volvía al ojo en 9 s y ahí oscilaba ±0,6°.
##
## El listón sale del casco y no del capitán: con la caña a tope el JUGADOR sale de la zona muerta
## a los 29,3 s (`barco/ojo_del_viento`). Se le dan 45 s.
const T_OJO := 45.0

static func _sale_del_ojo(m: MarcoPruebas, arbol: SceneTree, mio: Node3D) -> void:
	_viento(Vector3(1, 0, 0))
	# Blanco de través: lo que pida el capitán cae fuera de la zona muerta, así que todo lo que
	# tenga que hacer es salir de ella.
	var enemigo := await _soltar_enemigo(arbol, mio, 0.0)
	if enemigo == null:
		return
	enemigo.global_position = mio.global_position + Vector3(0.0, 0.0, 200.0)
	mio.set("anclado", true)
	var muerto := float(enemigo.get("angulo_muerto"))
	var origen := Vector3(-1, 0, 0)
	# Proa a −X, de donde viene el viento, parado y sin guiñada.
	enemigo.global_rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)
	enemigo.set("velocidad", 0.0)
	enemigo.set("velocity", Vector3.ZERO)
	enemigo.set("_guinada", 0.0)
	var salida := -1.0
	var en_zona := 0.0
	var t := 0.0
	while t < T_OJO:
		_viento(Vector3(1, 0, 0))
		enemigo.set("anclado", false)
		mio.set("anclado", true)
		var dt := arbol.root.get_process_delta_time()
		var proa := -enemigo.global_transform.basis.z
		proa.y = 0.0
		if rad_to_deg(proa.normalized().angle_to(origen)) < muerto:
			en_zona += dt
		elif salida < 0.0:
			salida = t
		t += dt
		await arbol.process_frame
	m.comprobar(salida >= 0.0, "el capitán sale del ojo del viento ciando",
		("sale a los %.1f s" % salida) if salida >= 0.0 else "%.1f s de %.0f en la zona muerta"
			% [en_zona, T_OJO])
	m.menor_que(en_zona, T_OJO * 0.8, "no pasa la tirada con la proa en la zona muerta",
		"%.1f s de %.0f" % [en_zona, T_OJO])
	_retirar(enemigo)


# ── 6. Elige la munición por la situación ────────────────────────────────────
## La regla, acordada con el usuario el 21-10-2026: rasa por defecto y para rematar; palanqueta si
## el blanco HUYE con el aparejo aún entero y a tiro de palanqueta; metralla solo a quemarropa.
## Antes tiraba siempre rasa.
##
## Las distancias van en fracción del alcance que el capitán MIDE para cada tipo
## (`alcance_de`), no en metros: la palanqueta llega a la mitad que la rasa porque sale más
## despacio, y eso lo sabe la pieza.
##
## Los dos barcos fondeados; la huida se hace moviendo al blanco a mano por la línea que los une,
## que es lo que el capitán lee (cómo se abre la distancia). Cada caso se sostiene 2 s: ocho
## decisiones, de sobra para que la tasa de apertura (suavizada) pase su listón.
static func _elige_municion(m: MarcoPruebas, arbol: SceneTree, mio: Node3D) -> void:
	_viento(Vector3(1, 0, 0))
	var enemigo := await _soltar_enemigo(arbol, mio, 0.0)
	if enemigo == null:
		return
	var cap := enemigo.get_node_or_null(^"Capitan")
	if not m.comprobar(cap != null and cap.has_method("alcance_de"),
			"el capitán sabe el alcance de cada munición"):
		_retirar(enemigo)
		return
	cap.set("pausa_municion", 0.0)
	enemigo.set("pertrechos", {"rasa": 99, "palanqueta": 99, "metralla": 99})
	var r_pal := float(cap.call("alcance_de", "palanqueta"))
	var r_met := float(cap.call("alcance_de", "metralla"))
	var r_ras := float(cap.call("alcance_de", "rasa"))
	m.comprobar(r_met < r_pal and r_pal < r_ras, "cada munición llega a donde le toca",
		"rasa %.0f m, palanqueta %.0f m, metralla %.0f m" % [r_ras, r_pal, r_met])

	# [nombre, distancia, huye, casco del blanco, aparejo del blanco, metralla a bordo, esperada]
	var casos := [
		["a media distancia, el blanco quieto", r_pal * 0.7, false, 1.0, 1.0, 99, "rasa"],
		["a media distancia, el blanco huye", r_pal * 0.7, true, 1.0, 1.0, 99, "palanqueta"],
		["huye pero ya está desarbolado", r_pal * 0.7, true, 1.0, 0.3, 99, "rasa"],
		["a quemarropa", r_met * 0.3, false, 1.0, 1.0, 99, "metralla"],
		["a quemarropa con el casco deshecho", r_met * 0.3, false, 0.2, 1.0, 99, "rasa"],
		["a quemarropa sin metralla a bordo", r_met * 0.3, false, 1.0, 1.0, 0, "rasa"],
	]
	for c in casos:
		var lado := Vector3(0, 0, 1)
		mio.global_position = enemigo.global_position + lado * float(c[1])
		var p: Dictionary = enemigo.get("pertrechos")
		p["metralla"] = int(c[5])
		enemigo.set("municion_actual", "rasa")
		var t := 0.0
		while t < 2.0:
			_viento(Vector3(1, 0, 0))
			enemigo.set("anclado", true)
			mio.set("anclado", true)
			# Cada frame: un tocado del enemigo REPARA al blanco (ver `_soltar_enemigo`), y eso
			# le devolvería la integridad a mitad de caso.
			var integ: Dictionary = mio.get("integridad")
			for z in ["proa", "babor", "estribor", "popa"]:
				integ[z] = float(c[3])
			integ["aparejo"] = float(c[4])
			var dt := arbol.root.get_process_delta_time()
			if bool(c[2]):
				mio.global_position += lado * 3.0 * dt
			t += dt
			await arbol.process_frame
		m.comprobar(String(enemigo.get("municion_actual")) == String(c[6]),
			"munición %s: %s" % [c[0], c[6]],
			"carga %s a %.0f m" % [enemigo.get("municion_actual"),
				enemigo.global_position.distance_to(mio.global_position)])
	if mio.has_method("reparar"):
		mio.call("reparar")
	_retirar(enemigo)


# ── 7. Dificultad ────────────────────────────────────────────────────────────
## El capitán acertaba demasiado (69-88 % en `tools/duelo.tscn`): su puntería prueba la pieza
## hasta dejar el tiro a ±0,3 m. La dificultad, acordada con el usuario el 21-10-2026: tres
## niveles que sortean en cada andanada un ERROR DE ESTIMA en metros sobre el blanco, que la cuña
## y el espeque persiguen como si fuera el blanco de verdad. Se guarda en `Ajustes`, en
## `user://ajustes.cfg`.
##
## Lo que se mide es el residuo del tiro contra el blanco VERDADERO en el instante de cada
## andanada (`CapitanIA.andanada`), que es justo la variable que la dificultad cambia — no los
## tocados, que dependen además de la mar y del casco.
const T_PUNTERIA := 20.0

static func _dificultad(m: MarcoPruebas, arbol: SceneTree, mio: Node3D) -> void:
	var ajustes := arbol.root.get_node_or_null(^"Ajustes")
	if not m.comprobar(ajustes != null and "dificultad" in ajustes and ajustes.has_method("cargar"),
			"los ajustes tienen dificultad y se pueden cargar"):
		return
	# Se guarda y se lee en un archivo de PRUEBAS: el del jugador no se toca.
	var ruta0: String = ajustes.get("ruta")
	var nivel0: String = ajustes.get("dificultad")
	ajustes.set("ruta", "user://ajustes_prueba.cfg")
	ajustes.call("set_dificultad", "facil")
	ajustes.set("dificultad", "dificil")
	ajustes.call("cargar")
	m.comprobar(String(ajustes.get("dificultad")) == "facil",
		"la dificultad se guarda en user:// y se lee", "leída: %s" % ajustes.get("dificultad"))
	var cap_suelto := CapitanIA.new()
	m.comprobar(String(cap_suelto.call("nivel")) == "facil",
		"el capitán toma la dificultad de los ajustes", "nivel %s" % cap_suelto.call("nivel"))
	ajustes.set("dificultad", "normal")
	m.comprobar(String(cap_suelto.call("nivel")) == "normal",
		"y la sigue si cambia en partida", "nivel %s" % cap_suelto.call("nivel"))
	cap_suelto.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ajustes_prueba.cfg"))
	ajustes.set("ruta", ruta0)
	ajustes.set("dificultad", nivel0)

	# Misma semilla, mismos errores: las pruebas y las medidas se pueden repetir.
	var series := []
	for s in [7, 7, 8]:
		var c := CapitanIA.new()
		c.set("dificultad", "normal")
		c.call("set_semilla", s)
		var l := []
		for i in 5:
			l.append(c.call("sortear_error"))
		series.append(l)
		c.free()
	m.comprobar(series[0] == series[1] and series[0] != series[2],
		"con la misma semilla el error sorteado se repite", str(series[0]))

	# La dispersión de verdad, peleando: los dos fondeados, el blanco por el través a 150 m y a
	# BARLOVENTO. Fondeado con el trapo arriba el casco escora a sotavento, y por esa banda la cuña
	# tope (12°) solo llegaba a 101-132 m: el blanco a 148 quedaba fuera de alcance y fácil no
	# disparaba nunca.
	_viento(Vector3(1, 0, 0))
	var enemigo := await _soltar_enemigo(arbol, mio, 0.0)
	if enemigo == null:
		return
	var cap := enemigo.get_node_or_null(^"Capitan")
	enemigo.global_rotation = Vector3.ZERO
	enemigo.global_position = mio.global_position + Vector3(150.0, 0.0, 0.0)
	var rms := {}
	for nivel in ["facil", "normal", "dificil"]:
		cap.set("dificultad", nivel)
		cap.call("set_semilla", 11)
		var errores: Array[float] = []
		var anota := func(r: Dictionary):
			errores.append(Vector2(float(r["largo"]), float(r["traves"])).length())
		cap.connect("andanada", anota)
		var t := 0.0
		while t < T_PUNTERIA:
			_viento(Vector3(1, 0, 0))
			enemigo.set("anclado", true)
			mio.set("anclado", true)
			t += arbol.root.get_process_delta_time()
			await arbol.process_frame
		cap.disconnect("andanada", anota)
		var suma := 0.0
		for e in errores:
			suma += e * e
		rms[nivel] = sqrt(suma / maxf(float(errores.size()), 1.0)) if not errores.is_empty() else -1.0
		m.mayor_que(float(errores.size()), 3.0, "en %s dispara" % nivel,
			"%d andanadas en %.0f s, residuo cuadrático %.1f m" % [errores.size(), T_PUNTERIA, rms[nivel]])
	m.comprobar(rms["facil"] > rms["normal"] and rms["normal"] > rms["dificil"],
		"la dificultad ordena la puntería: fácil peor que normal, normal peor que difícil",
		"residuo %.1f / %.1f / %.1f m" % [rms["facil"], rms["normal"], rms["dificil"]])
	if mio.has_method("reparar"):
		mio.call("reparar")
	_retirar(enemigo)


# ── Andamiaje ────────────────────────────────────────────────────────────────
## Mete un barco enemigo en el mundo con su capitán puesto.
##
## El capitán se cuelga ANTES de entrar al árbol porque `Barco._ready` recorre sus hijos y llama
## a `configurar` sobre los que lo tengan; añadido después, se queda sin barco.
##
## Y hay que sacarlo de `barco_activo`: **cada `Barco` se mete solo en ese grupo en su `_ready`**,
## así que un segundo barco se anuncia como el del jugador y el mar, el HUD y la cámara se van
## con él. Eso es del mismo refactor que mueve el mando: quién es el barco del jugador lo decide
## quien sube al jugador a bordo, no el barco.
static func _soltar_enemigo(arbol: SceneTree, mio: Node3D, distancia: float) -> Node3D:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	if esc == null:
		return null
	var b := esc.instantiate() as Node3D
	b.name = "Enemigo"
	var cap := CapitanIA.new()
	cap.name = "Capitan"
	cap.bando = "enemigo"
	b.add_child(cap)
	mio.get_parent().add_child(b)
	b.remove_from_group("barco_activo")
	b.global_position = mio.global_position + Vector3(distancia, 0.0, 0.0)
	b.global_position.y = mio.global_position.y
	# Que cargue el modelo, monte la artillería y la tela se estabilice.
	for i in 180:
		await arbol.process_frame
	# **El blanco de este paquete no se rompe.** Desde que las balas dañan (19-10-2026, paquete
	# `municion`), el enemigo HUNDÍA al jugador en 45 s de cañoneo: el capitán se quedaba sin blanco
	# y su timón daba 40 bandazos, y el resto de la batería corría con el barco en el fondo. Aquí se
	# mide cómo gobierna y apunta, no lo que rompe, así que cada impacto deja al jugador como estaba.
	if mio.has_method("reparar"):
		for n in b.find_children("*", "", true, false):
			if n.has_signal("impacto") and n.has_method("disparar"):
				n.connect("impacto", func(_d: Vector3, _c: Node): mio.call("reparar"))
	return b


static func _retirar(b: Node3D) -> void:
	if b != null and is_instance_valid(b):
		var p := b.get_parent()
		if p != null:
			p.remove_child(b)
		b.queue_free()


## Grados entre la proa y la línea al blanco, sin signo: 0 = por la proa, 90 = por el través.
static func _angulo_al_blanco(desde: Node3D, hasta: Node3D) -> float:
	var proa := -desde.global_transform.basis.z
	proa.y = 0.0
	var d := hasta.global_position - desde.global_position
	d.y = 0.0
	if proa.length() < 0.001 or d.length() < 0.001:
		return 0.0
	return rad_to_deg(proa.normalized().angle_to(d.normalized()))


## Viento fijo. Tocar `Viento.direccion` no sirve: el autoload la recalcula cada frame desde la
## BASE con su bamboleo y sus ráfagas del ±45 %.
static func _viento(dir: Vector3) -> void:
	Viento.direccion_base = dir
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	Viento.fuerza_base = 1.0
