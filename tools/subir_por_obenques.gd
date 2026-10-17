extends Node

## Si el personaje puede ponerse en los obenques y subir, o si la barrera de la regala se lo come.
##
## Dos medidas, porque son dos fallos distintos:
##
##  - **¿CABE?** Se pone la cápsula del personaje en el plano de los flechastes, a la altura de la
##    regala, y se pregunta a la física qué hay ahí con su máscara. Si contesta la barrera, no hay
##    por dónde entrar y lo demás da igual.
##  - **¿SUBE?** Se le deja empujando hacia fuera con la W y saltando, y se anota lo más alto que
##    llega sobre la regala y en qué se apoyó.
##
## El sitio se saca de las propias mallas de la jarcia, no de números a mano: los flechastes de
## esta balandra caen en x 1,77-1,83 y la barrera arranca en 1,87.
##
##     godot --path . tools/subir_por_obenques.tscn

const MASCARA := 5
const RADIO_JUGADOR := 0.40
const TREPAR := 12.0


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	await get_tree().create_timer(8.0).timeout
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	b.set("anclado", true)
	await UtilesPruebas.tecla(get_tree(), KEY_F)
	for i in 60:
		await get_tree().process_frame
	var jug := b.find_child("Player", false, false) as CharacterBody3D
	if jug == null:
		print("no baja a cubierta"); get_tree().quit(1); return
	var forma := (jug.find_child("CollisionShape3D", false, false) as CollisionShape3D).shape

	# Dónde está la escala de flechastes, en ejes del barco.
	var al_barco := b.global_transform.affine_inverse()
	var caja := AABB()
	var primera := true
	for n in b.find_children("flechaste_e_*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var c := (al_barco * mi.global_transform) * mi.mesh.get_aabb()
		caja = c if primera else caja.merge(c)
		primera = false
	if primera:
		print("no hay flechastes"); get_tree().quit(1); return
	var centro := caja.get_center()
	print("\n─── subir por los obenques ───")
	print("la escala de estribor va de x %.3f a %.3f, y de %.2f a %.2f"
		% [caja.position.x, caja.position.x + caja.size.x,
			caja.position.y, caja.position.y + caja.size.y])

	# --- ¿CABE? Peldano a peldano, y POR FUERA: se sube a los obenques desde la regala con el
	# cuerpo hacia el mar y la escala contra el pecho, como en un barco de verdad. Eso quiere decir
	# que el personaje tiene que caber ENTERO por fuera del cabo --su diámetro, no su radio--, y
	# no basta con que la barrera deje de morder el peldano.
	#
	# Probar UN punto no vale: al pie de la escala cabía ya antes y ocho peldanos más arriba
	# también, y esa media medida es la que haría descartar la barrera.
	print("%-18s %8s %8s %8s   %s"
		% ["peldano", "x fuera", "y", "z", "que estorba al que sube POR FUERA"])
	var bloqueados := 0
	var peldanos := 0
	for n in b.find_children("flechaste_e_*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var c := (al_barco * mi.global_transform) * mi.mesh.get_aabb()
		var p := c.get_center()
		peldanos += 1
		# Hacia fuera: en la banda de estribor, +X del barco.
		# El GRUESO del cabo, no su largo: un flechaste mide 1,44 m de punta a punta y 6 cm de
		# grueso, y con el maximo de la caja el punto de prueba se iba 70 cm mar adentro.
		var radio_cabo: float = minf(minf(c.size.x, c.size.y), c.size.z) * 0.5
		var fuera := p + Vector3(RADIO_JUGADOR + radio_cabo, 0.0, 0.0)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = forma
		q.transform = Transform3D(Basis(), b.global_transform * fuera)
		q.collision_mask = MASCARA
		q.exclude = [jug.get_rid()]
		var estorban := []
		for golpe in b.get_world_3d().direct_space_state.intersect_shape(q, 32):
			var col := golpe["collider"] as CollisionObject3D
			# La jarcia no estorba: es justo a lo que se agarra. Y del casco hay que saber QUE
			# forma es: la borda es la regala, madera de verdad, y que estorbe es correcto; la
			# barrera es un invento nuestro para que nadie se caiga, y esa si se puede apartar.
			if String(col.name).begins_with("Percha_"):
				continue
			var due := col.shape_owner_get_owner(col.shape_find_owner(int(golpe["shape"])))
			var nom: String = String((due as Node).name) if due != null else String(col.name)
			if not estorban.has(nom):
				estorban.append(nom)
		if not estorban.is_empty():
			bloqueados += 1
		print("%-18s %8.3f %8.3f %8.3f   %s"
			% [mi.name, fuera.x, fuera.y, fuera.z,
				"libre" if estorban.is_empty() else ", ".join(estorban)])
	print("%d peldanos de %d con algo del casco encima
" % [bloqueados, peldanos])

	# --- ¿SUBE? Con TRES figuras de personaje, porque la forma es lo que decide si se apoya en un
	# peldano: la capsula tiene los pies redondos y rueda fuera del cabo, mientras que una caja o
	# un cilindro apoyan en plano y el contacto sale con la normal vertical, que es lo que pone
	# `is_on_floor()` en true y lo que deja volver a saltar.
	var figuras := {}
	var cap := CapsuleShape3D.new()
	cap.radius = RADIO_JUGADOR
	cap.height = 1.8
	figuras["capsula (la de hoy)"] = cap
	var cja := BoxShape3D.new()
	cja.size = Vector3(RADIO_JUGADOR * 2.0, 1.8, RADIO_JUGADOR * 2.0)
	figuras["caja"] = cja
	var cil := CylinderShape3D.new()
	cil.radius = RADIO_JUGADOR
	cil.height = 1.8
	figuras["cilindro"] = cil

	# El peldano mas bajo: es desde donde se empieza.
	var bajo := Vector3.INF
	for n in b.find_children("flechaste_e_*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var c := ((al_barco * mi.global_transform) * mi.mesh.get_aabb()).get_center()
		if c.y < bajo.y:
			bajo = c
	var forma_nodo := jug.find_child("CollisionShape3D", false, false) as CollisionShape3D
	# 1) ¿SE QUEDA DE PIE en un peldano? Es la pregunta de verdad: la trepada mezcla apoyarse con
	# saltar, y si no se sostiene quieto encima de un cabo, lo demás no importa. Se le posa con los
	# pies sobre la cara de arriba del peldano y se le deja caer sin tocar ninguna tecla.
	var alto_libre := Vector3.INF
	for n in b.find_children("flechaste_e_04", "MeshInstance3D", true, false):
		alto_libre = ((al_barco * (n as MeshInstance3D).global_transform)
			* (n as MeshInstance3D).mesh.get_aabb()).get_center()
	print("
%-22s %12s %12s %10s" % ["figura", "cae (m)", "queda en y", "de pie"])
	for nombre in figuras:
		forma_nodo.shape = figuras[nombre]
		await _posarse(b, jug, al_barco, alto_libre, nombre)

	# 2) CON EL MODO TREPAR: se pone junto a la escala mirando a ella y se le mantiene la W. Es la
	# medida que importa; las otras dos estan para que no se vuelva a intentar arreglarlo con la
	# figura del personaje ni con los colisionadores.
	forma_nodo.shape = figuras["capsula (la de hoy)"]
	var esc: Node = null
	for n in b.find_children("Escala_*", "Area3D", false, false):
		if String(n.name).ends_with("_e"):
			esc = n
	if esc == null:
		print("
NO hay EscalaJarcia montada")
	else:
		var pie2 := Vector3(bajo.x - 0.7, bajo.y + 0.2, bajo.z)
		jug.global_position = b.global_transform * pie2
		jug.look_at(b.global_transform * Vector3(bajo.x + 2.0, pie2.y, bajo.z), Vector3.UP)
		jug.velocity = Vector3.ZERO
		for i in 30:
			await get_tree().physics_frame
		var y0: float = (al_barco * jug.global_position).y
		var e := InputEventKey.new()
		e.keycode = KEY_W
		e.physical_keycode = KEY_W
		e.pressed = true
		Input.parse_input_event(e)
		var t := 0.0
		var alto := y0
		var enganchado := false
		while t < 10.0:
			await get_tree().physics_frame
			t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
			alto = maxf(alto, (al_barco * jug.global_position).y)
			if jug.has_method("trepando") and bool(jug.call("trepando")):
				enganchado = true
		e.pressed = false
		Input.parse_input_event(e)
		print("
con el modo trepar: %s, sube %.2f m (de y %.2f a %.2f) en 10 s"
			% ["se engancha" if enganchado else "NO SE ENGANCHA", alto - y0, y0, alto])

	# 3) Y trepando a pelo desde cubierta, que es lo que hacia antes el jugador.
	print("
%-22s %10s %10s   %s" % ["figura", "sube (m)", "llega a y", "se apoya en"])
	for nombre in figuras:
		forma_nodo.shape = figuras[nombre]
		await _trepar(b, jug, al_barco, bajo, nombre)
	get_tree().quit(0)


## Posa al personaje encima de un peldano y mira si se queda o resbala.
func _posarse(b: Node3D, jug: CharacterBody3D, al_barco: Transform3D, peldano: Vector3,
		nombre: String) -> void:
	var y0: float = peldano.y + 0.92
	jug.global_position = b.global_transform * Vector3(peldano.x, y0, peldano.z)
	jug.velocity = Vector3.ZERO
	var t := 0.0
	while t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
	var y1: float = (al_barco * jug.global_position).y
	print("%-22s %12.3f %12.2f %10s"
		% [nombre, y0 - y1, y1, "sí" if jug.is_on_floor() else "NO"])


## Deja al personaje al pie de la escala empujando hacia ella y saltando, y anota cuanto sube.
##
## Se arranca desde la CUBIERTA y no ya por fuera: fuera no hay suelo y se cae antes de empezar
## --medido, aparecia en y 2,38 y acababa en el agua en los 30 frames de asiento--, asi que lo
## que se mide asi es la caida, no la trepada.
func _trepar(b: Node3D, jug: CharacterBody3D, al_barco: Transform3D, bajo: Vector3,
		nombre: String) -> void:
	var pie := Vector3(bajo.x - 0.9, bajo.y, bajo.z)
	jug.global_position = b.global_transform * pie
	jug.look_at(b.global_transform * Vector3(pie.x + 2.0, pie.y, pie.z), Vector3.UP)
	jug.velocity = Vector3.ZERO
	for i in 30:
		await get_tree().physics_frame
	var y0: float = (al_barco * jug.global_position).y
	var alto := y0
	var apoyos := {}
	for k in [KEY_W, KEY_SPACE]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = true
		Input.parse_input_event(e)
	var t := 0.0
	while t < TREPAR:
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		alto = maxf(alto, (al_barco * jug.global_position).y)
		for i in jug.get_slide_collision_count():
			var c := jug.get_slide_collision(i).get_collider() as Node
			if c != null and String(c.name).begins_with("Percha_flechaste"):
				apoyos[String(c.name).substr(17)] = true
	for k in [KEY_W, KEY_SPACE]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = false
		Input.parse_input_event(e)
	var l := apoyos.keys()
	l.sort()
	print("%-22s %10.3f %10.2f   %s" % [nombre, alto - y0, alto, ", ".join(l)])
