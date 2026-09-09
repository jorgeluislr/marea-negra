extends Node
## Mide el estiramiento sobre la malla SOLDADA del SoftBody (no la original con costuras) y
## fotografía para ver la textura tras soldar.
@export var carpeta := ""
func _ready() -> void: _correr()
func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
func _mide(b: Node3D, esq: Skeleton3D, nombre: String) -> void:
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with(nombre): sb = x as SoftBody3D
	if sb == null: return
	var arr := sb.mesh.surface_get_arrays(0)   # la malla SOLDADA del cuerpo
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var tr := sb.transform
	var g := b.global_transform.affine_inverse()
	var rp := PackedVector3Array(); rp.resize(vs.size())
	for k in vs.size(): rp[k] = g * sb.get_point_transform(k)
	var ests: Array[float] = []; var peor := 0.0
	for t in range(0, idx.size(), 3):
		for e in [[idx[t],idx[t+1]],[idx[t+1],idx[t+2]],[idx[t+2],idx[t]]]:
			var a: int = e[0]; var c: int = e[1]
			var lr := (tr*vs[a]-tr*vs[c]).length(); var ld := (rp[a]-rp[c]).length()
			var est := (ld-lr)/maxf(lr,0.001); ests.append(est); peor = maxf(peor,est)
	ests.sort(); var n := ests.size(); var m50 := 0
	for e in ests:
		if e > 0.5: m50 += 1
	print("%-12s vertices=%d  estiramiento mediana %+.1f%%  p99 %+.1f%%  max %+.1f%%  bordes>50%%: %d" %
		[nombre, vs.size(), ests[n/2]*100, ests[int(n*0.99)]*100, ests[n-1]*100, m50])
func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	Viento.direccion = Vector3(1,0,0.4).normalized(); Viento.fuerza = 1.3
	var esq: Skeleton3D = b.find_children("*","Skeleton3D",true,false)[0]
	await get_tree().create_timer(8.0).timeout
	_mide(b, esq, "foque")
	_mide(b, esq, "vela_mayor")
	var cam := Camera3D.new(); add_child(cam); cam.fov = 55.0; cam.make_current()
	var o := b.global_position
	var ade := -b.global_transform.basis.z; var der := b.global_transform.basis.x
	cam.global_position = o - ade * 6.0 - der * 10.0 + Vector3.UP * 5.0
	cam.look_at(o + Vector3.UP * 4.5, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await _foto("soldado.png")
	get_tree().quit()
