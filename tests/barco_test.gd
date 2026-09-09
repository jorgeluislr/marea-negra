class_name BarcoTest
extends RefCounted

## Paquete `barco`: lo que `Barco` absorbió de los scripts-nodo sueltos y que se rompe en
## silencio — no da error, simplemente deja de hacerse.


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("barco")
	var b := UtilesPruebas.barco(arbol)
	if not m.comprobar(b != null, "hay un barco en el grupo 'barco_activo'"):
		return
	m.comprobar(b is Barco, "el barco es un Barco", b.get_class())
	m.comprobar(b is Balandra, "el barco de salida es la Balandra", str(b.get("nombre")))

	# --- Colisionadores de cubierta (antes colisiones_barco.gd). Sin ellos no hay suelo que
	# pisar, y el fallo no se ve hasta que bajas a cubierta y te caes al agua.
	var cuerpo := b.find_child("Colisiones", false, false) as StaticBody3D
	if m.comprobar(cuerpo != null, "monta el StaticBody de cubierta"):
		var formas := 0
		var suelos := 0
		for h in cuerpo.get_children():
			if h is CollisionShape3D:
				formas += 1
				if (h as CollisionShape3D).shape is ConcavePolygonShape3D:
					suelos += 1
		m.comprobar(formas > 50, "levanta las cajas de borda y barrera", "%d formas" % formas)
		m.comprobar(suelos == 2, "las dos mallas de suelo son trimesh", "%d" % suelos)
		m.comprobar(cuerpo.collision_layer == 4,
			"las colisiones van en la capa 3, no en la del casco", str(cuerpo.collision_layer))

	# --- Timón (antes control_timon.gd): refleja la ENTRADA, así que responde aun parado.
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
	var velas := []
	for h in b.get_children():
		if h.has_method("izar"):
			velas.append(h)
	if m.comprobar(velas.size() == 2, "encuentra sus dos velas", "%d" % velas.size()):
		await UtilesPruebas.tecla(arbol, KEY_S)     # cierra la de POPA
		for i in 300:
			await arbol.process_frame
		var proa: Node = velas[0] if int(velas[0].get("mando")) == 0 else velas[1]
		var popa: Node = velas[1] if int(velas[0].get("mando")) == 0 else velas[0]
		m.comprobar(not popa.esta_izada(), "S arría la vela de popa")
		m.comprobar(proa.esta_izada(), "y NO toca la de proa")
		await UtilesPruebas.tecla(arbol, KEY_S)
		for i in 300:
			await arbol.process_frame
		m.comprobar(popa.esta_izada(), "S otra vez la vuelve a izar")

	# --- Cambio de modo (antes paseo_cubierta.gd). El jugador tiene que colgar DEL BARCO o se
	# queda atrás en cuanto el barco navega.
	await UtilesPruebas.tecla(arbol, KEY_F)
	for i in 90:
		await arbol.process_frame
	var jug := b.find_child("Player", false, false)
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
