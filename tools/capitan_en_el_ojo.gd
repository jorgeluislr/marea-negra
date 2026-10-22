extends Node

## El CAPITÁN DE IA parado de proa al viento: cuánto tiempo pasa con la proa dentro de la zona
## muerta, cuánto sin arrancada o ciando, y si llega a salir. Es el «se queda bloqueado mirando al
## viento» del enemigo, que `tools/ojo_del_viento.tscn` mide para el JUGADOR (con las teclas).
##
##     godot --path . tools/capitan_en_el_ojo.tscn --max-fps 120
##
## Se suelta una balandra enemiga en el mundo real (con mar: sin ella el alcance mide otro juego),
## PARADA, sin guiñada y con la proa en el ojo, y se le pone el blanco —el barco del jugador,
## fondeado— en tres demoras respecto al viento: a barlovento, de través y a sotavento. Cada caso
## es un barco nuevo, para no heredar la arrancada del anterior.

const MEDIR := 60.0
const DISTANCIA := 200.0


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func():
		push_error("se acabo el tiempo"); get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	_viento()
	await get_tree().create_timer(6.0).timeout
	Oleaje.asentar()
	var mio := UtilesPruebas.barco(get_tree())
	if mio == null:
		get_tree().quit(1)
		return
	print("\n─── el capitán en el ojo del viento ───")
	var resumen: Array[String] = []
	# [demora del blanco desde el viento, nombre, grados que entra desviada la proa]. El ojo exacto
	# no es un caso de laboratorio: el duelo hace nacer a una balandra así.
	for caso in [[0.0, "a barlovento", 0.0], [90.0, "de través", 0.0], [180.0, "a sotavento", 0.0],
			[90.0, "través, 4°", 4.0]]:
		resumen.append(await _caso(mio, caso[0], caso[1], caso[2]))
	print("\n── resumen (%.0f s por caso) ──" % MEDIR)
	for r in resumen:
		print(r)
	get_tree().quit(0)


func _caso(mio: Node3D, demora: float, nombre: String, desvio: float) -> String:
	_viento()
	var origen := Vector3(-1, 0, 0)   # de donde viene el viento (sopla hacia +X)
	var b := (load("res://scenes/barcos/balandra.tscn") as PackedScene).instantiate() as Node3D
	b.name = "Enemigo"
	var cap := CapitanIA.new()
	cap.name = "Capitan"
	cap.bando = "enemigo"
	b.add_child(cap)
	mio.get_parent().add_child(b)
	b.remove_from_group("barco_activo")
	mio.set("anclado", true)
	b.global_position = Vector3(mio.global_position.x, mio.global_position.y, mio.global_position.z) \
		- origen.rotated(Vector3.UP, deg_to_rad(demora)) * DISTANCIA
	# Que monte la artillería y la tela; el barco se mantiene aproado y quieto mientras tanto.
	var t := 0.0
	while t < 3.0:
		_aproar(b, desvio)
		t += get_process_delta_time()
		await get_tree().process_frame
	_aproar(b, desvio)
	# Las piezas se enganchan DESPUÉS de la espera: la artillería se monta en diferido, y
	# enganchadas al meter el barco no había ninguna — ni se contaban los tiros ni se reparaba al
	# blanco, y el barco del jugador se iba a pique a los tres minutos de herramienta.
	var tiros := [0]
	for n in b.find_children("*", "", true, false):
		if n.has_signal("impacto") and n.has_method("disparar") and mio.has_method("reparar"):
			n.connect("impacto", func(_d: Vector3, _c: Node): mio.call("reparar"))
			n.connect("disparo", func(_d: Vector3, _h: Vector3): tiros[0] += 1)

	print("\ncaso: blanco %s a %.0f m" % [nombre, DISTANCIA])
	print("%6s %8s %10s %8s %8s  %s" % ["t s", "vel m/s", "al viento°", "f_viento", "timón", "maniobra"])
	var muerto := float(b.get("angulo_muerto"))
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var en_zona := 0.0
	var racha := 0.0
	var peor_racha := 0.0
	var ciando := 0.0
	var sin_arrancada := 0.0
	var salida := -1.0
	var siguiente := 0.0
	t = 0.0
	var al := 0.0
	while t < MEDIR:
		_viento()
		b.set("anclado", false)
		mio.set("anclado", true)
		await get_tree().physics_frame
		t += dt
		var proa := -b.global_transform.basis.z
		proa.y = 0.0
		al = rad_to_deg(proa.normalized().angle_to(origen))
		var v := float(b.get("velocidad"))
		if al < muerto:
			en_zona += dt
			racha += dt
			peor_racha = maxf(peor_racha, racha)
		else:
			racha = 0.0
			if salida < 0.0:
				salida = t
		if v < -0.05:
			ciando += dt
		if absf(v) < 0.5:
			sin_arrancada += dt
		if t >= siguiente:
			siguiente += 3.0
			print("%6.1f %8.3f %10.1f %8.3f %8.2f  %-18s %d tiros, dist %.0f" % [t, v, al,
				float(b.call("factor_viento")), float(b.get("orden_timon")), cap.call("maniobra_actual"),
				tiros[0], b.global_position.distance_to(mio.global_position)])
	var linea := ("%-13s zona muerta %5.1f s (racha máx %5.1f), ciando %5.1f s, |v|<0,5 %5.1f s, "
		+ "%s, al final a %.0f° del viento, %d disparos") % [nombre, en_zona, peor_racha, ciando,
		sin_arrancada, "sale a los %.1f s" % salida if salida >= 0.0 else "NO SALE", al, tiros[0]]
	print("-> " + linea)
	b.get_parent().remove_child(b)
	b.queue_free()
	await get_tree().process_frame
	return linea


func _aproar(b: Node3D, desvio := 0.0) -> void:
	# Proa a −X, que es de donde viene el viento: `rotate_y(+90°)` lleva el −Z del casco a −X.
	b.global_rotation = Vector3(0.0, deg_to_rad(90.0 + desvio), 0.0)
	b.set("velocidad", 0.0)
	b.set("velocity", Vector3.ZERO)
	b.set("_guinada", 0.0)


func _viento() -> void:
	Viento.direccion_base = Vector3(1, 0, 0)
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	Viento.fuerza_base = 1.0
