extends SceneTree
func _init() -> void:
	for m in ["soft_body_move_point", "soft_body_get_point_global_position",
			"soft_body_set_transform", "soft_body_get_bounds"]:
		print("PhysicsServer3D.%s : %s" % [m, PhysicsServer3D.has_method(m)])
	var sb := SoftBody3D.new()
	for m in ["set_point_pinned", "is_point_pinned", "get_point_transform"]:
		print("SoftBody3D.%s : %s" % [m, sb.has_method(m)])
	print("propiedades utiles: ", sb.get_property_list().map(func(x): return x["name"]).filter(
		func(nm: String): return nm.contains("stiff") or nm.contains("precis") or nm.contains("mass") or nm.contains("damp") or nm.contains("drag") or nm.contains("press")))
	sb.free()
	quit()
