class_name BarcoTest
extends RefCounted

## Paquete `barco`: lo que `Barco` absorbió de los scripts-nodo sueltos y que se rompe en
## silencio — no da error, simplemente deja de hacerse.
##
## Partido en ESCENARIOS que se preparan solos y dejan el barco como lo encontraron, para poder
## pedir uno suelto (`-- barco/timon`). Ninguno cuenta con lo que haya dejado el anterior.


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("barco")
	var b := UtilesPruebas.barco(arbol)
	if not m.comprobar(b != null, "hay un barco en el grupo 'barco_activo'"):
		return
	m.comprobar(b is Barco, "el barco es un Barco", b.get_class())
	m.comprobar(b is Balandra, "el barco de salida es la Balandra", str(b.get("nombre")))

	if m.escenario("cabeceo"):
		await _cabeceo(m, arbol, b)
	if m.escenario("masa"):
		await _masa(m, arbol, b)
	if m.escenario("ojo_del_viento"):
		await _ojo_del_viento(m, arbol, b)
	if m.escenario("cubierta"):
		_cubierta(m, b)
	if m.escenario("jarcia_solida"):
		_jarcia_solida(m, b)
	if m.escenario("paso_obenques"):
		_paso_obenques(m, b)
	if m.escenario("timon"):
		await _timon(m, arbol, b)
	if m.escenario("velas"):
		await _velas(m, arbol, b)
	if m.escenario("a_pie"):
		await _a_pie(m, arbol, b)
	if m.escenario("trepar"):
		await _trepar(m, arbol, b)
	if m.escenario("al_agua"):
		await _al_agua(m, arbol, b)


# --- CABECEO. La escora se veía bien y el balanceo de proa a popa no, y no es cosa de gusto:
# el casco leía la ola en la proa y en la popa SOLAS, con doce metros entre medias, y dos
# puntos separados una eslora promedian a cero cualquier ola de esa misma eslora y recortan a
# la mitad las más cortas, que son las de más pendiente. Encima la obediencia a la ola era una
# sola para las dos inclinaciones, cuando la estabilidad longitudinal de cualquier casco es dos
# órdenes mayor que la transversal: un barco escora bastante menos que la ola y cabecea casi
# exactamente con ella.
#
# Se mide ANCLADO y con la mar de proa, que es el rumbo que más cabeceo pide, y se compara con
# lo que la propia ola pide a la recta proa-popa, no con un número suelto: así la comprobación
# no depende del estado de la mar del día. Medido con `tools/cabeceo_en_la_mar.tscn`: antes
# 3,46° de pico a pico contra 6,33 que pedía la ola (55 %).
static func _cabeceo(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	var rumbo_previo: float = b.global_rotation.y
	var anclado_previo: bool = bool(b.get("anclado"))
	b.set("anclado", true)
	var dm := Vector2(Viento.direccion_base.x, Viento.direccion_base.z).normalized()
	b.global_rotation = Vector3(0.0, atan2(dm.x, dm.y), 0.0)
	for i in 120:
		await arbol.physics_frame
	var semi: Vector2 = b.get("recorte_radio")
	var cab := [INF, -INF]
	var pide := [INF, -INF]
	var sa := 0.0
	var sb := 0.0
	var saa := 0.0
	var sbb := 0.0
	var sab := 0.0
	var pasos := 0
	for i in 480:
		await arbol.physics_frame
		var g: Transform3D = b.global_transform
		var ph := Vector2((-g.basis.z).x, (-g.basis.z).z).normalized()
		var c := Vector2(g.origin.x, g.origin.z)
		var v := rad_to_deg(g.basis.get_euler().x)
		cab[0] = minf(cab[0], v); cab[1] = maxf(cab[1], v)
		# La ola se lee con la proa y la popa a secas, que NO es como el casco la lee: se compara
		# contra una medida independiente de la implementación a propósito.
		var w := rad_to_deg(atan2(Oleaje.altura_en(c + ph * semi.y)
			- Oleaje.altura_en(c - ph * semi.y), semi.y * 2.0))
		pide[0] = minf(pide[0], w); pide[1] = maxf(pide[1], w)
		sa += v; sb += w; saa += v * v; sbb += w * w; sab += v * w; pasos += 1
	var pp: float = cab[1] - cab[0]
	var pp_ola: float = maxf(pide[1] - pide[0], 0.01)
	var fn := float(maxi(pasos, 1))
	var r: float = (sab / fn - (sa / fn) * (sb / fn)) / maxf(sqrt(
		maxf(saa / fn - (sa / fn) * (sa / fn), 0.0)
		* maxf(sbb / fn - (sb / fn) * (sb / fn), 0.0)), 1e-9)
	m.mayor_que(pp, 5.0, "con la mar de proa el casco cabecea de verdad",
		"%.2f° de pico a pico" % pp)
	m.mayor_que(pp / pp_ola, 0.9, "y cabecea con la ola, no a la mitad de lo que ella pide",
		"%.2f° contra %.2f° de la ola" % [pp, pp_ola])
	# LA comprobación de las tres: con el signo invertido las dos de arriba pueden salir verdes
	# —el casco se mueve, y mucho— mientras mete la proa justo cuando la ola se la levanta. Con
	# los cuatro puntos esto medía −0,82.
	m.mayor_que(r, 0.5, "y sube la proa cuando la ola se la levanta, no al revés",
		"parecido %+.3f" % r)
	await _devolver(arbol, b, anclado_previo, rumbo_previo)


# --- EL CASCO TIENE MASA TAMBIÉN AL TUMBARSE Y AL GIRAR. El usuario lo vio como "la fuerza del
# giro y el viento no están frenadas por el peso del barco", y las dos cosas eran ciertas.
# Medido con `tools/escora_dinamica.tscn`, con el balance de la ola apagado para que no tape nada:
#
# - con las rachas de través el viento pedía de 1,5° a 7,5° y el casco se iba de 0,1° a 9,3°:
#   AMPLIFICABA la racha. Un casco pesado la filtra; nunca puede tumbarse más de lo que le piden.
# - con la caña a la banda el barco giraba a 25,8 °/s a los 0,1 s, que era ya su giro entero.
#   Sin inercia de guiñada la escora del giro aparece de golpe con ella.
static func _masa(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	await UtilesPruebas.al_timon(arbol)
	var rumbo_previo: float = b.global_rotation.y
	var anclado_previo: bool = bool(b.get("anclado"))
	var dm := Vector2(Viento.direccion_base.x, Viento.direccion_base.z).normalized()
	var obed_previa: float = b.get("obediencia_escora")
	var racha_previa := Viento.variacion_fuerza
	var bamboleo_previo := Viento.bamboleo_dir
	b.set("obediencia_escora", 0.0)
	b.set("anclado", false)
	Viento.variacion_fuerza = 0.45
	Viento.bamboleo_dir = 0.12
	b.global_rotation = Vector3(0.0, atan2(dm.x, dm.y) + PI * 0.5, 0.0)
	for i in 480:
		await arbol.physics_frame
	var obj := [INF, -INF]
	var escs := [INF, -INF]
	for i in 1200:
		await arbol.physics_frame
		var o := rad_to_deg(float(b.call("_escora_de_navegacion")))
		var e := rad_to_deg(b.global_transform.basis.get_euler().z)
		obj[0] = minf(obj[0], o); obj[1] = maxf(obj[1], o)
		escs[0] = minf(escs[0], e); escs[1] = maxf(escs[1], e)
	var pp_obj: float = maxf(obj[1] - obj[0], 0.01)
	var pp_esc: float = escs[1] - escs[0]
	m.menor_que(pp_esc / pp_obj, 1.0, "con rachas de través el casco no se tumba más de lo que pide el viento",
		"%.2f° de pico a pico contra %.2f° pedidos" % [pp_esc, pp_obj])
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	for i in 240:
		await arbol.physics_frame
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var r_prev := atan2((-b.global_transform.basis.z).x, (-b.global_transform.basis.z).z)
	var w_01 := 0.0
	var w_max := 0.0
	var ev_t := InputEventKey.new()
	ev_t.keycode = KEY_D
	ev_t.physical_keycode = KEY_D
	ev_t.pressed = true
	Input.parse_input_event(ev_t)
	for i in int(3.0 / dt):
		await arbol.physics_frame
		var p := -b.global_transform.basis.z
		var rr := atan2(p.x, p.z)
		var w := absf(rad_to_deg(wrapf(rr - r_prev, -PI, PI)) / dt)
		r_prev = rr
		if i == int(0.1 / dt):
			w_01 = w
		w_max = maxf(w_max, w)
	ev_t.pressed = false
	Input.parse_input_event(ev_t)
	m.menor_que(w_01 / maxf(w_max, 0.01), 0.5, "y al meter la caña el giro tarda en entrar",
		"%.1f °/s a los 0,1 s de %.1f °/s" % [w_01, w_max])
	# Y CONSERVA SU ARRANCADA al aproar. El casco iba a su velocidad objetivo con una aceleración
	# constante de 2 m/s², igual para frenar que para arrancar: de proa al viento, ciñendo a 1,4 m/s,
	# se paraba en 0,7 s. Así no hay virada por avante posible con un casco que tarda en girar, y el
	# capitán de IA se quedaba en el ojo. Lo que frena a un barco que ya no propulsa es el agua, que
	# frena con el CUADRADO de la velocidad: va perdiendo arrancada, no se clava.
	b.global_rotation = Vector3(0.0, atan2(dm.x, dm.y) + PI * 0.5, 0.0)
	for i in 480:
		await arbol.physics_frame
	var v0: float = b.get("velocidad")
	b.global_rotation = Vector3(0.0, atan2(dm.x, dm.y), 0.0)
	for i in int(1.0 / dt):
		await arbol.physics_frame
	var v1: float = b.get("velocidad")
	m.mayor_que(v1 / maxf(v0, 0.01), 0.6, "y aproado conserva su arrancada un rato",
		"%.2f m/s al segundo de aproar, de %.2f" % [v1, v0])
	b.set("obediencia_escora", obed_previa)
	Viento.variacion_fuerza = racha_previa
	Viento.bamboleo_dir = bamboleo_previo
	await _devolver(arbol, b, anclado_previo, rumbo_previo)


# --- SALE DEL OJO DEL VIENTO CIANDO. Parado de proa al viento la vela no tira; el viento en el
# aparejo la hace ciar, y con arrancada atrás la caña obra al revés: el barco cae a la banda
# contraria a la caña (estribor → la proa a babor), sale de la zona muerta y vuelve a avanzar en
# cuanto la vela porta. Con la masa del casco (`aceleracion` 0,29) la cía se quedaba en nada:
# medido con `tools/ojo_del_viento.tscn`, −0,055 m/s y 4,4° girados en 30 s, sin salir nunca.
static func _ojo_del_viento(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	await UtilesPruebas.al_timon(arbol)
	var rumbo_previo: float = b.global_rotation.y
	var anclado_previo: bool = bool(b.get("anclado"))
	var velas_previas := [bool(b.get("vela_delantera")), bool(b.get("vela_trasera"))]
	var racha_previa := Viento.variacion_fuerza
	var bamboleo_previo := Viento.bamboleo_dir
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	b.set("anclado", false)
	b.call("set_vela_delantera", true)
	b.call("set_vela_trasera", true)
	var dm := Vector2(Viento.direccion_base.x, Viento.direccion_base.z).normalized()
	b.global_rotation = Vector3(0.0, atan2(dm.x, dm.y), 0.0)
	b.set("velocidad", 0.0)
	b.set("velocity", Vector3.ZERO)
	b.set("_guinada", 0.0)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var ev := InputEventKey.new()
	ev.keycode = KEY_D
	ev.physical_keycode = KEY_D
	ev.pressed = true
	Input.parse_input_event(ev)
	var previo: float = b.global_rotation.y
	var girado := 0.0       # + = la proa cae a babor
	var v_min := 0.0
	var t_salida := -1.0
	var girado_salida := 0.0
	var t_avante := -1.0
	var t := 0.0
	while t < 50.0 and t_avante < 0.0:
		await arbol.physics_frame
		t += dt
		girado += rad_to_deg(wrapf(b.global_rotation.y - previo, -PI, PI))
		previo = b.global_rotation.y
		var v: float = b.get("velocidad")
		v_min = minf(v_min, v)
		if t_salida < 0.0 and float(b.call("factor_viento")) > 0.05:
			t_salida = t
			girado_salida = girado
		if t_salida >= 0.0 and v > 0.0:
			t_avante = t
	ev.pressed = false
	Input.parse_input_event(ev)
	m.menor_que(v_min, -0.2, "de proa al viento y parado, el viento la hace ciar",
		"%.2f m/s" % v_min)
	m.comprobar(t_salida >= 0.0 and t_salida < 40.0 and girado_salida > 0.0,
		"y ciando con la caña a estribor sale de la zona muerta con la proa a babor",
		"a los %.1f s, %+.1f°" % [t_salida, girado_salida] if t_salida >= 0.0
			else "no sale en %.0f s: %+.1f° girados" % [t, girado])
	m.comprobar(t_avante >= 0.0, "y vuelve a avanzar en cuanto la vela porta",
		"a los %.1f s" % t_avante if t_avante >= 0.0 else "en %.0f s no avanza" % t)
	b.call("set_vela_delantera", velas_previas[0])
	b.call("set_vela_trasera", velas_previas[1])
	Viento.variacion_fuerza = racha_previa
	Viento.bamboleo_dir = bamboleo_previo
	await _devolver(arbol, b, anclado_previo, rumbo_previo)


# --- Colisionadores de cubierta (antes colisiones_barco.gd). Sin ellos no hay suelo que
# pisar, y el fallo no se ve hasta que bajas a cubierta y te caes al agua.
static func _cubierta(m: MarcoPruebas, b: Node3D) -> void:
	var cuerpo := b.find_child("Colisiones", false, false) as StaticBody3D
	if m.comprobar(cuerpo != null, "monta el StaticBody de cubierta"):
		var formas := 0
		var suelos := 0
		for h in cuerpo.get_children():
			if h is CollisionShape3D:
				formas += 1
				if (h as CollisionShape3D).shape is ConcavePolygonShape3D:
					suelos += 1
		# 34 con las 16 secciones de la balandra: dos bordas por sección, los suelos de proa y popa
		# y los dos tapones. Eran más de 50 mientras se levantaba la barrera invisible sobre la
		# regala; ya no se levanta (`colision_alto_barrera` = 0) porque impedía saltar al agua y
		# subir por los obenques, y ahora el que cae nada.
		m.comprobar(formas > 25, "levanta las cajas de borda", "%d formas" % formas)
		m.comprobar(suelos == 2, "las dos mallas de suelo son trimesh", "%d" % suelos)
		m.comprobar(cuerpo.collision_layer == 4,
			"las colisiones van en la capa 3, no en la del casco", str(cuerpo.collision_layer))


# --- PALOS Y JARCIA SÓLIDOS PARA EL PERSONAJE. Los cuerpos que levanta `perchas_solidas` nacieron
# para que la lona no atravesara las perchas, y por eso iban en una capa que solo miran las velas:
# el personaje cruzaba el mástil, la botavara y los obenques como si fueran humo. Ahora esos
# mismos cuerpos llevan también la capa 3, que es la que enmascara el jugador (su `collision_mask`
# es 5: mundo y cubierta).
#
# Se comprueban las dos cosas por separado porque fallan por separado: que ESTÉN todas las piezas
# —una lista de patrones que no case deja la jarcia sin cuerpo y no avisa de nada— y que de verdad
# paren un rayo en la máscara del jugador. Esto último con el MÁSTIL, que a media altura es lo
# único que hay en medio metro a la redonda.
static func _jarcia_solida(m: MarcoPruebas, b: Node3D) -> void:
	var solidos := {}
	for n in b.find_children("Percha_*", "StaticBody3D", true, false):
		solidos[(n as StaticBody3D).name] = (n as StaticBody3D).collision_layer
	for pieza in ["Percha_mastil_v3", "Percha_botavara", "Percha_pico",
			"Percha_obenque_pp_e", "Percha_obenque_pr_b", "Percha_flechaste_e_00"]:
		m.comprobar(solidos.has(pieza) and (int(solidos[pieza]) & 4) != 0,
			"'%s' es sólido para el personaje" % pieza.trim_prefix("Percha_"),
			"capa %s" % str(solidos.get(pieza, "no existe")))
	m.comprobar(solidos.size() >= 36, "y está toda la jarcia, no solo las perchas",
		"%d cuerpos" % solidos.size())
	var palo := b.find_children("mastil_v3", "MeshInstance3D", true, false)
	if m.comprobar(not palo.is_empty(), "el barco tiene la malla del mástil"):
		var mi := palo[0] as MeshInstance3D
		var centro := mi.global_transform * mi.mesh.get_aabb().get_center()
		var lado := b.global_transform.basis.x.normalized() * 0.5
		var q := PhysicsRayQueryParameters3D.create(centro - lado, centro + lado)
		# La máscara del jugador, tal cual está en player.tscn: mundo (1) y cubierta (4).
		q.collision_mask = 5
		var golpe := b.get_world_3d().direct_space_state.intersect_ray(q)
		m.comprobar(not golpe.is_empty(),
			"y el mástil para un rayo en la máscara del jugador",
			"" if golpe.is_empty() else String((golpe["collider"] as Node).name))


# --- Y HAY PASO PARA SUBIR POR LOS OBENQUES, POR FUERA. A los obenques se sube desde la regala
# con el cuerpo hacia el mar y la escala contra el pecho, que es como se sube en un barco; la
# barrera invisible de la regala sube 1,6 m justo por ahí y caía encima de las mesas de
# guarnición, donde nace la escala de flechastes.
#
# Se prueba con la cápsula desplazada HACIA FUERA del peldano, su diámetro y no su radio: el
# personaje tiene que caber entero al otro lado del cabo. Medido con
# `tools/subir_por_obenques.tscn` antes del arreglo: **5 peldanos de 13** mordidos por la
# barrera, y los cinco de abajo, que son por donde se empieza.
#
# Peldano a peldano y no en un punto: al pie de la escala la cápsula cabía ya antes y ocho
# peldanos más arriba también, así que una muestra suelta hacía descartar la barrera.
#
# Solo cuenta la BARRERA: que el peldano más bajo toque la borda es geometría del barco — la
# regala es madera de verdad y está a 8 cm de él.
static func _paso_obenques(m: MarcoPruebas, b: Node3D) -> void:
	var pj := (load("res://scenes/character/player.tscn") as PackedScene).instantiate()
	var forma: Shape3D = (pj.find_child("CollisionShape3D", false, false) as CollisionShape3D).shape
	var mascara: int = (pj as CharacterBody3D).collision_mask
	var radio: float = (forma as CapsuleShape3D).radius
	pj.queue_free()
	var tapados := 0
	var peldanos := 0
	var quien := ""
	for n in b.find_children("flechaste_e_*", "MeshInstance3D", true, false):
		var fl := n as MeshInstance3D
		peldanos += 1
		var caja := fl.mesh.get_aabb()
		# El GRUESO del cabo, no su largo: un flechaste mide 1,44 m de punta a punta y 6 cm de
		# grueso, y con el máximo de la caja el punto de prueba se iba 70 cm mar adentro.
		var grueso: float = minf(minf(caja.size.x, caja.size.y), caja.size.z) * 0.5
		var p: Vector3 = fl.global_transform * caja.get_center()
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = forma
		q.transform = Transform3D(Basis(),
			p + b.global_transform.basis.x.normalized() * (radio + grueso))
		q.collision_mask = mascara
		for golpe in b.get_world_3d().direct_space_state.intersect_shape(q, 32):
			var col := golpe["collider"] as CollisionObject3D
			# La jarcia no estorba: es a lo que se agarra.
			if String(col.name).begins_with("Percha_"):
				continue
			var due := col.shape_owner_get_owner(col.shape_find_owner(int(golpe["shape"])))
			var nom: String = String((due as Node).name) if due != null else String(col.name)
			if nom.begins_with("Barrera"):
				tapados += 1
				quien = nom
				break
	if m.comprobar(peldanos > 0, "la balandra tiene su escala de flechastes"):
		m.comprobar(tapados == 0, "y la barrera de la regala deja subir por fuera",
			"%d peldanos de %d mordidos por %s" % [tapados, peldanos, quien if quien != "" else "nada"])


# --- Timón (antes control_timon.gd): refleja la ENTRADA, así que responde aun parado.
static func _timon(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	await UtilesPruebas.al_timon(arbol)
	var skel := b.find_children("*", "Skeleton3D", true, false)
	if m.comprobar(not skel.is_empty(), "el barco tiene esqueleto"):
		var s := skel[0] as Skeleton3D
		var hueso := s.find_bone("timon")
		if m.comprobar(hueso >= 0, "existe el hueso del timón"):
			var reposo := s.get_bone_pose_rotation(hueso)
			var e := InputEventKey.new()
			e.keycode = KEY_A
			e.physical_keycode = KEY_A
			e.pressed = true
			Input.parse_input_event(e)
			for i in 40:
				await arbol.process_frame
			var girado := s.get_bone_pose_rotation(hueso)
			var giro := rad_to_deg(reposo.angle_to(girado))
			var su := InputEventKey.new()
			su.keycode = KEY_A
			su.physical_keycode = KEY_A
			su.pressed = false
			Input.parse_input_event(su)
			m.comprobar(giro > 5.0, "la caña cae a banda con A", "%.1f°" % giro)
			for i in 90:
				await arbol.process_frame
			var vuelta := rad_to_deg(reposo.angle_to(s.get_bone_pose_rotation(hueso)))
			m.menor_que(vuelta, 3.0, "y vuelve al centro al soltar")


# --- El barco manda sobre SUS velas y solo sobre las que le tocan (antes, tres nodos
# `control_izado` se conectaban por su cuenta a las señales).
static func _velas(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	await UtilesPruebas.al_timon(arbol)
	var velas := []
	for h in b.get_children():
		if h.has_method("izar"):
			velas.append(h)
	if m.comprobar(velas.size() == 2, "encuentra sus dos velas", "%d" % velas.size()):
		var proa: Node = velas[0] if int(velas[0].get("mando")) == 0 else velas[1]
		var popa: Node = velas[1] if int(velas[0].get("mando")) == 0 else velas[0]
		# Se parte de la de popa IZADA, que es como el barco sale: S es un conmutador y lo que se
		# comprueba depende de dónde empiece.
		if not popa.esta_izada():
			await UtilesPruebas.tecla(arbol, KEY_S)
			for i in 300:
				await arbol.process_frame
		await UtilesPruebas.tecla(arbol, KEY_S)     # cierra la de POPA
		for i in 300:
			await arbol.process_frame
		m.comprobar(not popa.esta_izada(), "S arría la vela de popa")
		m.comprobar(proa.esta_izada(), "y NO toca la de proa")
		await UtilesPruebas.tecla(arbol, KEY_S)
		for i in 300:
			await arbol.process_frame
		m.comprobar(popa.esta_izada(), "S otra vez la vuelve a izar")


# --- Cambio de modo (antes paseo_cubierta.gd). El jugador tiene que colgar DEL BARCO o se
# queda atrás en cuanto el barco navega.
static func _a_pie(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	var jug: Node = await _a_cubierta(arbol, b)
	if m.comprobar(jug != null, "F baja a cubierta e instancia el personaje"):
		m.comprobar(jug is Jugador, "el personaje es un Jugador")
		m.comprobar(jug.get_parent() == b, "y cuelga del barco, para que lo lleve al navegar")
		m.comprobar(not bool(b.get("gobierno")), "el barco suelta el gobierno mientras andas")
		m.comprobar((jug as CharacterBody3D).is_on_floor(), "el personaje pisa la cubierta")
	await UtilesPruebas.tecla(arbol, KEY_F)
	for i in 90:
		await arbol.process_frame
	m.comprobar(b.find_child("Player", false, false) == null, "F devuelve el timón")
	m.comprobar(bool(b.get("gobierno")), "y el barco recupera el gobierno")


# --- Y TREPA POR LA JARCIA. Trepar es un MODO, no un problema de colisionadores, y eso
# está medido: posando al personaje encima de un peldano y soltándolo, la cápsula cae 43,9 m
# hasta el agua, la caja 2,0 y el cilindro 1,77 — cambiar su figura no lo arregla
# (`tools/subir_por_obenques.tscn` mide las tres). Un peldano tiene 3,4 cm de grueso y hay
# 38 cm hasta el siguiente.
#
# Se comprueba lo que se ve: que SE ENGANCHA y que SUBE. Lo primero sin lo segundo es un
# personaje pegado al palo sin moverse, y lo segundo sin lo primero no puede pasar.
static func _trepar(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	var jug: Node = await _a_cubierta(arbol, b)
	if not m.comprobar(jug != null, "F baja a cubierta para trepar"):
		await UtilesPruebas.al_timon(arbol)
		return
	var escalas := b.find_children("Escala_*", "Area3D", false, false)
	m.comprobar(escalas.size() == 2, "monta una escala de jarcia por banda",
		"%d" % escalas.size())
	if not escalas.is_empty():
		var esc: Node3D = escalas[0]
		# Al pie de la escala, mirándola: es desde donde se agarra uno.
		var pie: Vector3 = esc.global_position - esc.fuera() * 0.7 + Vector3.UP * 0.2
		(jug as CharacterBody3D).global_position = pie
		(jug as Node3D).look_at(pie + esc.fuera(), Vector3.UP)
		for i in 20:
			await arbol.process_frame
		var y0: float = (jug as Node3D).global_position.y
		var ev := InputEventKey.new()
		ev.keycode = KEY_W
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
		var engancho := false
		for i in 240:
			await arbol.physics_frame
			if bool(jug.call("trepando")):
				engancho = true
		ev.pressed = false
		Input.parse_input_event(ev)
		var subido: float = (jug as Node3D).global_position.y - y0
		m.comprobar(engancho, "el personaje se agarra a la jarcia con W mirándola")
		m.mayor_que(subido, 2.0, "y sube por ella", "%.2f m" % subido)
		# Y se suelta: con la cápsula colgada del aparejo no se puede seguir jugando.
		jug.call("soltar_escala")
		m.comprobar(not bool(jug.call("trepando")), "y se suelta cuando se le pide")
	await UtilesPruebas.al_timon(arbol)


# --- HOMBRE AL AGUA. El personaje va a bordo como HIJO del casco, para que la cubierta lo
# arrastre al navegar; en el agua eso es justo lo que sobra, o el náufrago viajaría con el
# barco a nueve nudos. Se comprueban las tres cosas que se rompen por separado: que pase a
# nadar, que DEJE de colgar del barco y que pueda volver a bordo.
#
# La flotación se mide contra la OLA de debajo y no contra una altura fija: el mar sube y
# baja 1,6 m, y quedarse quieto respecto al cero del mundo sería lo contrario de flotar.
static func _al_agua(m: MarcoPruebas, arbol: SceneTree, b: Node3D) -> void:
	var jug: Node = await _a_cubierta(arbol, b)
	if not m.comprobar(jug != null, "F baja a cubierta para caer al agua"):
		await UtilesPruebas.al_timon(arbol)
		return
	jug.call("soltar_escala")
	(jug as CharacterBody3D).global_position = b.global_transform * Vector3(6.0, 4.0, 0.0)
	(jug as CharacterBody3D).velocity = Vector3.ZERO
	for i in 360:
		await arbol.physics_frame
	m.comprobar(bool(jug.call("nadando")), "el que cae por la borda nada")
	m.comprobar(jug.get_parent() != b, "y deja de colgar del barco",
		String(jug.get_parent().name))
	var mar: float = Oleaje.altura_en(Vector2(
		(jug as Node3D).global_position.x, (jug as Node3D).global_position.z))
	m.menor_que(absf((jug as Node3D).global_position.y - mar), 0.6,
		"flotando a la altura de la ola")
	# Y vuelve a bordo: pegado al costado, mirando al barco, con la E de siempre.
	(jug as CharacterBody3D).global_position = b.global_transform * Vector3(3.0, 1.5, 0.0)
	(jug as Node3D).look_at(b.global_position + Vector3.UP * 1.5, Vector3.UP)
	for i in 30:
		await arbol.physics_frame
	await UtilesPruebas.tecla(arbol, KEY_E)
	for i in 30:
		await arbol.physics_frame
	m.comprobar(jug.get_parent() == b, "y con E vuelve a bordo",
		String(jug.get_parent().name))
	# F devuelve el timón también desde el agua: `_a_gobernar` libera al personaje esté donde esté.
	await UtilesPruebas.al_timon(arbol)


# ── Preparación ──────────────────────────────────────────────────────────────

## Baja a cubierta desde el timón y devuelve el personaje (o null si no apareció).
static func _a_cubierta(arbol: SceneTree, b: Node3D) -> Node:
	await UtilesPruebas.al_timon(arbol)
	await UtilesPruebas.tecla(arbol, KEY_F)
	for i in 90:
		await arbol.process_frame
	return b.find_child("Player", false, false)


## Vuelve a dejar el barco con el ancla y el rumbo con que el escenario lo encontró.
static func _devolver(arbol: SceneTree, b: Node3D, anclado: bool, rumbo: float) -> void:
	b.set("anclado", anclado)
	b.global_rotation = Vector3(0.0, rumbo, 0.0)
	for i in 30:
		await arbol.physics_frame
