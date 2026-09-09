extends Node
## Muestra los colisionadores (cápsulas de palo + barreras del jugador) y verifica si la vela
## puede chocar con alguno que no sea su palo.
@export var carpeta := ""
func _ready() -> void: _correr()
func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
func _correr() -> void:
	await get_tree().create_timer(4.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("vela_mayor"): sb = x as SoftBody3D
	print("VELA MAYOR softbody: collision_mask = %d" % sb.collision_mask)
	# recorre todos los StaticBody del barco
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(1,0.4,0,0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for sbody in b.find_children("*", "StaticBody3D", true, false):
		var st := sbody as StaticBody3D
		var choca := (sb.collision_mask & st.collision_layer) != 0
		var ncaps := 0; var ncajas := 0; var rmin := 9.0; var rmax := 0.0
		for cs in st.find_children("*","CollisionShape3D",true,false):
			var sh := (cs as CollisionShape3D).shape
			if sh is CapsuleShape3D:
				ncaps += 1; rmin = minf(rmin,(sh as CapsuleShape3D).radius); rmax = maxf(rmax,(sh as CapsuleShape3D).radius)
			elif sh is ConcavePolygonShape3D: pass
			else: ncajas += 1
		print("%-18s layer=%d  ¿la vela choca con él? %s   cápsulas=%d (radio %.3f-%.3f) cajas=%d"
			% [st.name, st.collision_layer, choca, ncaps, rmin if ncaps>0 else 0.0, rmax, ncajas])
		# dibuja sus cápsulas
		if choca or st.name == "Colisiones":
			for cs in st.find_children("*","CollisionShape3D",true,false):
				var sh := (cs as CollisionShape3D).shape
				var mi := MeshInstance3D.new()
				if sh is CapsuleShape3D:
					var cm := CapsuleMesh.new(); cm.radius=(sh as CapsuleShape3D).radius; cm.height=(sh as CapsuleShape3D).height; mi.mesh=cm
				elif sh is BoxShape3D:
					var bm := BoxMesh.new(); bm.size=(sh as BoxShape3D).size; mi.mesh=bm
				else: continue
				mi.material_override = mat
				(cs as Node3D).add_child(mi)
	await get_tree().create_timer(0.5).timeout
	var cam := Camera3D.new(); add_child(cam); cam.fov = 55.0; cam.make_current()
	var o := b.global_position
	var ade := -b.global_transform.basis.z; var der := b.global_transform.basis.x
	cam.global_position = o - ade * 6.0 - der * 10.0 + Vector3.UP * 4.0
	cam.look_at(o - ade * 1.0 + Vector3.UP * 3.5, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await _foto("colisiones_vela.png")
	get_tree().quit()
