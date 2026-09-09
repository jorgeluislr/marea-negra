extends SceneTree
## Lista las mallas CON COLOR de vértice de cada modelo. Es lo que el escáner omnibus de
## tela.gd recogía por su cuenta; al pasar a un nodo por paño hay que saber sus nombres.

func _init() -> void:
	for f in ["lancha", "barca", "goleta", "balandra"]:
		var ruta := "res://assets/models/%s.glb" % f
		var esc := load(ruta) as PackedScene
		if esc == null:
			print("%s: NO SE PUDO CARGAR" % f)
			continue
		var raiz := esc.instantiate()
		var telas: Array[String] = []
		var otras := 0
		for n in raiz.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or mi.mesh.get_surface_count() == 0:
				continue
			if (mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0:
				telas.append("%s (%d verts)" % [mi.name, mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()])
			else:
				otras += 1
		print("%s: con color -> %s   | sin color: %d mallas" % [f, ", ".join(telas) if not telas.is_empty() else "NINGUNA", otras])
		raiz.free()
	quit()
