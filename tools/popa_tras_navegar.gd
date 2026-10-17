extends Node

## Por qué el obenque de popa atraviesa la mayor en popa cerrada SOLO si antes el barco navegó.
##
## Prepara el barco de una de varias maneras y luego lo lleva a popa fondeado, como
## `tela/popa_obenques`, imprimiendo cada segundo dónde está la vela y cuántas caras atraviesa
## la jarcia. Una tirada por preparación, porque el estado que se busca es lo que deja la
## anterior:
##
##     godot --path . tools/popa_tras_navegar.tscn --max-fps 120 -- fondeado
##     godot --path . tools/popa_tras_navegar.tscn --max-fps 120 -- libre
##     godot --path . tools/popa_tras_navegar.tscn --max-fps 120 -- arriar_libre
##     godot --path . tools/popa_tras_navegar.tscn --max-fps 120 -- arriar_fondeado
##
## `libre` navega 13 s de través sin tocar la vela; `libre_parado` navega y luego se para;
## `arriar_*` repite lo de `tela/arriar` (arriar e izar con S) navegando o fondeado.
##
## Más argumentos: el rumbo del viento en popa (`-- fondeado 175`; por defecto 160°, el de
## `tela/popa_obenques`), `clave=valor` para la mayor o `PerchasSolidas` (`empuje_viento=10`,
## `radio_lona=0.02`, `holgura_caja=1` para que el arreglo casi no actúe), y `reiniciar=espacio|capa|mascara|copia|consulta` para
## tocar la colisión al final con la lona ya apoyada y ver qué la saca.
##
## Lo que contó el 17-10-2026: el historial NO importa. Falla siempre que la lona llega al muro
## (fondeado a 160° no llega), con el muro de 20 cm igual que con uno de 2, y solo lo arregla
## `reiniciar=espacio`, que rehace la caja del `SoftBody` en la fase ancha. Ojo: `consulta`
## (`intersect_shape`) no ve NUNCA un `SoftBody3D`, ni con la esfera centrada en sus puntos, así que
## su cero no dice nada. Ver `TelaFisica._vigilar_caja`.

const PREPARAR := 13.0
const POPA := 12.0


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func():
		push_error("se acabo el tiempo"); get_tree().quit(1))
	var args := OS.get_cmdline_user_args()
	var modo: String = args[0] if not args.is_empty() else "libre"
	# El resto, `clave=valor`, se pone a la mayor (`empuje_viento`, `precision`...) o a
	# `PerchasSolidas` (`radio_lona`) al entrar en el árbol, antes de que monten nada.
	for a in args:
		if not "=" in a:
			continue
		var kv := a.split("=")
		get_tree().node_added.connect(func(n: Node):
			var es_mayor := str(n.get("nombre_malla")) == "vela_mayor"
			if (es_mayor or n.name == "PerchasSolidas") and n.get(kv[0]) != null:
				n.set(kv[0], type_convert(kv[1], typeof(n.get(kv[0]))))
				print("%s.%s = %s" % [n.name, kv[0], n.get(kv[0])]))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(7.0).timeout
	Oleaje.asentar()
	var arbol := get_tree()
	var b := UtilesPruebas.barco(arbol)
	var mayor: Node = null
	for t in UtilesPruebas.telas(arbol):
		if str(t.get("nombre_malla")) == "vela_mayor":
			mayor = t
	if b == null or mayor == null:
		print("no hay barco o no hay mayor"); arbol.quit(1); return
	await UtilesPruebas.al_timon(arbol)
	await UtilesPruebas.estabilizar(arbol, 3.0)
	print("\n─── preparación: %s ───" % modo)
	match modo:
		"fondeado":
			await UtilesPruebas.estabilizar(arbol, PREPARAR)
		"libre":
			print("velocidad al acabar %.2f m/s" % await UtilesPruebas.navegar(arbol, PREPARAR,
				Vector3(1, 0, 0)))
		"libre_parado":
			# Navega igual, pero se para de través ANTES de ir a popa: separa lo que deja el haber
			# navegado de lo que hace la frenada durante la trasluchada.
			await UtilesPruebas.navegar(arbol, PREPARAR, Vector3(1, 0, 0))
			await UtilesPruebas.estabilizar(arbol, 8.0)
		"arriar_libre", "arriar_fondeado":
			b.set("anclado", modo == "arriar_fondeado")
			for i in 3:
				await UtilesPruebas.tecla(arbol, KEY_S)
				for f in 400:
					await arbol.process_frame
		_:
			print("modo desconocido"); arbol.quit(1); return
	await _foto(arbol, b, mayor, "al acabar la preparación")

	# El viento de `tela/popa_obenques` es (-0,34, 0, -0,94) en ejes del barco: viene de 160°.
	var beta := deg_to_rad(float(args[1]) if args.size() > 1 and not "=" in args[1] else 160.0)
	var dir := (b.global_transform.basis * Vector3(-sin(beta), 0.0, cos(beta))).normalized()
	print("viento en popa desde %.0f°" % rad_to_deg(beta))
	var t := 0.0
	var siguiente := 0.0
	while t < POPA:
		Viento.direccion_base = dir
		Viento.bamboleo_dir = 0.0
		Viento.variacion_fuerza = 0.0
		Viento.fuerza_base = 1.0
		b.set("anclado", true)
		t += arbol.root.get_process_delta_time()
		await arbol.process_frame
		if t >= siguiente:
			await _foto(arbol, b, mayor, "popa t=%4.1f" % t)
			siguiente += 1.0
	var peor := 0
	var cabos := {}
	for _k in 10:
		var c: Dictionary = await UtilesPruebas.jarcia_por_la_lona(arbol, b, mayor)
		if int(c["cruces"]) > peor:
			peor = int(c["cruces"]); cabos = c["por_cabo"]
		for _f in 6:
			await arbol.physics_frame
	print("RESULTADO %s: %d caras atravesadas %s, cajas rehechas a mano %s en %d frames de física"
		% [modo, peor, cabos, mayor.datos_depuracion().get("cajas_rehechas", "-"),
			Engine.get_physics_frames()])
	_donde_cruza(b, mayor)
	_los_de_dentro(b, mayor)
	# `reiniciar=capa|mascara|sacar`: con la lona ya metida, ¿sale si se rehace el contacto?
	for a in args:
		if a.begins_with("reiniciar="):
			await _reiniciar(arbol, b, mayor, a.trim_prefix("reiniciar="), dir)
	arbol.quit(0)


func _reiniciar(arbol: SceneTree, b: Node3D, mayor: Node, como: String, dir: Vector3) -> void:
	var muros := b.find_children("Lona_*", "StaticBody3D", true, false)
	var cuerpo: SoftBody3D = mayor.datos_depuracion()["cuerpo"]
	match como:
		"capa":
			for c in muros:
				(c as CollisionObject3D).collision_layer = 0
			await arbol.physics_frame
			await arbol.physics_frame
			for c in muros:
				(c as CollisionObject3D).collision_layer = 64
		"mascara":
			var m := cuerpo.collision_mask
			cuerpo.collision_mask = 0
			await arbol.physics_frame
			await arbol.physics_frame
			cuerpo.collision_mask = m
		"identidad":
			var rid := cuerpo.get_physics_rid()
			print("transformación del SoftBody en el servidor: %s"
				% PhysicsServer3D.soft_body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM))
			PhysicsServer3D.soft_body_set_transform(rid, Transform3D.IDENTITY)
		"copia":
			# Una cápsula nueva donde está cada muro, colgada de la raíz y quieta: separa el
			# contacto del motor de lo que hace `perchas_solidas` con sus cuerpos cada frame.
			for c in muros:
				var cs := (c.get_child(0) as CollisionShape3D)
				var st := StaticBody3D.new()
				st.collision_layer = 64
				st.collision_mask = 0
				var cs2 := CollisionShape3D.new()
				cs2.shape = cs.shape.duplicate()
				st.add_child(cs2)
				arbol.root.add_child(st)
				st.global_transform = (c as Node3D).global_transform * cs.transform
				(c as CollisionObject3D).collision_layer = 0
		"consulta":
			# ¿Ve el motor la lona dentro de la cápsula? La misma resolución estrecha que usan los
			# contactos (`solve_soft_body`), preguntada sin depender del par de la fase ancha.
			var esp := b.get_world_3d().direct_space_state
			for c in muros:
				var cs := (c.get_child(0) as CollisionShape3D)
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = cs.shape
				q.transform = (c as Node3D).global_transform * cs.transform
				q.collision_mask = cuerpo.collision_layer
				var r := esp.intersect_shape(q, 32)
				var quien := []
				for h in r:
					quien.append(str(h["collider"].name) if h["collider"] != null else str(h["rid"]))
				print("  %s ve: %s" % [c.name, quien])
			print("capa del SoftBody %d, máscara %d" % [cuerpo.collision_layer, cuerpo.collision_mask])
			# Control: una esfera de 5 cm CENTRADA en puntos de la lona, que tiene que verla seguro.
			var vistos := 0
			var probados := 0
			var no_vistos := []
			for i in range(0, mayor.datos_depuracion()["fijo"].size(), 20):
				var q := PhysicsShapeQueryParameters3D.new()
				var sf := SphereShape3D.new()
				sf.radius = 0.05
				q.shape = sf
				q.transform = Transform3D(Basis(), cuerpo.get_point_transform(i))
				q.collision_mask = cuerpo.collision_layer
				probados += 1
				if not esp.intersect_shape(q, 8).is_empty():
					vistos += 1
				else:
					no_vistos.append(i)
			print("control: la esfera ve la lona en %d de %d puntos; no en %s" % [vistos, probados, no_vistos])
		"espacio":
			# Sacar el cuerpo del espacio y volverlo a meter obliga al motor a rehacer su forma, y
			# con ella la caja con que entra en la fase ancha.
			var rid := cuerpo.get_physics_rid()
			var esp_rid := PhysicsServer3D.soft_body_get_space(rid)
			print("caja de la lona (servidor) antes: %s" % PhysicsServer3D.soft_body_get_bounds(rid))
			PhysicsServer3D.soft_body_set_space(rid, RID())
			PhysicsServer3D.soft_body_set_space(rid, esp_rid)
		"sacar":
			for c in muros:
				var p := c.get_parent()
				p.remove_child(c)
				p.add_child(c)
	var t := 0.0
	while t < 4.0:
		Viento.direccion_base = dir
		await arbol.process_frame
		t += arbol.root.get_process_delta_time()
	await _foto(arbol, b, mayor, "tras reiniciar (%s)" % como)


## Los puntos libres metidos en algún muro, del más hondo al menos, con sus coordenadas en ejes
## del muro (x de lado, z hacia proa; el cabo va en z = -(R - r)) y a qué altura del muro están.
func _los_de_dentro(b: Node3D, mayor: Node) -> void:
	var d: Dictionary = mayor.datos_depuracion()
	var cuerpo: SoftBody3D = d["cuerpo"]
	var fijo: PackedByteArray = d["fijo"]
	var filas := []
	for c in b.find_children("Lona_*", "StaticBody3D", true, false):
		var cs := c.get_child(0) as CollisionShape3D
		var cap := cs.shape as CapsuleShape3D
		var tr := (c as Node3D).global_transform * cs.transform
		var media := maxf(cap.height * 0.5 - cap.radius, 0.0)
		for i in fijo.size():
			if fijo[i] == 1:
				continue
			var q: Vector3 = tr.affine_inverse() * cuerpo.get_point_transform(i)
			var r := q.distance_to(Vector3(0.0, clampf(q.y, -media, media), 0.0)) - cap.radius
			if r < 0.0:
				filas.append([r, "  %s p%d hondo %.3f  lado %+.3f proa %+.3f  eje %+.2f/%.2f  vecinos fijos %d"
					% [c.name, i, -r, q.x, q.z, q.y, media, _vecinos_fijos(mayor, i)]])
	filas.sort_custom(func(a, z): return a[0] < z[0])
	print("dentro de los muros: %d" % filas.size())
	for f in filas:
		print(f[1])


func _vecinos_fijos(mayor: Node, i: int) -> int:
	var d: Dictionary = mayor.datos_depuracion()
	var cuerpo: SoftBody3D = d["cuerpo"]
	var fijo: PackedByteArray = d["fijo"]
	var idx: PackedInt32Array = cuerpo.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var n := 0
	for t in range(0, idx.size(), 3):
		if idx[t] == i or idx[t + 1] == i or idx[t + 2] == i:
			for k in 3:
				if fijo[idx[t + k]] == 1:
					n += 1
	return n


## Para cada cara que atraviesa un obenque: a qué altura del cabo (0 = mesa, 1 = tope) y dónde
## quedan sus tres puntos respecto al MURO de detrás de ese cabo — distancia a la superficie de
## la cápsula (negativo = dentro) y la coordenada a lo largo de su eje (fuera de ±media = pasa
## por encima o por debajo del muro).
func _donde_cruza(b: Node3D, mayor: Node) -> void:
	var d: Dictionary = mayor.datos_depuracion()
	var cuerpo: SoftBody3D = d["cuerpo"]
	var fijo: PackedByteArray = d["fijo"]
	var idx: PackedInt32Array = cuerpo.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var n := fijo.size()
	var p := PackedVector3Array()
	p.resize(n)
	for i in n:
		p[i] = cuerpo.get_point_transform(i)
	for mi in b.find_children("obenque*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var bajo := Vector3(0.0, INF, 0.0)
		var alto := Vector3(0.0, -INF, 0.0)
		for v in (m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var g: Vector3 = m.global_transform * v
			if g.y < bajo.y:
				bajo = g
			if g.y > alto.y:
				alto = g
		var muro: Array = []
		for c in b.find_children("Lona_" + m.name, "StaticBody3D", true, false):
			var cs := c.get_child(0) as CollisionShape3D
			var cap := cs.shape as CapsuleShape3D
			muro = [(c as Node3D).global_transform * cs.transform, cap.radius,
				maxf(cap.height * 0.5 - cap.radius, 0.0)]
		for t in range(0, idx.size(), 3):
			var x: Variant = Geometry3D.segment_intersects_triangle(bajo, alto,
					p[idx[t]], p[idx[t + 1]], p[idx[t + 2]])
			if x == null:
				continue
			var s := ((x as Vector3) - bajo).dot(alto - bajo) / (alto - bajo).length_squared()
			var txt := "  %s cara %d a %.2f del cabo (y=%.2f m):" % [m.name, t / 3, s, (x as Vector3).y]
			for k in 3:
				var i := idx[t + k]
				var linea := " p%d%s" % [i, "(ancla)" if fijo[i] == 1 else ""]
				if not muro.is_empty():
					var q: Vector3 = (muro[0] as Transform3D).affine_inverse() * p[i]
					var r := q.distance_to(Vector3(0.0, clampf(q.y, -muro[2], muro[2]), 0.0))
					linea += " sup %+.3f eje %+.2f/%.2f (lado %+.3f, proa %+.3f)" % [r - float(muro[1]),
						q.y, muro[2], q.x, q.z]
				txt += linea
			print(txt)


func _foto(arbol: SceneTree, b: Node3D, mayor: Node, que: String) -> void:
	var j: Dictionary = await UtilesPruebas.vela_en_jarcia(arbol, b, mayor)
	var c: Dictionary = await UtilesPruebas.jarcia_por_la_lona(arbol, b, mayor)
	var e: Dictionary = await UtilesPruebas.estiramiento(arbol, mayor)
	var lado := _lado_del_muro(b, mayor)
	que += "  dentro %d delante %d" % [lado[0], lado[1]]
	var v := (b as CharacterBody3D).velocity.length() if b is CharacterBody3D else 0.0
	print("%-24s vela %6.1f°  obenque %6.1f°  pasados %3d  caras %d %s  estira %.4f/%d  barco %.2f m/s rumbo %.1f°"
		% [que, j.get("az_vela", 0.0), j.get("az_obenque", 0.0), j.get("pasados", -1),
			c.get("cruces", -1), c.get("por_cabo", {}), e["medio"], e["malas"], v,
			rad_to_deg(b.global_rotation.y)])


## Puntos libres de la mayor DENTRO de algún muro de obenque y puntos DELANTE del cabo (a proa
## de su eje, en ejes del muro: z es la tangente hacia proa y el cabo va en z = -(R - r)), que
## es el lado en que la lona no debería estar nunca.
func _lado_del_muro(b: Node3D, mayor: Node) -> Array:
	var d: Dictionary = mayor.datos_depuracion()
	var cuerpo: SoftBody3D = d["cuerpo"]
	var fijo: PackedByteArray = d["fijo"]
	var muros := []
	for c in b.find_children("Lona_*", "StaticBody3D", true, false):
		var cs := c.get_child(0) as CollisionShape3D
		var cap := cs.shape as CapsuleShape3D
		muros.append([(c as Node3D).global_transform * cs.transform, cap.radius,
			maxf(cap.height * 0.5 - cap.radius, 0.0)])
	var dentro := 0
	var delante := 0
	for i in fijo.size():
		if fijo[i] == 1:
			continue
		var p := cuerpo.get_point_transform(i)
		for m in muros:
			var q: Vector3 = (m[0] as Transform3D).affine_inverse() * p
			if absf(q.y) > m[2]:
				continue
			var R: float = m[1]
			if Vector2(q.x, q.z).length() < R:
				dentro += 1
				break
			if q.z > -(R - 0.015) and absf(q.x) < R:
				delante += 1
				break
	return [dentro, delante]
