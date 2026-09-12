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
const T_MANDO := 4.0
const T_CENIDA := 40.0
const T_COMBATE := 45.0


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("ia")
	var mio := UtilesPruebas.barco(arbol)
	if not m.comprobar(mio != null, "hay un barco del jugador"):
		return

	await _mando_no_compartido(m, arbol, mio)
	await _cine_a_barlovento(m, arbol, mio)
	await _presenta_la_banda(m, arbol, mio)


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

	var rumbo_mio := mio.global_rotation.y
	var rumbo_suyo := enemigo.global_rotation.y
	# Timón a tope, dado como ORDEN y no como tecla: es lo que hace la IA.
	for i in int(T_MANDO * 60.0):
		enemigo.set("orden_timon", 1.0)
		enemigo.set("anclado", false)
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
## Se miden DOS cosas y hacen falta las dos: que se acerque (si no, no sirve de nada) y que
## nunca se quede parado de proa al viento (`factor_viento` casi cero). Sólo la primera dejaría
## pasar un capitán que llega de milagro tras quedarse clavado medio minuto; sólo la segunda,
## uno que navega precioso hacia ninguna parte.
static func _cine_a_barlovento(m: MarcoPruebas, arbol: SceneTree, mio: Node3D) -> void:
	_viento(Vector3(1, 0, 0))
	# El jugador queda a barlovento del enemigo: el viento sopla hacia +X, así que barlovento es
	# −X. El enemigo tendrá que ceñir para llegar hasta él.
	var enemigo := await _soltar_enemigo(arbol, mio, 0.0)
	if enemigo == null:
		return
	enemigo.global_position = mio.global_position + Vector3(300.0, 0.0, 0.0)
	mio.set("anclado", true)

	var d0: float = enemigo.global_position.distance_to(mio.global_position)
	var parado := 0.0
	var pasos := int(T_CENIDA * 60.0)
	for i in pasos:
		_viento(Vector3(1, 0, 0))
		enemigo.set("anclado", false)
		if float(enemigo.call("factor_viento")) < 0.05:
			parado += arbol.root.get_process_delta_time()
		await arbol.process_frame
	var d1: float = enemigo.global_position.distance_to(mio.global_position)

	m.menor_que(d1, d0 - 80.0, "ciñendo, el enemigo se acerca al barco de barlovento")
	m.menor_que(parado, T_CENIDA * 0.25, "no se queda de proa al viento",
		"%.1f s de %.0f" % [parado, T_CENIDA])
	var cap := enemigo.get_node_or_null(^"Capitan")
	if cap != null:
		m.mayor_que(float(int(cap.call("viradas"))), 0.0, "ha dado al menos una virada")
	_retirar(enemigo)


# ── 3. Presenta la banda antes de disparar ───────────────────────────────────
## Los cañones son fijos al costado, así que la única puntería posible es el rumbo del barco. Se
## anota el ángulo proa-enemigo en el INSTANTE de cada disparo, enganchándose a la señal de cada
## pieza: mirarlo después no vale, porque el barco sigue girando.
static func _presenta_la_banda(m: MarcoPruebas, arbol: SceneTree, mio: Node3D) -> void:
	_viento(Vector3(0, 0, 1))
	var enemigo := await _soltar_enemigo(arbol, mio, 180.0)
	if enemigo == null:
		return
	mio.set("anclado", true)

	var angulos: Array[float] = []
	for n in enemigo.find_children("*", "", true, false):
		if n.has_method("disparar") and n.has_signal("disparo"):
			n.connect("disparo", func(_d: Vector3, _h: Vector3):
				angulos.append(_angulo_al_blanco(enemigo, mio)))

	for i in int(T_COMBATE * 60.0):
		_viento(Vector3(0, 0, 1))
		enemigo.set("anclado", false)
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
