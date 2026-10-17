class_name TelaTest
extends RefCounted

## Paquete `tela`: el soldado, los anclajes, la recogida y —sobre todo— que el paño no nazca
## estirado. Los umbrales de abajo salen de medidas reales, no de números redondos; están
## holgados respecto a lo medido para que la prueba no chille por una ráfaga.
##
## Partido en ESCENARIOS que se preparan solos —ancla, rumbo, viento— y devuelven el barco con
## el ancla con que lo encontraron, para poder pedir uno suelto (`-- tela/costura`).


## Las ventanas de medida (los segundos de `navegar`, `ondeo` y `relieve_del_pico`) están al
## mínimo que conserva el margen medido, porque cada segundo aquí es un segundo de reloj: la
## tela no se simula en `--headless` y no se puede acelerar el reloj sin desincronizar las anclas
## —que se recolocan en `_process`— de la física. El barco llega a su velocidad en ~5 s, así que
## navegar 6 basta. Si alguna se vuelve intermitente, **sube la ventana, no bajes el tope**.


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("tela")
	# CUÁNTOS paños físicos hay depende de la bandera, que se ha probado de las dos formas: fue
	# física, pasó a shader el 9 de septiembre de 2026 por el enrollado en el mástil, y está de
	# vuelta en física para revisar si aquel defecto sigue ahí ahora que el viento aparente está
	# arreglado. Así que aquí se exige lo que no depende de eso —el foque y la mayor— y de la
	# bandera se comprueba, más abajo, lo que corresponda a la que esté montada.
	var telas := UtilesPruebas.telas(arbol)
	var por_nombre := {}
	for t in telas:
		por_nombre[str(t.get("nombre_malla"))] = t
	if not m.comprobar(por_nombre.has("foque") and por_nombre.has("vela_mayor"),
			"la balandra monta el foque y la mayor como paños físicos",
			", ".join(por_nombre.keys())):
		return

	if m.escenario("montaje"):
		_montaje(m, arbol, telas, por_nombre)
	if m.escenario("nacimiento"):
		await _nacimiento(m, arbol, por_nombre)
	if m.escenario("arriar"):
		await _arriar(m, arbol, por_nombre["vela_mayor"])
	if m.escenario("popa_obenques"):
		await _popa_obenques(m, arbol, por_nombre["vela_mayor"])
	if m.escenario("popa_navegando"):
		await _popa_navegando(m, arbol, por_nombre["vela_mayor"])
	if m.escenario("bandera"):
		_bandera(m, arbol)
	if m.escenario("bandera_enrollado"):
		await _bandera_enrollado(m, arbol)
	if m.escenario("bandera_sotavento"):
		await _bandera_sotavento(m, arbol)
	if m.escenario("bandera_aparente"):
		await _bandera_aparente(m, arbol)
	if m.escenario("costura"):
		await _costura(m, arbol, por_nombre["vela_mayor"])
	if m.escenario("anclas"):
		await _anclas(m, arbol, por_nombre)
	if m.escenario("flameo"):
		await _flameo(m, arbol, por_nombre["vela_mayor"])


## Lo que se lee del montaje sin dejar correr el tiempo: cuántos puntos, qué anclajes, qué
## aparejo y qué área de viento. Es instantáneo.
static func _montaje(m: MarcoPruebas, arbol: SceneTree, telas: Array, por_nombre: Dictionary) -> void:
	m.comprobar(por_nombre.get("vela_mayor") is VelaFisica, "la mayor es una VelaFisica")
	# Un paño no puede estar montado dos veces: `TelaFisica` oculta la malla de autor para poner
	# su `SoftBody` en su sitio y `TelaShader` la necesita visible, así que juntos no funcionan.
	m.comprobar(telas.size() == por_nombre.size(),
		"ningún paño está montado dos veces", "%d telas, %d nombres" % [telas.size(), por_nombre.size()])

	# --- Soldado de costuras: sin él, glTF parte los vértices del UV y el paño se descose.
	#
	# La mayor bajó de 1.347/1.217 a 678/613 el 9 de septiembre de 2026: tenía 36,4 vértices por
	# m² contra los 16,9 del foque, o sea el doble de fina sin motivo. Se le quitó una línea de
	# cada dos con `unsubdivide` —que conserva la rejilla de cuadriláteros, las cuatro capas UV,
	# `Col` y los pesos, porque los vértices que quedan son un SUBCONJUNTO de los originales, y
	# por eso no hubo que rehornear nada— más 4 vértices repuestos en la baluma, cuya curva se
	# cortaba en recto y perdía 167 mm de silueta. Con ellos, la desviación máxima es de 13,5 mm.
	var soldados := {"foque": [253, 207], "vela_mayor": [678, 613]}
	for nombre in soldados:
		var d: Dictionary = por_nombre[nombre].datos_depuracion()
		var n: int = (d["fijo"] as PackedByteArray).size()
		m.comprobar(n == soldados[nombre][1], "'%s' suelda a %d puntos" % [nombre, soldados[nombre][1]],
			"%d" % n)

	# --- Anclajes por el canal AZUL de Col.
	for nombre in ["foque", "vela_mayor"]:
		var d: Dictionary = por_nombre[nombre].datos_depuracion()
		var fijo: PackedByteArray = d["fijo"]
		var n := 0
		for k in fijo.size():
			if fijo[k] == 1:
				n += 1
		m.comprobar(n > 0, "'%s' tiene anclajes marcados en azul" % nombre, "%d" % n)

	# --- Y la garantía de que no nace estirado: el paño no se monta en un frame largo. Se
	# comprueba la condición, no el síntoma: que salga bien un día concreto depende de si el
	# frame en que nació fue corto por casualidad.
	for nombre in ["foque", "vela_mayor"]:
		var dd: Dictionary = por_nombre[nombre].datos_depuracion()
		var dm: float = dd.get("delta_montaje", 1.0)
		var tope: float = float(por_nombre[nombre].get("delta_estable"))
		m.comprobar(dm <= tope or dd.get("espera_montaje", 0.0) >= float(por_nombre[nombre].get("espera_max")),
			"'%s' nace con el reloj fino, no en un tirón" % nombre, "frame de %.3f s" % dm)

	# --- Cada vela tiene SU aparejo. Un sub-recurso de escena se comparte entre instancias, y
	# si se comparte, dos velas del mismo barco se izarían a la vez.
	m.comprobar(por_nombre["foque"].get("aparejo") != por_nombre["vela_mayor"].get("aparejo"),
		"foque y mayor no comparten aparejo")

	# --- Cada paño lo gobierna SU ÁREA de viento, no la del vecino. Las áreas son esferas de
	# 30 m con `SPACE_OVERRIDE_REPLACE` y la misma prioridad, así que las tres cubren los tres
	# paños y solo puede mandar una. Estuvo mandando la del foque sobre la bandera, y por eso el
	# empuje, el peso propio y el flameo de la bandera no hacían nada. Se separan por capa.
	var cuerpos := {}
	for t in telas:
		var dd: Dictionary = t.datos_depuracion()
		if not dd.is_empty():
			cuerpos[str(t.get("nombre_malla"))] = (dd["cuerpo"] as SoftBody3D).collision_layer
	var cruces := 0
	for a in UtilesPruebas.barco(arbol).find_children("AreaViento_*", "Area3D", true, false):
		var ar := a as Area3D
		var mia := ar.name.trim_prefix("AreaViento_")
		for nombre in cuerpos:
			if nombre != mia and (ar.collision_mask & int(cuerpos[nombre])) != 0:
				cruces += 1
		if cuerpos.has(mia):
			m.comprobar((ar.collision_mask & int(cuerpos[mia])) != 0,
				"'%s' recibe el viento de su propia área" % mia)
	m.comprobar(cruces == 0, "ningún área de viento gobierna el paño de otra", "%d cruces" % cruces)


# --- El paño NO nace estirado. Es lo que rompía el arranque: un frame largo del arranque
# hacía caer la tela varios pasos de física con los anclajes congelados, y el solver ya no
# cerraba esas aristas. Medido tras el arreglo: 0 aristas por encima del 25 % en las velas.
# La bandera lleva un tope más ancho porque tiene UNA sola columna de anclajes (11, la que
# roza el mástil): con dos, la segunda sujetaba paño que debe volar. Estuvo en rojo el 8 de
# septiembre de 2026, con ~30 aristas pasadas, y la causa era la cápsula del mástil,
# que se llevaba sus 11 anclajes 53 mm dentro. Ver `perchas_solidas.gd`.
static func _nacimiento(m: MarcoPruebas, arbol: SceneTree, por_nombre: Dictionary) -> void:
	var previo := _guardar(arbol)
	await UtilesPruebas.estabilizar(arbol, 3.0)
	#
	# **El foque tolera 1 arista y la mayor ninguna, y eso es una decisión, no un descuido.**
	# Es el precio medido de bajar la física a 60 Hz el 10 de septiembre de 2026: el foque nace
	# con una arista pasada y no cierra. Descartado midiendo, no lo repitas: el solver
	# (`precision` 5, 10 y 20 dan EXACTAMENTE la misma arista) y el frame del nacimiento (con
	# `delta_estable` a 1/60 el paño nace en 0,000-0,006 s y sigue ahí). En tamaño real es
	# poco: fondeado, la peor arista del foque mide 19,1 % sobre 30,9 mm —5,9 mm— contra 10,4 %
	# y 3,2 mm a 120 Hz. Tres milímetros en una arista de tres centímetros.
	#
	# Por eso va acompañada del tope en METROS, que es el que de verdad guarda contra un
	# desgarro: el porcentaje engaña —una arista de reposo corta se pone al 240 % con dos
	# centímetros y no se ve—, mientras que el desgarro del nacimiento abría 63 aristas y las
	# dejaba abiertas para siempre. Si eso vuelve, salta el de metros aunque el de cuenta pase.
	var topes := {"foque": [0.02, 1], "vela_mayor": [0.02, 0]}
	for nombre in topes:
		var e: Dictionary = await UtilesPruebas.estiramiento(arbol, por_nombre[nombre])
		m.menor_que(e["medio"], topes[nombre][0], "'%s' no nace estirado" % nombre)
		m.comprobar(e["malas"] <= topes[nombre][1],
			"'%s': ninguna arista pasada de vueltas" % nombre,
			"%d por encima del 25 %%, tope %d" % [e["malas"], topes[nombre][1]])
		m.menor_que(e["peor_m"], 0.030,
			"'%s': ninguna arista se abre de verdad" % nombre)
	await _devolver(arbol, previo)


# --- Arriar recoge el paño (y con ello el viento deja de afectarle); izar lo suelta.
static func _arriar(m: MarcoPruebas, arbol: SceneTree, mayor: Node) -> void:
	var previo := _guardar(arbol)
	await UtilesPruebas.al_timon(arbol)
	# Fondeado y con viento fijo, como se medía cuando venía detrás de `nacimiento`.
	await UtilesPruebas.estabilizar(arbol, 0.5)
	var apa: Variant = mayor.get("aparejo")
	# S es un conmutador: se parte de la mayor izada, que es como sale el barco.
	if apa != null and apa.arriado_medido() > 0.5:
		await UtilesPruebas.tecla(arbol, KEY_S)
		for i in 400:
			await arbol.process_frame
	await UtilesPruebas.tecla(arbol, KEY_S)
	for i in 400:
		await arbol.process_frame
	m.casi(apa.arriado_medido() if apa != null else -1.0, 1.0, 0.05, "al arriar, la driza recorre todo")
	var e_arr: Dictionary = await UtilesPruebas.estiramiento(arbol, mayor)
	m.comprobar(bool(e_arr["recogiendo"]), "y el paño queda recogido")
	await UtilesPruebas.tecla(arbol, KEY_S)
	for i in 400:
		await arbol.process_frame
	m.casi(apa.arriado_medido() if apa != null else -1.0, 0.0, 0.05, "al izar, la driza vuelve")
	var e_iza: Dictionary = await UtilesPruebas.estiramiento(arbol, mayor)
	m.comprobar(not bool(e_iza["recogiendo"]), "y el paño se vuelve a soltar")
	m.menor_que(e_iza["medio"], 0.03, "sin estirarse al desplegar")
	await _devolver(arbol, previo)


# --- LA PERCHA TOPA EN LA JARCIA. La mayor y los obenques salen del MISMO palo, así que
# en cuanto el paño gira más que el obenque de popa de su banda los dos se cruzan y la jarcia
# aparece atravesando la lona. No es un roce: medido con `tools/vela_en_obenques.tscn` con el
# tope de percha en 80°, a 150° de viento pasaban los **613 puntos de 613**, y a 120° ya 199.
# El obenque de popa de esta balandra está a 68,5° del eje del mástil, y ese ángulo es el
# tope de trimado: no es un número elegido, es dónde topa la percha de verdad.
#
# Se mide EN POPA CERRADA, que es donde la regla de la mitad manda abrir del todo y donde el
# usuario lo vio. A un traés la vela no llega ni a 51° y la comprobación pasaría sola.
#
# Lo que se exige es que el PLANO del paño no pase del obenque, no que no lo pase ni un punto.
# Exigir cero es más estricto que la realidad y que este modelo: la lona tiene barriga y sus
# puntos más hinchados salen 6,4-6,9° del plano de la percha, así que con la vela justo en el
# tope quedan ~185 de 613 por fuera y solo se llegaría a cero cerrando la vela tanto que no
# abriría ni al traés. Con el defecto puesto esta comprobación lee **86,2° contra 68,5 y los
# 613 puntos**, así que discrimina de sobra. Y apoyar la lona en un cuerpo DEL GROSOR del cabo
# no lo arregla: probado, 476 puntos pasados contra 475 sin él, porque esta malla tiene 25 cm de
# arista y el cabo 1,5 cm de radio y los puntos pasan entre las cápsulas. Lo que sí la apoya es
# el muro grueso de detrás del cabo, que comprueba la siguiente.
static func _popa_obenques(m: MarcoPruebas, arbol: SceneTree, mayor: Node) -> void:
	var previo := _guardar(arbol)
	var barco := UtilesPruebas.barco(arbol)
	await UtilesPruebas.estabilizar(arbol, 12.0,
		(barco.global_transform.basis * Vector3(-0.34, 0.0, -0.94)).normalized())
	var jar: Dictionary = await UtilesPruebas.vela_en_jarcia(arbol, barco, mayor)
	m.comprobar(absf(jar.get("az_vela", 999.0)) <= absf(jar.get("az_obenque", 0.0)),
		"en popa la mayor no traspasa los obenques",
		"vela a %.1f°, obenque a %.1f° (%d de %d puntos pasados)"
			% [jar.get("az_vela", 0.0), jar.get("az_obenque", 0.0),
				jar.get("pasados", -1), jar.get("total", 0)])

	# --- Y NINGÚN OBENQUE SALE POR EL MEDIO DEL PAÑO. Lo de arriba mira el PLANO de la vela; esto
	# mira la barriga, que es lo que el usuario vio: con la percha topada a 59° la lona se hincha
	# 6-7° fuera de su plano y el obenque de popa le atravesaba **2 caras** a partir de 120° de
	# viento, en las dos bandas (`tools/vela_en_obenques.tscn`). Se cuenta cruzando el eje de cada
	# cabo con los triángulos del paño, que no confunde la lona que se APOYA en el cabo con la que
	# lo deja dentro. Varias muestras, porque la lona flamea y un cruce puede ir y venir.
	var atravesadas := 0
	var cabos := {}
	for _k in 10:
		var c: Dictionary = await UtilesPruebas.jarcia_por_la_lona(arbol, barco, mayor)
		if int(c.get("cruces", 999)) > atravesadas:
			atravesadas = int(c.get("cruces", 999))
			cabos = c.get("por_cabo", {})
		for _f in 6:
			await arbol.physics_frame
	m.comprobar(atravesadas == 0, "en popa ningún obenque atraviesa la mayor",
		"%d caras atravesadas %s" % [atravesadas, cabos])
	await _devolver(arbol, previo)


# --- LA LONA APOYADA EN EL MURO DEL OBENQUE, que `popa_obenques` no llega a probar: fondeado con
# viento de 160° la mayor pasa del obenque por azimut pero NO toca el muro (se queda a
# centímetros), así que su cero de caras no dice nada del muro. La lona solo llega a él si viene
# con más empuje: navegando de través y trasluchando mientras el barco frena —que es como se
# llega a popa jugando— o fondeado con el viento más a popa, 175°. En los dos casos, medido el
# 17-10-2026 con `tools/popa_tras_navegar.tscn`, 24-25 puntos libres se quedaban metidos en el
# muro, hasta 14 cm, y el obenque de popa atravesaba SIEMPRE las mismas 2 caras (122 y 235 de la
# malla soldada), en la banda en que cayera la vela. La vela quedaba IDÉNTICA con el muro de
# 20 cm que con uno de 2 cm: el muro no hacía nada.
#
# No era la lona al otro lado del muro (ningún punto lo rodea) ni el contacto (en aislado, con
# `tools/lona_contra_capsula.tscn`, un paño a 40 m/s² no entra ni 1 mm, y uno que nace dentro
# sale). Era la caja del `SoftBody3D` en la fase ancha, que Godot Physics no rehace si el paño se
# mueve menos de 5 cm por paso: a 2,9 m/s el barco se la dejaba atrás, y abriendo despacio la
# vela crecía fuera de ella. Sin caja que lo toque no hay par con el muro. Lo arregla
# `TelaFisica._vigilar_caja`, y rehacer la caja a mano en el estado roto sacaba la lona sola.
#
# Por eso se exige, además del cero, que la lona TOQUE el muro: sin eso la prueba volvería a
# pasar sola el día que la vela abra un poco menos.
static func _popa_navegando(m: MarcoPruebas, arbol: SceneTree, mayor: Node) -> void:
	var previo := _guardar(arbol)
	var barco := UtilesPruebas.barco(arbol)
	await UtilesPruebas.al_timon(arbol)
	await UtilesPruebas.navegar(arbol, 13.0, (barco.global_transform.basis * Vector3(1, 0, 0)).normalized())
	await UtilesPruebas.estabilizar(arbol, 12.0,
		(barco.global_transform.basis * Vector3(-0.34, 0.0, -0.94)).normalized())
	var atravesadas := 0
	var cabos := {}
	var cerca := INF
	var dentro := 0
	for _k in 10:
		var c: Dictionary = await UtilesPruebas.jarcia_por_la_lona(arbol, barco, mayor)
		if int(c.get("cruces", 999)) > atravesadas:
			atravesadas = int(c.get("cruces", 999))
			cabos = c.get("por_cabo", {})
		var mu: Dictionary = await UtilesPruebas.lona_en_muros(arbol, barco, mayor)
		cerca = minf(cerca, float(mu.get("cerca", INF)))
		dentro = maxi(dentro, int(mu.get("dentro", 0)))
		for _f in 6:
			await arbol.physics_frame
	m.menor_que(cerca, 0.03, "tras navegar, en popa la mayor llega a apoyarse en el muro del obenque",
		"el punto más cercano a %.1f mm de su cara (%d dentro)" % [cerca * 1000.0, dentro])
	m.comprobar(atravesadas == 0, "y apoyada, ningún obenque atraviesa la mayor",
		"%d caras atravesadas %s, %d puntos dentro del muro" % [atravesadas, cabos, dentro])
	await _devolver(arbol, previo)


# --- LA BANDERA ES TELA DE SHADER, y por qué. La física no puede sostenerla: su gratil va
# cosido a 54,8 mm del eje del mástil, que ahí tiene 46 mm de radio — nueve milímetros de
# holgura para un paño de 960 mm. Al virar, el hueso lleva el gratil alrededor del palo, la
# lona va con retraso y acaba al otro lado; una vez envuelta no sale hasta parar el barco.
# Medido en un viraje a sotavento: de 0 puntos a menos de 100 mm del eje se pasaba a 19, con
# el más hondo a 4 mm —dentro de la madera—, y 5 s después seguían 10-11 pegados. Se
# descartaron midiendo el giro del hueso, la cápsula, el flameo, el empuje, todo el solver y
# la frecuencia de física; y una restricción dura que sacaba los puntos del palo la deshacía
# el solver, porque el enrollado es TOPOLÓGICO. Con el shader el giro es RÍGIDO y entero, así
# que no hay lona que pueda quedarse al otro lado: es imposible por construcción.
static func _bandera(m: MarcoPruebas, arbol: SceneTree) -> void:
	var ban := UtilesPruebas.barco(arbol).find_children("Bandera*", "", false, false)
	if not m.comprobar(ban.size() == 1, "el barco lleva una bandera", "%d nodos" % ban.size()):
		return
	var bd: Node = ban[0]
	m.comprobar(str(bd.get("nombre_malla")) == "bandera", "y anima la malla 'bandera'")

	# --- SI ES DE SHADER: aquí se comprueba la ORDEN, no el resultado. El desplazamiento del
	# paño ocurre en el vertex shader y GDScript no puede leer dónde acabó cada vértice, así
	# que no hay forma de medir el ondeo ni la costura como se hace con el paño físico. Lo
	# verificable es el ángulo que se le pasa. Es menos cobertura, y conviene tenerlo presente.
	if bd is TelaShader:
		var db: Dictionary = (bd as TelaShader).datos_bandera()
		if m.comprobar(not db.is_empty(), "el shader encontró la malla y la anima"):
			# La malla de autor tiene que quedar VISIBLE: `TelaFisica` la ocultaba para poner su
			# `SoftBody` en su lugar, y si algo la dejase oculta la bandera desaparecería sin más.
			m.comprobar((db["malla"] as MeshInstance3D).visible, "la malla queda visible")
			m.comprobar((db["malla"] as MeshInstance3D).material_override is ShaderMaterial,
				"y con el material del shader de tela encima")
			# El anclaje y el largo salen del canal verde de `Col`. Si no los encontrase, el
			# shader cae a su reserva (largo 0,3 y dirección +X) y la bandera giraría sobre un
			# punto que no es su driza — falla en silencio, así que se afirma el valor medido.
			# 0,69 y no los 0,96 que decía `BanderaFisica`: son dos definiciones distintas del
			# mismo paño. La física medía del centroide de las anclas al vértice MÁS LEJANO; el
			# shader mide al CENTROIDE del borde libre (verde alto y rojo > 0,7), que cae más acá.
			m.casi(float(db["largo"]), 0.69, 0.10, "y dedujo el largo de la bandera de `Col`")


# --- SI ES FÍSICA: lo que hay que comprobar es que NO SE ENROLLA en el mástil, que es lo
# que la sacó de la física en septiembre de 2026. Su gratil va cosido a 54,8 mm del eje del
# palo, que ahí tiene 46 mm de radio: nueve milímetros de holgura para un paño de 960 mm.
# Al virar, el hueso lleva el gratil alrededor del palo, la lona libre va con retraso y
# acaba al otro lado; una vez envuelta no sale hasta parar el barco, porque el conflicto es
# TOPOLÓGICO y ninguna fuerza lo deshace (una restricción dura que sacaba 7-9 puntos por
# paso la deshacía el solver). Medido entonces: de 0 puntos libres a menos de 100 mm del eje
# se pasaba a 19, el más hondo a 4 mm —dentro de la madera—, y 5 s después seguían 10-11.
#
# **Se vuelve a medir porque aquella cifra es de antes de arreglar el viento aparente**, y
# las dos investigaciones se solaparon. `Viento.velocidad_m_s` valía 8 con la balandra a 9,
# así que en popa el aparente cambiaba de signo y `orientar()` perseguía un objetivo que
# saltaba 180°: el hueso apenas se movía. Con eso dentro, el hueso no llegaba a barrer el
# gratil alrededor del palo de la forma que produce el enrollado, ni a no hacerlo — la
# medida no discriminaba. Si esto sale en 0, la bandera física vuelve a ser una opción.
#
# El viraje es de 170° y no de 90° a propósito: `virar()` no dice hacia qué banda gira, y
# un arco de 170° pasa por la popa venga de donde venga el viento. Un viraje corto podría
# no llegar a cruzar el paño de lado, que es cuando el enrollado ocurre.
#
# Con la bandera de shader no hay nada que medir aquí: el escenario no comprueba nada.
static func _bandera_enrollado(m: MarcoPruebas, arbol: SceneTree) -> void:
	var bd := _la_bandera(arbol)
	if not bd is BanderaFisica:
		return
	var previo := _guardar(arbol)
	await UtilesPruebas.al_timon(arbol)
	# De través, como salía antes de partir el paquete en escenarios: proa a −Z, viento a +X.
	UtilesPruebas.barco(arbol).global_rotation = Vector3.ZERO
	# Se mide la PENETRACIÓN, no la cercanía. El mástil tiene 46 mm de radio en la sección
	# de la bandera —lo imprime `perchas_solidas` al arrancar— y la relinga va cosida a
	# 54,8 mm del eje, así que los puntos libres pegados a ella rondan esa cifra SIEMPRE,
	# viren o no: con un cedazo de 100 mm salía 1 punto a 99 mm con el barco navegando en
	# línea recta. El cedazo de 100 mm sigue ahí porque es con el que se contaron los 19
	# puntos de septiembre y hace comparables las cifras, pero lo que falla es meterse en la
	# madera. Y el enrollado no era rozar: era llegar a 4 mm del eje y QUEDARSE.
	await UtilesPruebas.navegar(arbol, 6.0, Vector3(1, 0, 0))
	var antes: Dictionary = await UtilesPruebas.puntos_en_el_palo(arbol, bd)
	m.comprobar(float(antes["mas_cerca"]) > 0.046,
		"la bandera vuela por fuera del palo antes de virar", _dentro(antes))
	var giro: float = await UtilesPruebas.virar(arbol, 170.0, 30.0)
	if m.mayor_que(giro, 150.0, "el barco vira lo bastante para medir el enrollado"):
		var justo: Dictionary = await UtilesPruebas.puntos_en_el_palo(arbol, bd)
		m.comprobar(float(justo["mas_cerca"]) > 0.046,
			"y no se mete en el mástil al virar", _dentro(justo))
		# Y 5 s después sigue volando LARGA. Es la mitad que importa: una bandera enrollada se
		# ACORTA —el paño se queda pegado al palo— y eso el ángulo no lo ve, que un trapo
		# flojo puede estar perfectamente apuntado. De través vuela 0,59 m de sus 0,96, y en
		# popa 0,42 con `empuje_viento` a 35; enrollada se quedaba en 0,28 hasta fondear.
		await UtilesPruebas.navegar(arbol, 5.0, Vector3(1, 0, 0))
		var luego: Dictionary = await UtilesPruebas.puntos_en_el_palo(arbol, bd)
		m.comprobar(float(luego["mas_cerca"]) > 0.046,
			"ni se queda metida en él 5 s después", _dentro(luego))
		var vuelo: float = await UtilesPruebas.largo_del_vuelo(arbol, bd, 2.0)
		m.mayor_que(vuelo, 0.35, "y sigue volando larga, no pegada al palo")
	await _devolver(arbol, previo)


# --- Apunta a SOTAVENTO: al rolar el viento, la bandera lo sigue. Vale para las dos, que
# `direccion_de_vuelo()` lo tienen las dos y significa lo mismo: hacia dónde apunta la
# DRIZA, no el paño. Medir el paño no sirve — vuela al aparente aunque el hueso apunte mal.
static func _bandera_sotavento(m: MarcoPruebas, arbol: SceneTree) -> void:
	var bd := _la_bandera(arbol)
	if not m.comprobar(bd != null, "hay bandera para medir a sotavento"):
		return
	var previo := _guardar(arbol)
	await UtilesPruebas.estabilizar(arbol, 2.5, Vector3(1, 0, 0))
	var d1: Vector3 = bd.direccion_de_vuelo()
	# OJO: con el barco PARADO esta comprobación es casi tautológica —`direccion_de_vuelo()`
	# gira la dirección de reposo por el mismo ángulo que se calculó para apuntar al viento,
	# así que da 0,0° por construcción—. Vale para cazar un eje o un signo equivocados, no
	# más. La que discrimina de verdad es la del viento APARENTE, `bandera_aparente`:
	# comprobado volviendo al viento real, sale 28,6° y falla.
	m.menor_que(rad_to_deg(acos(clampf(d1.dot(Vector3(1, 0, 0)), -1.0, 1.0))), 20.0,
		"la bandera apunta a sotavento")
	await UtilesPruebas.estabilizar(arbol, 2.5, Vector3(-1, 0, 0))
	var d2: Vector3 = bd.direccion_de_vuelo()
	m.mayor_que(rad_to_deg(acos(clampf(d1.dot(d2), -1.0, 1.0))), 120.0,
		"y da la vuelta cuando el viento rola 180°")
	await _devolver(arbol, previo)


# --- Y NAVEGANDO va al viento APARENTE, no al real. Con el barco a 9 m/s y el viento de
# través hay hasta 50° entre uno y otro; con el real, la driza apunta a un sitio y la
# tela vuela a otro. `Viento.velocidad_m_s` tiene que superar la máxima del barco o el
# aparente cambia de signo en popa — esa es la prueba de abajo, y es el fallo que se veía
# como "la bandera no rola": con 8 m/s contra los 9 del barco, y las ráfagas moviendo
# `fuerza * 8` entre 4,4 y 11,6, el objetivo saltaba 180° varias veces por segundo y el
# hueso se quedaba temblando cerca del reposo mientras el paño volaba bien.
static func _bandera_aparente(m: MarcoPruebas, arbol: SceneTree) -> void:
	var bd := _la_bandera(arbol)
	if not m.comprobar(bd != null, "hay bandera para medir el viento aparente"):
		return
	var previo := _guardar(arbol)
	await UtilesPruebas.al_timon(arbol)
	var b3 := UtilesPruebas.barco(arbol) as CharacterBody3D
	m.mayor_que(Viento.velocidad_m_s, b3.velocidad_max,
		"el viento sopla más rápido de lo que puede correr el barco")
	# El rumbo se FIJA aquí, de través (proa a −Z, viento hacia +X), en vez de heredar el que
	# dejen los paquetes anteriores: con la inercia de guiñada el barco llegaba aproado, a 44°
	# del ojo y ciando (0,23 m/s), y sin nadie al timón un velero aproado no sale. Con la guiñada
	# instantánea llegaba con otro rumbo solo por casualidad.
	(b3 as Node3D).global_rotation = Vector3.ZERO
	var vel := await UtilesPruebas.navegar(arbol, 6.0, Vector3(1, 0, 0))
	# El listón va en FRACCIÓN de lo que el casco puede dar, no en metros por segundo: un
	# número absoluto se
	# pone rojo el día que se toque `velocidad_max` sin que la tela tenga nada que ver. Pasó
	# al bajarla de 9 a 4,5 m/s, que es la velocidad de casco real de esta balandra.
	if m.mayor_que(vel, b3.velocidad_max * 0.3,
			"el barco navega para poder medir el viento aparente"):
		var ap := Viento.aparente(b3.velocity)
		ap.y = 0.0
		var d3: Vector3 = bd.direccion_de_vuelo()
		m.menor_que(rad_to_deg(acos(clampf(d3.dot(ap.normalized()), -1.0, 1.0))), 20.0,
			"la bandera apunta al viento aparente, no al real")
	await _devolver(arbol, previo)


# --- NAVEGANDO, la costura entre lo anclado y lo libre no se abre. Es la medida que faltaba:
# todo lo demás se comprobaba con el barco ANCLADO, y este defecto solo salía con el barco en
# marcha.
#
# **Su causa estuvo mal entendida hasta el 10 de septiembre de 2026.** Se creía que el paño
# libre iba un paso de física por detrás de sus anclas y que solo dependía del tamaño del
# paso, porque al barrer la frecuencia salía 60 Hz -> 108 mm, 120 -> 51, 240 -> 13; y el
# proyecto se puso a 120 Hz por eso. Pero lo que se estaba barriendo no era el paso: era
# cuántos pasos caben en un frame. Quien se quedaba atrás no era el paño libre, eran los
# puntos ANCLADOS, porque `SoftBody3D` solo los lleva a donde dice su nodo una vez por frame
# de render. Empujándolos al servidor en cada paso (`TelaFisica._colocar_anclas`), la costura
# de la mayor cae de 0,028 m a 0,002 y deja de depender de los fps.
#
# El tope baja de 0,075 a 0,010 a la vez que el arreglo: con 0,075 sobre 0,002 medidos ya no
# guardaba nada. Sigue habiendo 5 veces de margen.
static func _costura(m: MarcoPruebas, arbol: SceneTree, mayor: Node) -> void:
	var previo := _guardar(arbol)
	await _de_traves(arbol)
	var cos_may: Dictionary = await UtilesPruebas.costura(arbol, mayor, 1.5)
	m.menor_que(cos_may["medio"], 0.010, "la costura de la mayor aguanta navegando")
	await _devolver(arbol, previo)


# --- Los ANCLAJES no se retrasan del barco. Un punto anclado está clavado a un `Node3D`
# hijo del `Skeleton3D`, que viaja rígido con el casco: su separación tiene que ser cero
# navegando igual que fondeado. Se veía en el visor como la columna de anclajes de la bandera
# estirándose hacia popa en cuanto el barco arrancaba, y volviendo a su sitio al parar.
#
# **Con los FPS fijos, o no discrimina**: el desfase sale de que las anclas se recolocan una
# vez por FRAME mientras la física da varios pasos entre frame y frame, así que si el frame
# dura lo mismo que el paso —vsync a 120 Hz con la física a 120— hay un paso por frame y sale
# 0,0 mm con el defecto dentro. Medido en `tools/retraso_anclas.tscn`, a 8,74 m/s: 30 fps da
# 218 mm de peor, 60 fps da 73, sin tope da 0. Y peor = (pasos por frame - 1) x paso x
# velocidad, clavado a tres cifras, que es lo que identifica la causa.
static func _anclas(m: MarcoPruebas, arbol: SceneTree, por_nombre: Dictionary) -> void:
	var previo := _guardar(arbol)
	await _de_traves(arbol)
	for nombre in por_nombre:
		var ret: Dictionary = await UtilesPruebas.retraso_anclas(arbol, por_nombre[nombre], 60)
		m.menor_que(ret["peor"], 0.010,
			"los anclajes de '%s' no se quedan atrás navegando" % nombre)
	await _devolver(arbol, previo)


# --- La mayor DESVENTADA flamea, no da un latido. En fachada la lona pegaba un chasquido
# entero cada ~6,4 s —medio ciclo del bamboleo de dirección del viento, justo donde la percha
# gira más rápido— con el pico a 4,0 veces la mediana; navegando portando, el mismo pico es
# 2,2 y no es periódico. La causa no era el trimado, ni las cápsulas, ni el bamboleo del
# casco: un campo de viento uniforme no hace flamear a nada. Con `flameo_por_desventa`: 1,8.
#
# El viento se pone soplando HACIA la proa (`basis.z`, porque la proa mira a -Z), que es lo
# que deja al barco en fachada; con el viento de popa esto no se puede medir.
static func _flameo(m: MarcoPruebas, arbol: SceneTree, mayor: Node) -> void:
	var previo := _guardar(arbol)
	await UtilesPruebas.al_timon(arbol)
	var b4 := UtilesPruebas.barco(arbol) as CharacterBody3D
	await UtilesPruebas.navegar(arbol, 6.0, b4.global_transform.basis.z)
	if m.menor_que(b4.factor_viento(), 0.05, "el barco está en fachada para medir el flameo"):
		# **INTERMITENTE, y sin resolver (10 de septiembre de 2026).** A 120 Hz esta medida sale
		# BIMODAL —1,76 / 1,88 contra 2,61 / 2,62— con el tope en 2,50, así que la suite se pone
		# roja una de cada tres veces. No es ruido: son dos valores separados, no una nube.
		#
		# Lo que se sabe: a 60 Hz NO pasa (1,93 / 1,86 / 1,96 en tres pasadas seguidas). Y subir
		# la ventana de 12 a 20 s no ayuda —sale 2,615—, lo cual tiene sentido y contradice la
		# regla general de la cabecera de este fichero: esta cifra es un MÁXIMO partido por una
		# mediana, y alargar la ventana solo puede subir el máximo. Para robustecerla habría que
		# cambiar el máximo por un percentil alto, no ampliar la ventana.
		#
		# Lo que NO se sabe: si es de hoy. Apareció trabajando en el empuje de anclajes por paso,
		# que quita el tirón por frame y por tanto baja el movimiento de FONDO del paño — con la
		# mediana más baja, el mismo pico destaca más—, pero no se ha medido contra el estado
		# anterior. No tocar el tope para taparlo.
		var relieve := await UtilesPruebas.relieve_del_pico(arbol, mayor, 12.0)
		m.menor_que(relieve, 2.5, "la mayor desventada flamea en vez de dar un latido")
	await _devolver(arbol, previo)


# ── Preparación ──────────────────────────────────────────────────────────────

## Navegando de través —proa a −Z, viento a +X— el tiempo justo para coger su velocidad. Es
## donde se miden la costura y las anclas, porque el defecto que buscan solo sale en marcha.
static func _de_traves(arbol: SceneTree) -> void:
	await UtilesPruebas.al_timon(arbol)
	UtilesPruebas.barco(arbol).global_rotation = Vector3.ZERO
	await UtilesPruebas.navegar(arbol, 6.0, Vector3(1, 0, 0))


static func _la_bandera(arbol: SceneTree) -> Node:
	var ban := UtilesPruebas.barco(arbol).find_children("Bandera*", "", false, false)
	return ban[0] if ban.size() == 1 else null


## El ancla con que el escenario encontró el barco. El RUMBO no se devuelve a propósito: girar
## el casco de golpe arrastra metros las anclas de las velas en un solo paso, y cada escenario
## que necesita un rumbo ya lo fija él. Tampoco el viento: lo dejaban fijado (sin ráfagas ni
## bamboleo) ya antes de partir el paquete, y `ia` y `mundo` corren así desde siempre.
static func _guardar(arbol: SceneTree) -> Dictionary:
	return {"anclado": bool(UtilesPruebas.barco(arbol).get("anclado"))}


static func _devolver(arbol: SceneTree, previo: Dictionary) -> void:
	UtilesPruebas.barco(arbol).set("anclado", previo["anclado"])
	await arbol.physics_frame


## Detalle legible de una medida de `puntos_en_el_palo()`, para el informe de la prueba.
static func _dentro(d: Dictionary) -> String:
	var n := int(d["puntos"])
	if n == 0:
		return "0 puntos dentro"
	return "%d puntos dentro, el más hondo a %.0f mm del eje" % [n, float(d["mas_cerca"]) * 1000.0]
