extends Node
## Verifica los parametros REALES en ejecucion y fotografia la mayor NAVEGANDO (no anclada).
@export var carpeta := ""
func _ready() -> void: _correr()
func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("vela_mayor"): sb = x as SoftBody3D
	print("RUNTIME mayor: mask=%d  rigidez=%.2f  masa=%.1f" % [sb.collision_mask, sb.linear_stiffness, sb.total_mass])
	# NO anclar: dejar navegar. Camara que sigue al barco desde babor.
	var cam := Camera3D.new(); add_child(cam); cam.fov = 55.0; cam.make_current()
	for t in 3:
		await get_tree().create_timer(4.0).timeout
		var o := b.global_position
		var ade := -b.global_transform.basis.z; var der := b.global_transform.basis.x
		cam.global_position = o - ade * 6.0 - der * 11.0 + Vector3.UP * 5.0
		cam.look_at(o - ade * 1.0 + Vector3.UP * 4.0, Vector3.UP)
		await get_tree().create_timer(0.3).timeout
		await _foto("navegando_%d.png" % t)
		print("foto %d: barco en %v velocidad~%s" % [t, o, b.get("velocidad")])
	get_tree().quit()
