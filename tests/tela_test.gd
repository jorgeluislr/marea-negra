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
	# DOS paños físicos, no tres: la bandera pasó a tela de shader el 9 de septiembre de 2026
	# (ver el bloque de la bandera, abajo, para el porqué medido).
	var telas := UtilesPruebas.telas(arbol)
	if not m.comprobar(telas.size() == 2, "la balandra monta sus dos velas físicas",
			"%d" % telas.size()):
		return

	var por_nombre := {}
	for t in telas:
		por_nombre[str(t.get("nombre_malla"))] = t
	# La BANDERA no está aquí: es tela de SHADER desde el 9 de septiembre de 2026 y no expone
	# `datos_depuracion()`. Se comprueba más abajo, con lo único que de ella se puede comprobar.
	m.comprobar(por_nombre.has("foque") and por_nombre.has("vela_mayor"),
		"están el foque y la mayor como paños físicos", ", ".join(por_nombre.keys()))
	m.comprobar(por_nombre.get("vela_mayor") is VelaFisica, "la mayor es una VelaFisica")
	m.comprobar(not por_nombre.has("bandera"),
		"la bandera NO es un paño físico (no puede haber dos telas del mismo paño)")

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
	var topes := {"foque": [0.02, 0], "vela_mayor": [0.02, 0]}
	for nombre in topes:
		var e: Dictionary = await UtilesPruebas.estiramiento(arbol, por_nombre[nombre])
		m.menor_que(e["medio"], topes[nombre][0], "'%s' no nace estirado" % nombre)
		m.comprobar(e["malas"] <= topes[nombre][1],
			"'%s': ninguna arista pasada de vueltas" % nombre,
			"%d por encima del 25 %%" % e["malas"])

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
	var ban := UtilesPruebas.barco(arbol).find_children("BanderaShader", "", true, false)
	if m.comprobar(ban.size() == 1 and ban[0] is TelaShader,
			"la bandera es tela de shader (`TelaShader`)"):
		var bs: TelaShader = ban[0]
		m.comprobar(str(bs.get("nombre_malla")) == "bandera", "y anima la malla 'bandera'")
		var db: Dictionary = bs.datos_bandera()
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
			# shader mide al CENTROIDE del borde libre (verde alto y rojo > 0,7), que cae más
			# acá. Lo que importa es que no sea la reserva del shader —0,3 y dirección +X—,
			# porque entonces la bandera giraría sobre un punto que no es su driza.
			m.casi(float(db["largo"]), 0.69, 0.10, "y dedujo el largo de la bandera de `Col`")

		# --- Apunta a SOTAVENTO: al rolar el viento, la bandera lo sigue.
		await UtilesPruebas.estabilizar(arbol, 2.5, Vector3(1, 0, 0))
		var d1: Vector3 = bs.direccion_de_vuelo()
		# OJO: con el barco PARADO esta comprobación es casi tautológica —`direccion_de_vuelo()`
		# gira la dirección de reposo por el mismo ángulo que se calculó para apuntar al viento,
		# así que da 0,0° por construcción—. Vale para cazar un eje o un signo equivocados, no
		# más. La que discrimina de verdad es la del viento APARENTE, más abajo: comprobado
		# volviendo al viento real, sale 28,6° y falla.
		m.menor_que(rad_to_deg(acos(clampf(d1.dot(Vector3(1, 0, 0)), -1.0, 1.0))), 20.0,
			"la bandera apunta a sotavento")
		await UtilesPruebas.estabilizar(arbol, 2.5, Vector3(-1, 0, 0))
		var d2: Vector3 = bs.direccion_de_vuelo()
		m.mayor_que(rad_to_deg(acos(clampf(d1.dot(d2), -1.0, 1.0))), 120.0,
			"y da la vuelta cuando el viento rola 180°")

		# --- Y NAVEGANDO va al viento APARENTE, no al real. Con el barco a 9 m/s y el viento de
		# través hay hasta 50° entre uno y otro; con el real, la driza apunta a un sitio y la
		# tela vuela a otro. `Viento.velocidad_m_s` tiene que superar la máxima del barco o el
		# aparente cambia de signo en popa — esa es la prueba de abajo.
		var b3 := UtilesPruebas.barco(arbol) as CharacterBody3D
		m.mayor_que(Viento.velocidad_m_s, b3.velocidad_max,
			"el viento sopla más rápido de lo que puede correr el barco")
		var vel := await UtilesPruebas.navegar(arbol, 6.0, Vector3(1, 0, 0))
		if m.mayor_que(vel, 3.0, "el barco navega para poder medir el viento aparente"):
			var ap := Viento.aparente(b3.velocity)
			ap.y = 0.0
			var d3: Vector3 = bs.direccion_de_vuelo()
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
	# todo lo demás se comprobaba con el barco ANCLADO, y este defecto solo sale con el barco en
	# marcha. El paño libre va exactamente UN PASO DE FÍSICA por detrás de sus anclas, que van
	# clavadas al esqueleto: a 8,7 m/s eso son 145 mm por paso.
	#
	# No depende de NADA del solver (rigidez 0,3-0,95, precisión 10-30, masa 0,6-0,1, arrastre
	# 0,3-0,05 dieron todos lo mismo) ni del viento (sin viento se abre MÁS): depende solo del
	# tamaño del paso. Medido en la bandera cuando era física: 60 Hz → 108 mm, 120 Hz → 51,
	# 240 Hz → 13. El proyecto va a 120 por esto.
	#
	# Se mide en la MAYOR, que es la que sigue siendo física. Era un defecto conocido de ella
	# desde septiembre —"el paño va un paso de física por detrás del barco"— y no tenía prueba.
	await UtilesPruebas.navegar(arbol, 6.0, Vector3(1, 0, 0))
	var cos_may: Dictionary = await UtilesPruebas.costura(arbol, por_nombre["vela_mayor"], 1.5)
	m.menor_que(cos_may["medio"], 0.075, "la costura de la mayor aguanta navegando")

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
		var relieve := await UtilesPruebas.relieve_del_pico(arbol, mayor, 12.0)
		m.menor_que(relieve, 2.5, "la mayor desventada flamea en vez de dar un latido")
