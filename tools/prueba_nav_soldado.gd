extends Node
## Mide el estiramiento NAVEGANDO y trimado sobre la malla soldada, contra la forma de reposo
## capturada al arrancar. Y fotografía navegando.
@export var carpeta := ""
func _ready() -> void: _correr()
func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	Viento.fuerza = 0.0
	var esq: Skeleton3D = b.find_children("*","Skeleton3D",true,false)[0]
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("vela_mayor"): sb = x as SoftBody3D
	var idx: PackedInt32Array = sb.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var n: int = sb.get_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	await get_tree().create_timer(3.0).timeout
	# reposo (sin viento)
	var rest := PackedVector3Array(); rest.resize(n)
	for k in n: rest[k] = sb.get_point_transform(k)
	# navegando y trimado
	Viento.direccion = Vector3(1,0,0.5).normalized(); Viento.fuerza = 1.3
	await get_tree().create_timer(8.0).timeout
	var now := PackedVector3Array(); now.resize(n)
	for k in n: now[k] = sb.get_point_transform(k)
	var ests: Array[float] = []; var peor := 0.0; var m50 := 0
	for t in range(0, idx.size(), 3):
		for e in [[idx[t],idx[t+1]],[idx[t+1],idx[t+2]],[idx[t+2],idx[t]]]:
			var a: int = e[0]; var c: int = e[1]
			var lr := (rest[a]-rest[c]).length(); var ld := (now[a]-now[c]).length()
			var est := (ld-lr)/maxf(lr,0.001); ests.append(est); peor = maxf(peor,est)
			if est > 0.5: m50 += 1
	ests.sort(); var nn := ests.size()
	print("NAVEGANDO trim=%.1f: estiramiento mediana %+.1f%%  p99 %+.1f%%  max %+.1f%%  bordes>50%%: %d de %d" %
		[rad_to_deg(esq.get_bone_pose_rotation(esq.find_bone("vela")).get_euler().y), ests[nn/2]*100, ests[int(nn*0.99)]*100, ests[nn-1]*100, m50, nn])
	var cam := Camera3D.new(); add_child(cam); cam.fov = 55.0; cam.make_current()
	var o := b.global_position
	var ade := -b.global_transform.basis.z; var der := b.global_transform.basis.x
	# sotavento: la vela trima a babor (der negativa), así que la cámara va a babor mirando la cara
	cam.global_position = o - ade * 3.0 - der * 11.0 + Vector3.UP * 4.5
	cam.look_at(o - ade * 2.0 + Vector3.UP * 4.0, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await _foto("nav_soldado.png")
	# y un plano cerrado de la baluma (borde libre, popa de la mayor)
	cam.global_position = o - ade * 8.0 - der * 5.0 + Vector3.UP * 5.0
	cam.look_at(o - ade * 4.0 + Vector3.UP * 4.5, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await _foto("nav_baluma.png")
	get_tree().quit()
