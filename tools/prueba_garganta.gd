extends Node
## Foto de la mayor izada desde proa-babor, encuadrando la garganta, para ver si desaparece el
## triángulo rígido.
@export var carpeta := ""
func _ready() -> void: _correr()
func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
func _correr() -> void:
	await get_tree().create_timer(6.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	await get_tree().create_timer(3.0).timeout
	var cam := Camera3D.new(); add_child(cam); cam.fov = 55.0; cam.make_current()
	var o := b.global_position
	var ade := -b.global_transform.basis.z
	var der := b.global_transform.basis.x
	cam.global_position = o + ade * 11.0 - der * 6.0 + Vector3.UP * 4.5
	cam.look_at(o + ade * 3.0 + Vector3.UP * 3.5, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await _foto("garganta_proa.png")
	# y un plano medio de toda la vela desde babor
	# el pie de la mayor a lo largo de la botavara, desde babor-popa y algo elevado
	cam.global_position = o - ade * 7.0 - der * 8.0 + Vector3.UP * 4.5
	cam.look_at(o - ade * 2.0 + Vector3.UP * 3.0, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await _foto("pie_mayor.png")
	get_tree().quit()
