extends Node
## Compara el estiramiento del FOQUE (que va bien) con la mayor, y localiza el triangulo peor.
func _ready() -> void: _correr()
func _mide(b: Node3D, esq: Skeleton3D, nombre: String, ncount: int) -> void:
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with(nombre): sb = x as SoftBody3D
	var mi := b.find_children(nombre,"MeshInstance3D",true,false)[0] as MeshInstance3D
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var tr := Transform3D(); var x: Node = mi
	while x != null and x != esq:
		if x is Node3D: tr = (x as Node3D).transform * tr
		x = x.get_parent()
	var g := b.global_transform.affine_inverse()
	var rp := PackedVector3Array(); rp.resize(vs.size())
	for k in vs.size(): rp[k] = g * sb.get_point_transform(k)
	var suma := 0.0; var nn := 0; var peor := 0.0; var lr_peor := 0.0; var ld_peor := 0.0
	for t in range(0, idx.size(), 3):
		for e in [[idx[t],idx[t+1]],[idx[t+1],idx[t+2]],[idx[t+2],idx[t]]]:
			var a: int = e[0]; var c: int = e[1]
			var lr := (tr*vs[a] - tr*vs[c]).length()
			var ld := (rp[a] - rp[c]).length()
			var est := (ld-lr)/maxf(lr,0.001)
			suma += est; nn += 1
			if est > peor: peor = est; lr_peor = lr; ld_peor = ld
	print("%-12s estiramiento medio %+.1f%%  peor %+.1f%% (arista reposo %.3fm -> %.3fm)" % [nombre, suma/nn*100, peor*100, lr_peor, ld_peor])
func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	Viento.direccion = Vector3(1,0,1).normalized(); Viento.fuerza = 1.5
	var esq: Skeleton3D = b.find_children("*","Skeleton3D",true,false)[0]
	await get_tree().create_timer(8.0).timeout
	_mide(b, esq, "foque", 253)
	_mide(b, esq, "vela_mayor", 1347)
	get_tree().quit()
