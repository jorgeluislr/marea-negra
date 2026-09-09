extends SceneTree
## Comprueba que el timón llega a Godot con su material horneado y una sola capa UV.

func _initialize() -> void:
	var b: Node3D = (load("res://scenes/barcos/balandra.tscn") as PackedScene).instantiate()
	for nombre in ["timon_retopo", "bitas_botalon", "cabilla_botalon", "tope_botalon", "cania_timon"]:
		var l := b.find_children(nombre, "MeshInstance3D", true, false)
		if l.is_empty(): print(nombre, ": NO ESTA"); continue
		var mi := l[0] as MeshInstance3D
		var arr := mi.mesh.surface_get_arrays(0)
		var uv2 := arr[Mesh.ARRAY_TEX_UV2] != null
		var mt := mi.mesh.surface_get_material(0)
		var s := "%-14s uv2=%s" % [nombre, uv2]
		if mt is StandardMaterial3D:
			var sm := mt as StandardMaterial3D
			var t := sm.albedo_texture
			s += "  mat=%s  color=%s" % [mt.resource_name, "%dx%d" % [t.get_width(), t.get_height()] if t else "SIN TEXTURA"]
			s += "  rug=%s  nor=%s" % [sm.roughness_texture != null, sm.normal_enabled]
		else:
			s += "  material=%s" % [mt]
		print(s)
	b.free()
	quit(0)
