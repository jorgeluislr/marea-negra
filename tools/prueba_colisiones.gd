extends Node
## ¿Se puede andar por cubierta y no caerse? Suelta al jugador sobre la cubierta del barco
## activo y mira dónde acaba, si toca suelo, y si la barrera lo retiene al empujarlo afuera.
@export var carpeta := ""

func _ready() -> void: _correr()

func _correr() -> void:
	await get_tree().create_timer(2.5).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	var col := b.find_child("Colisiones", false, false) as StaticBody3D
	if col == null:
		print("SIN COLISIONES"); get_tree().quit(1); return
	var formas := 0
	var suelos := 0
	for c in col.get_children():
		if c is CollisionShape3D:
			formas += 1
			if (c as CollisionShape3D).shape is ConcavePolygonShape3D: suelos += 1
	print("colisiones: %d formas, %d de malla" % [formas, suelos])
	# suelta al jugador sobre la cubierta, como hijo del barco para que lo lleve consigo
	var jug: CharacterBody3D = (load("res://scenes/character/player.tscn") as PackedScene).instantiate()
	b.add_child(jug)
	jug.position = Vector3(0, 4.5, 0)
	await get_tree().create_timer(2.0).timeout
	print("tras caer: y local %.3f  en el suelo=%s" % [jug.position.y, jug.is_on_floor()])
	# empújalo hacia babor a ver si la barrera lo para
	for i in 120:
		jug.velocity.x = -6.0
		await get_tree().physics_frame
	print("empujado a babor: x local %.3f  y %.3f  en el suelo=%s" % [jug.position.x, jug.position.y, jug.is_on_floor()])
	for i in 120:
		jug.velocity.x = 6.0
		await get_tree().physics_frame
	print("empujado a estribor: x local %.3f  y %.3f" % [jug.position.x, jug.position.y])
	for i in 150:
		jug.velocity.z = -8.0
		await get_tree().physics_frame
	print("empujado a proa: z local %.3f  y %.3f" % [jug.position.z, jug.position.y])
	get_tree().quit()
