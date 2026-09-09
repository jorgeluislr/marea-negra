extends Node
## Pone una esfera roja en cada vértice anclado de la mayor, sobre la vela ya deformada, y
## fotografía. Así se ve el patrón de anclaje real y se puede correlacionar con el pliegue.
@export var carpeta := ""
func _ready() -> void: _correr()
func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
func _correr() -> void:
	await get_tree().create_timer(4.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("vela_mayor"): sb = x as SoftBody3D
	var mi := b.find_children("vela_mayor","MeshInstance3D",true,false)[0] as MeshInstance3D
	var cols: PackedColorArray = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	await get_tree().create_timer(3.0).timeout
	var esf := SphereMesh.new(); esf.radius = 0.08; esf.height = 0.16
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(1,0,0); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = esf
	var pin := []
	for k in cols.size():
		if cols[k].b > 0.5: pin.append(k)
	mm.instance_count = pin.size()
	for i in pin.size():
		mm.set_instance_transform(i, Transform3D(Basis(), sb.get_point_transform(pin[i])))
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.material_override = mat
	get_tree().current_scene.add_child(mmi)
	print("anclas dibujadas: %d" % pin.size())
	var cam := Camera3D.new(); add_child(cam); cam.fov = 50.0; cam.make_current()
	var o := b.global_position
	var ade := -b.global_transform.basis.z; var der := b.global_transform.basis.x
	cam.global_position = o - ade * 6.0 - der * 9.0 + Vector3.UP * 4.5
	cam.look_at(o - ade * 1.5 + Vector3.UP * 3.5, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await _foto("anclas_lado.png")
	cam.global_position = o + ade * 2.0 - der * 3.0 + Vector3.UP * 7.0
	cam.look_at(o - ade * 3.0 + Vector3.UP * 3.0, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await _foto("anclas_arriba.png")
	get_tree().quit()
