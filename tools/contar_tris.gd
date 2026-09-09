extends SceneTree
func _init() -> void:
	for arch in ["balandra", "goleta", "lancha"]:
		var ruta := "res://assets/models/%s.glb" % arch
		if not ResourceLoader.exists(ruta):
			continue
		var raiz := (load(ruta) as PackedScene).instantiate()
		get_root().add_child(raiz)
		await process_frame
		var total := 0
		var mallas := 0
		var top: Array = []
		for n in raiz.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null: continue
			var t := 0
			for s in mi.mesh.get_surface_count():
				var a := mi.mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				t += (idx.size() / 3) if idx.size() > 0 else (vs.size() / 3)
			total += t
			mallas += 1
			top.append([t, mi.name])
		top.sort_custom(func(x, y): return x[0] > y[0])
		print("\n=== %s: %s triangulos en %d mallas ===" % [arch, _mil(total), mallas])
		for i in mini(8, top.size()):
			print("   %-22s %s" % [top[i][1], _mil(top[i][0])])
		raiz.queue_free()
		await process_frame
	quit()

func _mil(n: int) -> String:
	var s := str(n); var r := ""; var c := 0
	for i in range(s.length() - 1, -1, -1):
		r = s[i] + r; c += 1
		if c % 3 == 0 and i > 0: r = "." + r
	return r
