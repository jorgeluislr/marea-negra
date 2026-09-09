class_name MundoTest
extends RefCounted

## Paquete `mundo`: el viento, el selector de embarcación y lo que se rompió al cambiar de
## barco y volver.


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("mundo")

	# --- Viento: lo leen todas las telas cada frame.
	Viento.bamboleo_dir = 0.12
	Viento.variacion_fuerza = 0.45
	var d0: Vector3 = Viento.direccion
	var f_min := INF
	var f_max := -INF
	for i in 240:
		f_min = minf(f_min, Viento.fuerza)
		f_max = maxf(f_max, Viento.fuerza)
		await arbol.process_frame
	m.casi(Viento.direccion.length(), 1.0, 0.001, "la dirección del viento es unitaria")
	m.comprobar(f_max > f_min, "la fuerza varía en ráfagas", "%.2f a %.2f" % [f_min, f_max])
	m.comprobar(absf(Viento.direccion.y) < 0.001, "y sopla en horizontal")

	# --- Selector de embarcación: TAB cambia de barco y el grupo queda con UNO solo. Si queda
	# más de uno, el mar, el HUD y las flechas siguen al que no toca.
	var antes := UtilesPruebas.barco(arbol)
	var nombre_antes := str(antes.get("nombre"))
	# Identidad de los aparejos de este barco, para saber luego si el barco reinstanciado
	# recibió los SUYOS o se le colaron los del anterior.
	var ids_antes := []
	for h in antes.get_children():
		if h.has_method("izar") and h.get("aparejo") != null:
			ids_antes.append((h.get("aparejo") as Resource).get_instance_id())
	await UtilesPruebas.tecla(arbol, KEY_TAB)
	for i in 120:
		await arbol.process_frame
	var ahora := UtilesPruebas.barco(arbol)
	m.comprobar(arbol.get_nodes_in_group("barco_activo").size() == 1,
		"tras TAB hay exactamente un barco activo",
		"%d" % arbol.get_nodes_in_group("barco_activo").size())
	m.comprobar(ahora != antes and str(ahora.get("nombre")) != nombre_antes,
		"y es otro barco", "%s -> %s" % [nombre_antes, str(ahora.get("nombre"))])

	# La vela del casco de una pieza (lancha/barca/goleta) se iza por el mismo camino que la
	# física, aunque su paño lo dibuje el shader.
	var velas_shader := []
	for h in ahora.get_children():
		if h is VelaShader:
			velas_shader.append(h)
	if m.comprobar(velas_shader.size() == 1, "el casco de una pieza trae su VelaShader"):
		var v: Node = velas_shader[0]
		var apa: Variant = v.get("aparejo")
		m.comprobar(apa != null, "con su aparejo")
		m.comprobar(v.esta_izada(), "y arranca izada")

	# --- Dar la vuelta a la flota y volver. Aquí saltó el bug del aparejo compartido: el
	# ángulo de trimado del barco anterior sobrevivía y la mayor abría estirada al 36 %.
	#
	# El viento ROLA entre cambio y cambio a propósito. Con viento fijo todos los barcos trimaban
	# al mismo ángulo, el estado heredado coincidía con el que tocaba y la prueba pasaba aunque
	# el recurso estuviese compartido: no valía para nada.
	for i in 3:
		Viento.direccion_base = Vector3(1, 0, 0) if i % 2 == 0 else Vector3(-1, 0, 0)
		await UtilesPruebas.tecla(arbol, KEY_TAB)
		for j in 120:
			await arbol.process_frame
	var vuelta := UtilesPruebas.barco(arbol)
	m.comprobar(str(vuelta.get("nombre")) == nombre_antes,
		"la vuelta completa devuelve el barco de salida", str(vuelta.get("nombre")))
	# Un sub-recurso de escena se COMPARTE entre instancias salvo que sea local a ella, y el
	# aparejo guarda estado. Esta comprobación es la que de verdad ataja el bug: no depende de
	# que la física llegue a manifestarlo.
	var ids_ahora := []
	for h in vuelta.get_children():
		if h.has_method("izar") and h.get("aparejo") != null:
			ids_ahora.append((h.get("aparejo") as Resource).get_instance_id())
	var compartidos := 0
	for id in ids_ahora:
		if ids_antes.has(id):
			compartidos += 1
	m.comprobar(compartidos == 0 and not ids_ahora.is_empty(),
		"el barco reinstanciado trae SUS aparejos, no los del anterior",
		"%d de %d compartidos" % [compartidos, ids_ahora.size()])

	await UtilesPruebas.estabilizar(arbol, 3.0)
	for t in UtilesPruebas.telas(arbol):
		var e: Dictionary = await UtilesPruebas.estiramiento(arbol, t)
		if e.is_empty():
			continue
		var tope := 0.06 if t is BanderaFisica else 0.02
		m.menor_que(e["medio"], tope,
			"'%s' vuelve sin estirarse" % str(t.get("nombre_malla")))
