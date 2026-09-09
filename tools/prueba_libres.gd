extends Node
## Muestra TODOS los vértices de la mayor: rojo=anclado, amarillo=libre, y mide cuántos libres
## hay en la zona baja (el pie que se dobla). Para confirmar la observación del usuario.
@export var carpeta := ""
func _ready() -> void: _correr()
func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
func _puntos(padre: Node, ps: Array, col: Color, r: float) -> void:
	if ps.is_empty(): return
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
	var e := SphereMesh.new(); e.radius = r; e.height = r*2; mm.mesh = e
	mm.instance_count = ps.size()
	for i in ps.size(): mm.set_instance_transform(i, Transform3D(Basis(), ps[i]))
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm
	var mat := StandardMaterial3D.new(); mat.albedo_color = col; mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmi.material_override = mat; padre.add_child(mmi)
func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	Viento.direccion = Vector3(1,0,0.4).normalized(); Viento.fuerza = 1.2
	await get_tree().create_timer(5.0).timeout
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("vela_mayor"): sb = x as SoftBody3D
	var mi := b.find_children("vela_mayor","MeshInstance3D",true,false)[0] as MeshInstance3D
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var anc := []; var lib := []
	var g := b.global_transform
	# altura de la botavara (y más baja del paño)
	var ymin := 999.0
	for k in vs.size(): ymin = minf(ymin, (sb.get_point_transform(k)).y)
	var lib_bajos := 0; var anc_bajos := 0
	for k in cols.size():
		var p := sb.get_point_transform(k)
		if cols[k].b > 0.5:
			anc.append(p)
			if p.y < ymin + 1.5: anc_bajos += 1
		else:
			lib.append(p)
			if p.y < ymin + 1.5: lib_bajos += 1
	print("zona baja (<1.5m sobre la botavara): %d anclados, %d libres" % [anc_bajos, lib_bajos])
	print("total: %d anclados, %d libres" % [anc.size(), lib.size()])
	_puntos(get_tree().current_scene, anc, Color(1,0,0), 0.05)
	_puntos(get_tree().current_scene, lib, Color(1,1,0), 0.035)
	var cam := Camera3D.new(); add_child(cam); cam.fov = 48.0; cam.make_current()
	var o := b.global_position
	var ade := -b.global_transform.basis.z; var der := b.global_transform.basis.x
	cam.global_position = o - ade * 5.0 - der * 8.0 + Vector3.UP * 4.0
	cam.look_at(o - ade * 1.5 + Vector3.UP * 3.2, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await _foto("libres_pie.png")
	get_tree().quit()
