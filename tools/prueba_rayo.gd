extends Node
## ¿Existen de verdad las formas en el espacio de física? Lanza un rayo hacia abajo sobre la
## cubierta y lista lo que hay, con capas y transforms.
func _ready() -> void: _correr()
func _correr() -> void:
	await get_tree().create_timer(2.5).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	await get_tree().create_timer(1.0).timeout
	var col := b.find_child("Colisiones", false, false) as StaticBody3D
	print("StaticBody: %s  capa=%d  mascara=%d  hijos=%d  en_arbol=%s" %
		[col.name, col.collision_layer, col.collision_mask, col.get_child_count(), col.is_inside_tree()])
	print("  global origen %v   barco global %v" % [col.global_position, b.global_position])
	var n := 0
	for c in col.get_children():
		if c is CollisionShape3D and n < 4:
			var cs := c as CollisionShape3D
			print("  %s  forma=%s  desactivada=%s  global %v" % [cs.name, cs.shape.get_class(), cs.disabled, cs.global_position])
			n += 1
	# rayo desde 4 m sobre la cubierta hacia abajo
	var espacio := b.get_world_3d().direct_space_state
	var desde := b.global_transform * Vector3(0, 5.0, 0)
	var hasta := b.global_transform * Vector3(0, -1.0, 0)
	var par := PhysicsRayQueryParameters3D.create(desde, hasta)
	par.collide_with_areas = false
	var r := espacio.intersect_ray(par)
	print("rayo de %v a %v -> %s" % [desde, hasta, r])
	# y qué hay en un punto justo sobre la cubierta
	var pq := PhysicsPointQueryParameters3D.new()
	pq.position = b.global_transform * Vector3(0, 1.70, 0)
	pq.collide_with_bodies = true
	var lista := espacio.intersect_point(pq, 8)
	print("punto sobre cubierta: %d cuerpos" % lista.size())
	for x in lista:
		print("   %s" % [(x["collider"] as Node).name])
	get_tree().quit()
