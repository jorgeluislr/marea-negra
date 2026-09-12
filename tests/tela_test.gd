class_name TelaTest
extends RefCounted

## Paquete `tela`: el soldado, los anclajes, la recogida y —sobre todo— que el paño no nazca
## estirado. Los umbrales de abajo salen de medidas reales, no de números redondos; están
## holgados respecto a lo medido para que la prueba no chille por una ráfaga.


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

	# --- El paño NO nace estirado. Es lo que rompía el arranque: un frame largo del arranque
	# hacía caer la tela varios pasos de física con los anclajes congelados, y el solver ya no
	# cerraba esas aristas. Medido tras el arreglo: 0 aristas por encima del 25 % en las velas.
	# La bandera lleva un tope más ancho porque tiene UNA sola columna de anclajes (11, la que
	# roza el mástil): con dos, la segunda sujetaba paño que debe volar. Estuvo en rojo el 8 de
	# septiembre de 2026, con ~30 aristas pasadas, y la causa era la cápsula del mástil,
	# que se llevaba sus 11 anclajes 53 mm dentro. Ver `perchas_solidas.gd`.
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

	# --- Y la garantía que lo evita: el paño no se monta en un frame largo. Se comprueba la
	# condición, no el síntoma: que salga bien un día concreto depende de si el frame en que
	# nació fue corto por casualidad.
	for nombre in ["foque", "vela_mayor"]:
		var dd: Dictionary = por_nombre[nombre].datos_depuracion()
		var dm: float = dd.get("delta_montaje", 1.0)
		var tope: float = float(por_nombre[nombre].get("delta_estable"))
		m.comprobar(dm <= tope or dd.get("espera_montaje", 0.0) >= float(por_nombre[nombre].get("espera_max")),
			"'%s' nace con el reloj fino, no en un tirón" % nombre, "frame de %.3f s" % dm)

	# --- Arriar recoge el paño (y con ello el viento deja de afectarle); izar lo suelta.
	var mayor: Node = por_nombre["vela_mayor"]
	await UtilesPruebas.tecla(arbol, KEY_S)
	for i in 400:
		await arbol.process_frame
	var apa: Variant = mayor.get("aparejo")
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

	# --- Cada vela tiene SU aparejo. Un sub-recurso de escena se comparte entre instancias, y
	# si se comparte, dos velas del mismo barco se izarían a la vez.
	var foque: Node = por_nombre["foque"]
	m.comprobar(foque.get("aparejo") != mayor.get("aparejo"),
		"foque y mayor no comparten aparejo")

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
	#
	# **Aquí se comprueba la ORDEN, no el resultado.** El desplazamiento del paño ocurre en el
	# vertex shader y GDScript no puede leer dónde acabó cada vértice, así que no hay forma de
	# medir el ondeo ni la costura como se hacía con el paño físico. Lo verificable es el ángulo
	# que se le pasa. Es menos cobertura, y conviene tenerlo presente.
	var ban := UtilesPruebas.barco(arbol).find_children("Bandera*", "", false, false)
	if m.comprobar(ban.size() == 1, "el barco lleva una bandera", "%d nodos" % ban.size()):
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
		if bd is BanderaFisica:
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

		# --- Apunta a SOTAVENTO: al rolar el viento, la bandera lo sigue. Vale para las dos, que
		# `direccion_de_vuelo()` lo tienen las dos y significa lo mismo: hacia dónde apunta la
		# DRIZA, no el paño. Medir el paño no sirve — vuela al aparente aunque el hueso apunte mal.
		await UtilesPruebas.estabilizar(arbol, 2.5, Vector3(1, 0, 0))
		var d1: Vector3 = bd.direccion_de_vuelo()
		# OJO: con el barco PARADO esta comprobación es casi tautológica —`direccion_de_vuelo()`
		# gira la dirección de reposo por el mismo ángulo que se calculó para apuntar al viento,
		# así que da 0,0° por construcción—. Vale para cazar un eje o un signo equivocados, no
		# más. La que discrimina de verdad es la del viento APARENTE, más abajo: comprobado
		# volviendo al viento real, sale 28,6° y falla.
		m.menor_que(rad_to_deg(acos(clampf(d1.dot(Vector3(1, 0, 0)), -1.0, 1.0))), 20.0,
			"la bandera apunta a sotavento")
		await UtilesPruebas.estabilizar(arbol, 2.5, Vector3(-1, 0, 0))
		var d2: Vector3 = bd.direccion_de_vuelo()
		m.mayor_que(rad_to_deg(acos(clampf(d1.dot(d2), -1.0, 1.0))), 120.0,
			"y da la vuelta cuando el viento rola 180°")

		# --- Y NAVEGANDO va al viento APARENTE, no al real. Con el barco a 9 m/s y el viento de
		# través hay hasta 50° entre uno y otro; con el real, la driza apunta a un sitio y la
		# tela vuela a otro. `Viento.velocidad_m_s` tiene que superar la máxima del barco o el
		# aparente cambia de signo en popa — esa es la prueba de abajo, y es el fallo que se veía
		# como "la bandera no rola": con 8 m/s contra los 9 del barco, y las ráfagas moviendo
		# `fuerza * 8` entre 4,4 y 11,6, el objetivo saltaba 180° varias veces por segundo y el
		# hueso se quedaba temblando cerca del reposo mientras el paño volaba bien.
		var b3 := UtilesPruebas.barco(arbol) as CharacterBody3D
		m.mayor_que(Viento.velocidad_m_s, b3.velocidad_max,
			"el viento sopla más rápido de lo que puede correr el barco")
		var vel := await UtilesPruebas.navegar(arbol, 6.0, Vector3(1, 0, 0))
		if m.mayor_que(vel, 3.0, "el barco navega para poder medir el viento aparente"):
			var ap := Viento.aparente(b3.velocity)
			ap.y = 0.0
			var d3: Vector3 = bd.direccion_de_vuelo()
			m.menor_que(rad_to_deg(acos(clampf(d3.dot(ap.normalized()), -1.0, 1.0))), 20.0,
				"la bandera apunta al viento aparente, no al real")

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
	await UtilesPruebas.navegar(arbol, 6.0, Vector3(1, 0, 0))
	var cos_may: Dictionary = await UtilesPruebas.costura(arbol, por_nombre["vela_mayor"], 1.5)
	m.menor_que(cos_may["medio"], 0.010, "la costura de la mayor aguanta navegando")

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
	await UtilesPruebas.navegar(arbol, 6.0, Vector3(1, 0, 0))
	for nombre in por_nombre:
		var ret: Dictionary = await UtilesPruebas.retraso_anclas(arbol, por_nombre[nombre], 60)
		m.menor_que(ret["peor"], 0.010,
			"los anclajes de '%s' no se quedan atrás navegando" % nombre)

	# --- La mayor DESVENTADA flamea, no da un latido. En fachada la lona pegaba un chasquido
	# entero cada ~6,4 s —medio ciclo del bamboleo de dirección del viento, justo donde la percha
	# gira más rápido— con el pico a 4,0 veces la mediana; navegando portando, el mismo pico es
	# 2,2 y no es periódico. La causa no era el trimado, ni las cápsulas, ni el bamboleo del
	# casco: un campo de viento uniforme no hace flamear a nada. Con `flameo_por_desventa`: 1,8.
	#
	# El viento se pone soplando HACIA la proa (`basis.z`, porque la proa mira a -Z), que es lo
	# que deja al barco en fachada; con el viento de popa esto no se puede medir.
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


## Detalle legible de una medida de `puntos_en_el_palo()`, para el informe de la prueba.
static func _dentro(d: Dictionary) -> String:
	var n := int(d["puntos"])
	if n == 0:
		return "0 puntos dentro"
	return "%d puntos dentro, el más hondo a %.0f mm del eje" % [n, float(d["mas_cerca"]) * 1000.0]
