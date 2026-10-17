extends Node

## Qué le pasa al personaje cuando se cae por la borda: si flota, si el barco se lo lleva, si
## nada y si puede volver a bordo.
##
## Las cuatro se rompen por separado y ninguna avisa. La que más: el personaje va a bordo como
## HIJO del casco —para que la cubierta lo arrastre al navegar—, así que en el agua seguiría
## viajando con el barco a nueve nudos como si nada.
##
## La flotación se mide contra la OLA de debajo (`Oleaje.altura_en`), no contra una altura fija:
## el mar sube y baja 1,6 m y un naufrago quieto respecto al cero del mundo estaria haciendo lo
## contrario de flotar.
##
##     godot --path . tools/hombre_al_agua.tscn


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

	print("\n─── hombre al agua ───")
	# Por la borda: se le deja caer desde fuera del costado.
	jug.global_position = b.global_transform * Vector3(6.0, 4.0, 0.0)
	jug.velocity = Vector3.ZERO
	var t := 0.0
	while t < 6.0:
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
	print("nadando: %s, y cuelga de '%s'"
		% [str(jug.call("nadando")), jug.get_parent().name])

	# Flotación: cuánto se aparta de la ola de debajo, medido un rato.
	var peor := 0.0
	var medio := 0.0
	var n := 0
	t = 0.0
	while t < 6.0:
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		var mar: float = Oleaje.altura_en(Vector2(jug.global_position.x, jug.global_position.z))
		var d: float = absf(jug.global_position.y - mar)
		peor = maxf(peor, d)
		medio += d
		n += 1
	print("flota a %.2f m de la ola de media (peor %.2f)" % [medio / maxf(n, 1), peor])

	# ¿Se lo lleva el barco? Con el casco navegando, la distancia tiene que crecer.
	var d0 := jug.global_position.distance_to(b.global_position)
	t = 0.0
	while t < 8.0:
		b.set("anclado", false)
		b.set("gobierno", true)
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
	var d1 := jug.global_position.distance_to(b.global_position)
	print("el barco navega 8 s y se aleja de %.1f a %.1f m  ->  %s"
		% [d0, d1, "lo deja atrás" if d1 - d0 > 20.0 else "SE LO LLEVA CONSIGO"])
	b.set("anclado", true)

	# ¿Nada? Con la W, y contra el agua, no contra el mundo.
	var p0 := jug.global_position
	var e := InputEventKey.new()
	e.keycode = KEY_W
	e.physical_keycode = KEY_W
	e.pressed = true
	Input.parse_input_event(e)
	t = 0.0
	while t < 5.0:
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
	e.pressed = false
	Input.parse_input_event(e)
	var avance := Vector2(jug.global_position.x - p0.x, jug.global_position.z - p0.z).length()
	print("nadando 5 s avanza %.2f m (%.2f m/s)" % [avance, avance / 5.0])

	# ¿Vuelve a bordo? Pegado al costado, mirando al barco, y E.
	jug.global_position = b.global_transform * Vector3(3.0, 1.5, 0.0)
	jug.look_at(b.global_position + Vector3.UP * 1.5, Vector3.UP)
	for i in 30:
		await get_tree().physics_frame
	await UtilesPruebas.tecla(get_tree(), KEY_E)
	for i in 30:
		await get_tree().physics_frame
	var sobre := jug.global_position.y - b.global_position.y
	print("tras pulsar E cuelga de '%s', a %.2f m sobre el barco  ->  %s"
		% [jug.get_parent().name, sobre,
			"vuelve a bordo" if jug.get_parent() == b else "SIGUE EN EL AGUA"])
	get_tree().quit(0)
