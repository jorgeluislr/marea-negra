extends SceneTree
func _init() -> void:
	var sb := SoftBody3D.new()
	print("SoftBody3D.get_physics_rid : %s" % sb.has_method("get_physics_rid"))
	for m in sb.get_method_list().map(func(x): return x["name"]):
		if String(m).contains("rid") or String(m).contains("physics"):
			print("   metodo: %s" % m)
	sb.free()
	quit()
