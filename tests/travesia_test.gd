class_name TravesiaTest
extends RefCounted

## Paquete `travesia`: la navegación rápida con la T (×1 → ×2 → ×4 → ×1).
##
## Es `Engine.time_scale` con la física a 60·N Hz, para que el paso siga siendo 1/60 s de juego:
## todo va N veces más deprisa —barco, mar, telas, calendario— y nada se simula con pasos más
## largos. Medido con `tools/coste_tiempo.tscn` antes de escribir nada: con el paso alargado las
## telas se estiran desde ×2 (48 aristas por encima del 25 %, y 420 y 30 cm a ×8); con el paso
## fino aguantan, y el techo de esta máquina está en ~460 pasos por segundo (×7,7), así que el
## modo no pasa de ×4. Decidido con el usuario el 18-10-2026.
##
## Se maneja con la T de verdad y se mira lo que pasa en el MOTOR (`time_scale`, los pasos de
## física, la distancia recorrida, la fecha), no una variable del modo. No nombra la clase del
## modo: lo busca por su nombre de nodo, para que el paquete compile aunque no exista y el fallo
## salga como fallo.
##
## Partido en escenarios (`-- travesia/distancia`); cada uno se prepara solo y deja el tiempo a ×1.

const T := KEY_T


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("travesia")
	var b := UtilesPruebas.barco(arbol)
	if not m.comprobar(b != null, "hay un barco en el grupo 'barco_activo'"):
		return
	if m.escenario("tecla"):
		await _tecla(m, arbol, b)
	if m.escenario("distancia"):
		await _distancia(m, arbol, b)
	if m.escenario("telas"):
		await _telas(m, arbol, b)
	if m.escenario("maniobra"):
		await _maniobra(m, arbol, b)
	if m.escenario("tiempo"):
		await _tiempo(m, arbol, b)
	if m.escenario("enemigo"):
		await _enemigo(m, arbol, b)
	if m.escenario("tierra"):
		await _tierra(m, arbol, b)
	if m.escenario("hud"):
		await _hud(m, arbol, b)
	await _a_uno(arbol)


# ── Preparación ──────────────────────────────────────────────────────────────

## Al timón, navegando de través con viento fijo y a ×1.
static func _preparar(arbol: SceneTree, b: Node3D) -> void:
	await _a_uno(arbol)
	await UtilesPruebas.al_timon(arbol)
	_viento(Vector3(1, 0, 0))
	b.set("anclado", false)
	if not bool(b.get("vela_delantera")):
		b.call("set_vela_delantera", true)
	if not bool(b.get("vela_trasera")):
		b.call("set_vela_trasera", true)
	b.set("modo_battle", false)
	await UtilesPruebas.navegar(arbol, 2.0, Vector3(1, 0, 0))


static func _viento(dir: Vector3) -> void:
	Viento.direccion_base = dir
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	Viento.fuerza_base = 1.0


## Vuelve a ×1 a las malas, por si un escenario falló a medias. No usa la tecla: es limpieza.
static func _a_uno(arbol: SceneTree) -> void:
	var tr := _travesia(UtilesPruebas.barco(arbol))
	if tr != null and tr.has_method("poner"):
		tr.call("poner", 1)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	await arbol.process_frame


static func _travesia(b: Node) -> Node:
	return b.get_node_or_null("MandoJugador/Travesia") if b != null else null


static func _motivo(b: Node) -> String:
	var tr := _travesia(b)
	return String(tr.get("motivo")) if tr != null else ""


## Espera `seg` segundos REALES, que con el tiempo acelerado no son los del juego.
static func _real(arbol: SceneTree, seg: float) -> void:
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < int(seg * 1e6):
		await arbol.process_frame


static func _a() -> String:
	return "time_scale %.2f, física %d Hz" % [Engine.time_scale, Engine.physics_ticks_per_second]


# ── Escenarios ───────────────────────────────────────────────────────────────

## La T recorre ×1 → ×2 → ×4 → ×1, y la física sube con ella para que el paso no cambie.
static func _tecla(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	await _preparar(arbol, b)
	m.comprobar(_travesia(b) != null, "el mando del jugador lleva la navegación rápida")
	for n in [2, 4, 1]:
		await UtilesPruebas.tecla(arbol, T)
		m.casi(Engine.time_scale, float(n), 0.001, "la T pone el tiempo a ×%d" % n, _a())
		m.comprobar(Engine.physics_ticks_per_second == 60 * n,
			"y la física a %d Hz, para que el paso siga en 1/60 s de juego" % (60 * n), _a())
	await _real(arbol, 0.3)
	await arbol.physics_frame
	m.casi(b.get_physics_process_delta_time(), 1.0 / 60.0, 0.0005,
		"de vuelta a ×1 el paso de física es 1/60 s", "%.5f" % b.get_physics_process_delta_time())


## A ×4 el barco recorre cuatro veces la distancia en el mismo tiempo REAL, y el calendario corre
## cuatro veces más: la fecha y el viento que sale de ella van con el barco.
static func _distancia(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	# El casco tarda en coger su arrancada (0,29 m/s², ver `casco-con-masa`): con 8 s a ×1 aún
	# acelera, y la ventana a ×4, que abarca cuatro veces más tiempo de juego, la pilla más rápido
	# — medido, 5,0 veces la distancia en vez de 4 con el tiempo de juego exacto a ×4,00. Así que
	# se calienta A ×4 (40 s de juego), se mide a ×4 y LUEGO a ×1, ya en régimen.
	await _preparar(arbol, b)
	await UtilesPruebas.tecla(arbol, T)
	await UtilesPruebas.tecla(arbol, T)
	await _real(arbol, 10.0)
	var r4 := await _recorrido(arbol, b, 3.0)
	await UtilesPruebas.tecla(arbol, T)
	await _real(arbol, 0.5)
	var r1 := await _recorrido(arbol, b, 3.0)
	await _a_uno(arbol)
	var det := "×1: %.2f m/s y %.3f días/s; ×4: %.2f m/s y %.3f días/s" \
		% [r1.x, r1.y * 1000.0, r4.x, r4.y * 1000.0]
	m.mayor_que(r1.x, 1.0, "a ×1 el barco navega (m/s reales)", det)
	m.casi(r4.x / maxf(r1.x, 0.01), 4.0, 0.6, "a ×4 recorre 4 veces la distancia por segundo real",
		det)
	m.casi(r4.y / maxf(r1.y, 1e-9), 4.0, 0.3, "y el calendario avanza 4 veces más", det)
	m.casi(r4.z, 4.0, 0.3, "el juego corre a ×4 sin perder pasos (s de juego por s real)",
		"%.2f" % r4.z)


## (m/s reales en absoluto, días de calendario por s real, s de juego por s real).
static func _recorrido(arbol: SceneTree, b: Node3D, seg: float) -> Vector3:
	var p0 := Origen.a_global(b.global_position)
	var c0: float = Calendario.instante
	var j0: float = float(b.get("time"))
	var t0 := Time.get_ticks_usec()
	await _real(arbol, seg)
	var dt := (Time.get_ticks_usec() - t0) / 1e6
	var p1 := Origen.a_global(b.global_position)
	return Vector3(Vector2(p1.x - p0.x, p1.z - p0.z).length() / dt,
		(Calendario.instante - c0) / dt, (float(b.get("time")) - j0) / dt)


## Las telas navegando a ×4 no se estiran más que a ×1: el mismo tope en metros que vigila el
## paquete `tela` (30 mm, el que de verdad guarda de un desgarro).
static func _telas(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	await _preparar(arbol, b)
	await UtilesPruebas.tecla(arbol, T)
	await UtilesPruebas.tecla(arbol, T)
	var peor := {}
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 6_000_000:
		for tela in UtilesPruebas.telas(arbol):
			var e: Dictionary = await UtilesPruebas.estiramiento(arbol, tela)
			if e.is_empty():
				continue
			var nombre := String(tela.datos_depuracion()["nombre"])
			peor[nombre] = maxf(float(peor.get(nombre, 0.0)), float(e["peor_m"]))
		await _real(arbol, 0.2)
	var escala := Engine.time_scale
	await _a_uno(arbol)
	m.casi(escala, 4.0, 0.001, "las telas se miden a ×4")
	m.comprobar(not peor.is_empty(), "hay telas que medir")
	for nombre in peor:
		m.menor_que(float(peor[nombre]), 0.030,
			"'%s' a ×4 no se estira más de 30 mm" % nombre, "%.4f m" % float(peor[nombre]))


## Anclar, el modo batalla, bajar a cubierta, la carta y arriar las dos velas cortan el modo; y
## con cualquiera de ellos puesto la T no lo enciende.
static func _maniobra(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	var casos := [
		["el ancla", KEY_SPACE, "ancla"],
		["el modo batalla", KEY_B, "batalla"],
		["bajar a cubierta", KEY_F, "cubierta"],
		["abrir la carta", KEY_M, "carta"],
	]
	for c in casos:
		await _preparar(arbol, b)
		await UtilesPruebas.tecla(arbol, T)
		await UtilesPruebas.tecla(arbol, T)
		await UtilesPruebas.tecla(arbol, c[1])
		await _real(arbol, 0.6)
		m.casi(Engine.time_scale, 1.0, 0.001, "%s corta la navegación rápida" % c[0], _a())
		m.comprobar(_motivo(b).contains(c[2]), "y dice por qué", _motivo(b))
		await UtilesPruebas.tecla(arbol, T)
		await _real(arbol, 0.3)
		m.casi(Engine.time_scale, 1.0, 0.001, "con %s puesto la T no la enciende" % c[0], _a())
		await UtilesPruebas.tecla(arbol, c[1])   # deshacer
		await _real(arbol, 0.3)
	# Las dos velas arriadas: una sola no corta.
	await _preparar(arbol, b)
	await UtilesPruebas.tecla(arbol, T)
	await UtilesPruebas.tecla(arbol, KEY_W)
	await _real(arbol, 0.6)
	m.casi(Engine.time_scale, 2.0, 0.001, "arriar una vela no corta el modo", _a())
	await UtilesPruebas.tecla(arbol, KEY_S)
	await _real(arbol, 0.6)
	m.casi(Engine.time_scale, 1.0, 0.001, "arriar las dos sí", _a())
	m.comprobar(_motivo(b).contains("velas"), "y dice por qué", _motivo(b))
	await UtilesPruebas.tecla(arbol, KEY_W)
	await UtilesPruebas.tecla(arbol, KEY_S)


## Un cambio de tiempo corta el modo: el viento que refresca o rola de golpe. El rolar lento del
## calendario, que a ×4 son 0,12 °/s, no.
static func _tiempo(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	await _preparar(arbol, b)
	await UtilesPruebas.tecla(arbol, T)
	await UtilesPruebas.tecla(arbol, T)
	# Rolar como el calendario a ×4 durante 3 s reales: no corta.
	var t0 := Time.get_ticks_usec()
	var ang := 0.0
	while Time.get_ticks_usec() - t0 < 3_000_000:
		ang += 0.124 * arbol.root.get_process_delta_time() / maxf(Engine.time_scale, 0.01)
		Viento.direccion_base = Vector3(1, 0, 0).rotated(Vector3.UP, deg_to_rad(ang))
		await arbol.process_frame
	m.casi(Engine.time_scale, 4.0, 0.001, "el rolar lento del alisio no corta el modo",
		"%.2f° en 3 s" % ang)
	Viento.direccion_base = Vector3(1, 0, 0).rotated(Vector3.UP, deg_to_rad(ang + 30.0))
	await _real(arbol, 0.6)
	m.casi(Engine.time_scale, 1.0, 0.001, "el viento que rola 30° de golpe lo corta", _a())
	m.comprobar(_motivo(b).contains("tiempo"), "y dice por qué", _motivo(b))
	await _preparar(arbol, b)
	await UtilesPruebas.tecla(arbol, T)
	Viento.fuerza_base = 1.4
	await _real(arbol, 0.6)
	m.casi(Engine.time_scale, 1.0, 0.001, "el viento que refresca de 1 a 1,4 lo corta", _a())
	m.comprobar(_motivo(b).contains("tiempo"), "y dice por qué", _motivo(b))
	Viento.fuerza_base = 1.0


## Un barco de otro bando a menos de 800 m corta el modo y no deja encenderlo; a 1,5 km, no.
##
## El «barco» es un nodo vacío en el grupo con un capitán de bando enemigo colgado: lo que cuenta
## es el bando y la distancia, no el casco, y una balandra entera más naciendo a la vez estiraría
## las telas de la batería.
static func _enemigo(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	await _preparar(arbol, b)
	var otro := Node3D.new()
	otro.name = "EnemigoDePrueba"
	var cap := Node.new()
	cap.name = "Capitan"
	cap.set_script(_capitan_falso())
	cap.set("bando", "enemigo")
	otro.add_child(cap)
	b.get_parent().add_child(otro)
	otro.add_to_group("barcos")
	var proa := -b.global_transform.basis.z
	otro.global_position = b.global_position + proa * 1500.0
	await UtilesPruebas.tecla(arbol, T)
	await _real(arbol, 0.6)
	m.casi(Engine.time_scale, 2.0, 0.001, "un enemigo a 1,5 km no corta el modo", _a())
	otro.global_position = b.global_position + proa * 600.0
	await _real(arbol, 0.6)
	m.casi(Engine.time_scale, 1.0, 0.001, "un enemigo a 600 m lo corta", _a())
	m.comprobar(_motivo(b).contains("enemigo"), "y dice por qué", _motivo(b))
	await UtilesPruebas.tecla(arbol, T)
	await _real(arbol, 0.3)
	m.casi(Engine.time_scale, 1.0, 0.001, "con el enemigo a la vista la T no lo enciende", _a())
	cap.set("bando", "jugador")
	await UtilesPruebas.tecla(arbol, T)
	await _real(arbol, 0.6)
	m.casi(Engine.time_scale, 2.0, 0.001, "un barco del bando propio a 600 m no lo corta", _a())
	otro.queue_free()
	await _a_uno(arbol)


static func _capitan_falso() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar bando := \"enemigo\"\n"
	s.reload()
	return s


## Tierra o bajío a proa corta el modo. Se lleva el MAPA (no el barco: las telas no se tocan) a
## que Norman Island quede delante de la proa, primero lejos y luego cerca.
static func _tierra(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	await _preparar(arbol, b)
	var g := arbol.get_first_node_in_group("tierra")
	var arch: Archipielago = g.get("archipielago") if g != null else null
	var rel: Object = g.get("relieve") if g != null else null
	var nor: Isla = null
	if arch != null:
		for isla in arch.islas:
			if isla.nombre == "Norman Island":
				nor = isla
	if not m.comprobar(nor != null and rel != null and bool(rel.call("listo")),
			"hay relieve y está Norman Island"):
		return
	# El punto MÁS ALTO de la isla, buscado en su rectángulo: su centro cae en el agua (−0,17 m
	# medidos), porque una isla con bahías no tiene la tierra en el centro de su caja.
	var r := nor.limites()
	var tierra := r.get_center()
	var alto := -INF
	for i in 41:
		for j in 41:
			var q := r.position + r.size * Vector2(i / 40.0, j / 40.0)
			var h := float(rel.call("altura_en", q))
			if h > alto:
				alto = h
				tierra = q
	m.mayor_que(alto, 2.0, "Norman Island tiene tierra en el relieve (m)")
	var aqui := Origen.a_global(b.global_position)
	var vuelta := Vector2(aqui.x, aqui.z)
	var proa3 := -b.global_transform.basis.z
	var proa := Vector2(proa3.x, proa3.z).normalized()

	Origen.llevar_a(tierra - proa * 900.0)
	await _real(arbol, 0.3)
	await UtilesPruebas.tecla(arbol, T)
	await _real(arbol, 0.6)
	m.casi(Engine.time_scale, 2.0, 0.001, "con la isla a 900 m por la proa el modo se enciende",
		_a())
	Origen.llevar_a(tierra - proa * 150.0)
	await _real(arbol, 0.6)
	m.casi(Engine.time_scale, 1.0, 0.001, "con la isla a 150 m por la proa se corta", _a())
	m.comprobar(_motivo(b).contains("tierra"), "y dice por qué", _motivo(b))
	await UtilesPruebas.tecla(arbol, T)
	await _real(arbol, 0.3)
	m.casi(Engine.time_scale, 1.0, 0.001, "con tierra a proa la T no lo enciende", _a())
	Origen.llevar_a(vuelta)
	await _real(arbol, 0.3)


## En la fila de estado del HUD hay un icono de travesía: activo y con «×4» a ×4, apagado a ×1;
## y al cortarse, un aviso con el motivo.
static func _hud(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	await _preparar(arbol, b)
	var hud: Node = null
	for n in arbol.root.find_children("HUD", "CanvasLayer", true, false):
		if n.get_node_or_null("Estado") != null:
			hud = n
	var icono := hud.get_node_or_null("Estado/Travesia") if hud != null else null
	var aviso := hud.get_node_or_null("AvisoTravesia") as Label if hud != null else null
	if not m.comprobar(icono != null and aviso != null,
			"el HUD tiene el icono Estado/Travesia y el aviso AvisoTravesia"):
		return
	await _real(arbol, 0.1)
	m.comprobar(not bool(icono.get("activo")), "a ×1 el icono está apagado")
	m.comprobar(String(icono.get("tecla")) == "[T]", "y enseña su tecla", String(icono.get("tecla")))
	await UtilesPruebas.tecla(arbol, T)
	await UtilesPruebas.tecla(arbol, T)
	await _real(arbol, 0.1)
	m.comprobar(bool(icono.get("activo")) and String(icono.get("texto")) == "×4",
		"a ×4 el icono se enciende y dice ×4", String(icono.get("texto")))
	await UtilesPruebas.tecla(arbol, KEY_SPACE)
	await _real(arbol, 0.6)
	m.comprobar(aviso.visible and aviso.text.contains("ancla"),
		"al cortarse sale un aviso con el motivo", aviso.text)
	await UtilesPruebas.tecla(arbol, KEY_SPACE)
	await _real(arbol, 0.3)
