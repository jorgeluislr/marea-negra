extends Node

## Qué encuentra una bala que llega de través a una balandra, rayo a rayo, pintado como un mapa
## de caracteres (proa a la izquierda, arriba lo alto):
##
##     .  nada                 C  la caja del `CharacterBody3D` (capa 2)
##     H  el casco (dianas)    P  un palo o percha (capa 5)   J  jarcia (capa 6)
##     V  una vela (`SoftBody3D`, por sus bits de viento)     ?  cualquier otra cosa
##
## Se hizo para dos preguntas antes de montar las zonas de daño: si un rayo VE las velas físicas
## (`intersect_shape` no devuelve nunca un `SoftBody3D`, y no estaba claro que `intersect_ray`
## sí), y cuánto aire hay dentro de la caja del barco —la esquina de proa, lo que va por encima
## del casco—, que es donde una bala "toca" sin tocar madera.
##
##     godot --path . tools/mapa_de_dianas.tscn

const ESPERA := 5.0
const PASO := 0.25
## Los bits de viento de las telas (capas 25-32), que es por lo único que se distingue una vela.
const VIENTO := 0xFF << 24


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func():
		push_error("se acabó el tiempo"); get_tree().quit(1))
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	var b := esc.instantiate() as Node3D
	b.set("altura_mar", 0.0)
	add_child(b)
	b.set("anclado", true)
	b.call("set_vela_delantera", true)
	b.call("set_vela_trasera", true)
	Viento.direccion_base = Vector3(-1, 0, 0)
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	await get_tree().create_timer(ESPERA).timeout
	await get_tree().physics_frame
	var esp := b.get_world_3d().direct_space_state
	var cs := b.get_node(^"CollisionShape3D") as CollisionShape3D
	var caja := (cs.shape as BoxShape3D).size
	var z0 := cs.position.z - caja.z * 0.5 - 1.5
	var z1 := cs.position.z + caja.z * 0.5 + 1.5
	print("caja %.2f x %.2f x %.2f centrada en %s; columnas de %.2f m de proa (z %.1f) a popa (z %.1f)"
		% [caja.x, caja.y, caja.z, cs.position, PASO, z0, z1])
	var cuenta := {}
	var y := 12.0
	while y >= -0.5:
		var linea := "%5.2f " % y
		var z := z0
		while z <= z1:
			var desde := b.to_global(Vector3(25.0, y, z))
			var hasta := b.to_global(Vector3(-25.0, y, z))
			var c := _que_toca(esp, desde, hasta)
			linea += c
			cuenta[c] = int(cuenta.get(c, 0)) + 1
			z += PASO
		print(linea)
		y -= PASO
	print("recuento: %s" % cuenta)
	get_tree().quit(0)


func _que_toca(esp: PhysicsDirectSpaceState3D, desde: Vector3, hasta: Vector3) -> String:
	var par := PhysicsRayQueryParameters3D.create(desde, hasta, 2 | 16 | 32 | 128 | VIENTO)
	var g := esp.intersect_ray(par)
	if g.is_empty():
		return "."
	var o: Object = g.get("collider")
	if o is SoftBody3D:
		return "V"
	if o is CharacterBody3D:
		return "C"
	if o is CollisionObject3D:
		var capa := (o as CollisionObject3D).collision_layer
		if capa & 128:
			return "H"
		if capa & 16:
			return "P"
		if capa & 32:
			return "J"
	return "?"
