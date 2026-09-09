extends SceneTree
## ¿Llegan a Godot con textura de color las piezas grandes del casco y la cubierta?

func _initialize() -> void:
	var b: Node3D = (load("res://scenes/barcos/balandra.tscn") as PackedScene).instantiate()
	for nombre in ["casco_lod0", "cubierta_min", "bodega", "mastil_v3", "botalon", "barril"]:
		var l := b.find_children(nombre, "MeshInstance3D", true, false)
		if l.is_empty(): print(nombre, ": NO ESTA"); continue
		var mi := l[0] as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var mt := mi.mesh.surface_get_material(si)
			var s := "%-14s sup%d " % [nombre, si]
			if mt is StandardMaterial3D:
				var sm := mt as StandardMaterial3D
				var t := sm.albedo_texture
				s += "mat=%-22s color=%s  albedo=%s" % [mt.resource_name,
					("%dx%d" % [t.get_width(), t.get_height()]) if t else "SIN TEXTURA",
					sm.albedo_color]
			else: s += "material=%s" % [mt]
			print(s)
	b.free()
	quit(0)
