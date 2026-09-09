extends Node
## ¿Las cápsulas de percha coinciden con sus palos, o se mueven por separado? Compara el eje de
## cada cápsula con el eje del palo calculado desde el MISMO hueso que deforma el palo visible.
func _ready() -> void: _correr()

func _correr() -> void:
	await get_tree().create_timer(4.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	var esq: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
	# fuerza un trim marcado
	Viento.direccion = Vector3(1,0,1).normalized(); Viento.fuerza = 1.5
	await get_tree().create_timer(3.0).timeout
	for nom in ["botavara", "pico", "mastil_v3"]:
		var mi := b.find_children(nom,"MeshInstance3D",true,false)[0] as MeshInstance3D
		var arr := mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var hu: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var pe: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		# hueso dominante del palo
		var suma := {}
		for k in vs.size():
			for j in 4:
				var w: float = pe[k*4+j]
				if w>0.0: suma[hu[k*4+j]] = float(suma.get(hu[k*4+j],0.0))+w
		var bi := -1; var mw := 0.0
		for x in suma:
			if float(suma[x])>mw: mw=float(suma[x]); bi=int(x)
		# posicion actual del palo = M_hueso * rest_vertice, promedio
		var M := esq.get_bone_global_pose(bi) * esq.get_bone_global_rest(bi).affine_inverse()
		var cpalo := Vector3.ZERO
		for v in vs: cpalo += M * v
		cpalo /= vs.size()
		# la capsula correspondiente
		var perc: StaticBody3D = null
		for c in esq.get_children():
			if (c as Node).name == "Percha_"+nom: perc = c as StaticBody3D
		if perc == null: print("%s: SIN capsula" % nom); continue
		var ccap := perc.transform.origin
		print("%-10s hueso=%s | centro palo %v | centro capsula %v | separacion %.3f m" %
			[nom, esq.get_bone_name(bi), cpalo, ccap, (cpalo-ccap).length()])
	get_tree().quit()
