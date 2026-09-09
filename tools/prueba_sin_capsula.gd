extends Node
## Quita a la mayor la colisión con las cápsulas de palo (mask=0) y fotografía, para ver si el
## "ángulo que empuja la vela" lo causaba la cápsula de la botavara.
@export var carpeta := ""
func _ready() -> void: _correr()
func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("vela_mayor"): sb = x as SoftBody3D
	sb.collision_mask = 0   # sin colisión con nada
	print("mayor mask puesto a 0")
	await get_tree().create_timer(4.0).timeout
	var cam := Camera3D.new(); add_child(cam); cam.fov = 55.0; cam.make_current()
	var o := b.global_position
	var ade := -b.global_transform.basis.z; var der := b.global_transform.basis.x
	cam.global_position = o - ade * 7.0 - der * 8.0 + Vector3.UP * 4.5
	cam.look_at(o - ade * 2.0 + Vector3.UP * 3.0, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await _foto("sin_capsula.png")
	get_tree().quit()
