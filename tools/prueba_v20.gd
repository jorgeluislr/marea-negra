extends Node
## Traza el vértice que salta (20 del foque) durante los primeros frames del arriado, y si es
## fijo o libre, para ver de dónde sale el tirón.
func _ready() -> void: _correr()
func _correr() -> void:
	await get_tree().create_timer(4.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	var esq: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
	var sb: SoftBody3D = null; var nodo: Node = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("foque"): sb = x as SoftBody3D
	# el nodo de control de la vela fisica del foque
	for x in b.get_children():
		if (x as Node).name.begins_with("VelaFisica") and x.get("nombre_malla")=="foque": nodo = x
	var mi := b.find_children("foque","MeshInstance3D",true,false)[0] as MeshInstance3D
	var arr := mi.mesh.surface_get_arrays(0)
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	print("vertice 20: azul(anclado siempre)=%.2f  pinned=%s" % [cols[20].b, sb.is_point_pinned(20)])
	await get_tree().create_timer(2.0).timeout
	var g := b.global_transform.affine_inverse()
	print("--- justo antes de arriar ---")
	print("v20 pos %v  pinned=%s" % [g*sb.get_point_transform(20), sb.is_point_pinned(20)])
	b.set("vela_delantera", false); b.emit_signal("vela_delantera_cambiada", false)
	for f in 6:
		await get_tree().physics_frame
		print("frame %d: v20 %v  pinned=%s" % [f, g*sb.get_point_transform(20), sb.is_point_pinned(20)])
	get_tree().quit()
