extends Node

## Si el personaje puede o no ocupar el sitio del mástil, de las perchas y de la jarcia.
##
## Se pregunta a la FÍSICA, no a la geometría: se toma la cápsula del personaje, se pone en el
## centro de cada forma de `perchas_solidas` y se consulta qué hay ahí con la máscara del jugador
## (5: mundo y cubierta). Si no sale nada, ese palo es humo para él.
##
## La primera versión de esta herramienta medía distancias al centro de la CAJA de cada malla y
## no valía para nada: el mástil está inclinado, así que su eje a la altura del pecho no pasa por
## el centro de su caja, y además no tiene ni un vértice entre los 2 y los 8,5 m de altura —los
## anillos están arriba—, de modo que el radio salía el de por defecto. Daba "LO ATRAVIESA" en
## tres piezas de cuatro con los colisionadores perfectamente puestos.
##
## Y luego se anda de verdad contra el mástil, con la W del juego, para ver que `move_and_slide`
## lo para: que la forma esté en la capa buena y que el personaje se pare no son lo mismo.
##
##     godot --path . tools/chocar_con_el_palo.tscn

## Máscara del jugador, copiada de `player.tscn`: capa 1 (mundo) y capa 3 (cubierta).
const MASCARA := 5
const EMPUJAR := 5.0


func _ready() -> void:
	get_tree().create_timer(200.0).timeout.connect(func(): get_tree().quit(1))
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

	print("\n─── chocar con el palo ───   (máscara del jugador: %d)" % MASCARA)
	var espacio := b.get_world_3d().direct_space_state
	var sin_cuerpo := []
	var piezas := 0
	for n in b.find_children("Percha_*", "StaticBody3D", true, false):
		var cuerpo := n as StaticBody3D
		piezas += 1
		var tocadas := 0
		var total := 0
		for h in cuerpo.get_children():
			var cs := h as CollisionShape3D
			if cs == null:
				continue
			total += 1
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = forma
			q.transform = Transform3D(Basis(), cs.global_transform.origin)
			q.collision_mask = MASCARA
			q.exclude = [jug.get_rid()]
			for golpe in espacio.intersect_shape(q, 16):
				if (golpe["collider"] as Node) == cuerpo:
					tocadas += 1
					break
		if tocadas < total:
			sin_cuerpo.append("%s (%d de %d)" % [cuerpo.name, tocadas, total])
	print("%d piezas de aparejo; el personaje choca con TODAS sus formas: %s"
		% [piezas, "sí" if sin_cuerpo.is_empty() else "NO -> " + ", ".join(sin_cuerpo)])

	# Y ahora andando de verdad. El objetivo es la forma del mástil que cae a la altura del pecho.
	var palo := b.find_child("Percha_mastil_v3", true, false) as StaticBody3D
	var y: float = jug.global_position.y
	var mejor: CollisionShape3D = null
	for h in palo.get_children():
		var cs := h as CollisionShape3D
		if cs != null and (mejor == null
				or absf(cs.global_transform.origin.y - y) < absf(mejor.global_transform.origin.y - y)):
			mejor = cs
	var meta := mejor.global_transform.origin
	var radio: float = (mejor.shape as CapsuleShape3D).radius
	var radial := (jug.global_position - meta)
	radial.y = 0.0
	radial = radial.normalized()
	jug.global_position = meta + radial * 3.0 + Vector3.UP * (y - meta.y)
	jug.look_at(meta + Vector3.UP * (y - meta.y), Vector3.UP)
	jug.velocity = Vector3.ZERO
	for i in 20:
		await get_tree().physics_frame
	var cerca := _plano(jug.global_position, meta)
	var e := InputEventKey.new()
	e.keycode = KEY_W
	e.physical_keycode = KEY_W
	e.pressed = true
	Input.parse_input_event(e)
	var t := 0.0
	var contra := ""
	while t < EMPUJAR:
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		cerca = minf(cerca, _plano(jug.global_position, meta))
		# Con qué choca de verdad, que es lo inequívoco: la distancia al eje engaña porque el palo
		# cae 9,47° a popa y la cápsula que lo para no es la que se tomó de referencia.
		for i in jug.get_slide_collision_count():
			var c := (jug.get_slide_collision(i).get_collider() as Node)
			if c != null and String(c.name).begins_with("Percha_"):
				contra = String(c.name)
	e.pressed = false
	Input.parse_input_event(e)
	print("andando contra el mástil (cápsula de r=%.3f a y=%.2f): llega a %.3f m de ese eje, y choca contra %s"
		% [radio, meta.y, cerca, contra if contra != "" else "NADA -> LO ATRAVIESA"])
	get_tree().quit(0)


func _plano(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
