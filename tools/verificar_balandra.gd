extends SceneTree

func _tr(n: Node, raiz: Node) -> Transform3D:
	var t := Transform3D(); var x := n
	while x != null and x != raiz:
		if x is Node3D: t = (x as Node3D).transform * t
		x = x.get_parent()
	return t

func _initialize() -> void:
	var b: Node3D = (load("res://scenes/barcos/balandra.tscn") as PackedScene).instantiate()
	var esq: Array[Node] = b.find_children("*", "Skeleton3D", true, false)
	if esq.is_empty():
		print("SIN ESQUELETO")
	else:
		var s := esq[0] as Skeleton3D
		var hs: Array[String] = []
		for i in s.get_bone_count(): hs.append(s.get_bone_name(i))
		print("esqueleto: ", s.name, "  huesos: ", hs)
		for n in ["vela", "driza", "timon", "raiz"]:
			print("  ", n, " -> idx ", s.find_bone(n))
	var claves := {"timon": "", "botalon": "", "cubierta": "", "vela_": ""}
	var mats := {}
	var telas: Array[String] = []
	var skinned := 0; var n := 0
	var aabb := AABB()
	for nodo in b.find_children("*", "MeshInstance3D", true, false):
		var mi := nodo as MeshInstance3D
		if mi.mesh == null: continue
		if mi.skin != null: skinned += 1
		var a := _tr(mi, b) * mi.mesh.get_aabb()
		if n == 0: aabb = a
		else: aabb = aabb.merge(a)
		n += 1
		var nm := mi.name.to_lower()
		for k in claves:
			if nm.begins_with(k) and claves[k] == "":
				claves[k] = "z=[%.2f,%.2f]" % [a.position.z, a.position.z + a.size.z]
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			if arr.size() > Mesh.ARRAY_COLOR and arr[Mesh.ARRAY_COLOR] != null and not telas.has(mi.name):
				telas.append(mi.name)
			var mt := mi.mesh.surface_get_material(si)
			if mt is StandardMaterial3D:
				var sm := mt as StandardMaterial3D
				mats[mt.resource_name] = "alb=%s" % [str(sm.albedo_texture != null)]
	print("mallas: ", n, "  con piel: ", skinned, "  telas: ", telas)
	for k in claves: print("  ", k, " ", claves[k])
	print("materiales con textura de color:")
	for k in mats: print("   ", k, " ", mats[k])
	quit(0)
