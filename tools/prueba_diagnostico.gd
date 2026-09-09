extends Node
## Visualiza TODO lo que afecta a la física del barco, en colores:
##  - naranja: cápsulas de palo (perchas_solidas) — con lo que la vela puede chocar
##  - azul: colisionadores del casco/borda/barreras (colisiones_barco) — jugador
##  - verde: la caja de colisión del CharacterBody (choque del barco con el mundo)
##  - rojo: vértices ANCLADOS de las velas físicas (siguen al esqueleto)
##  - amarillo: vértices LIBRES de las velas (los mueve el solver)
## Y prueba el control en primera persona con el barco GIRADO.
@export var carpeta := ""
func _ready() -> void: _correr()
func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
func _caja(padre: Node, forma: Shape3D, t: Transform3D, col: Color) -> void:
	var mi := MeshInstance3D.new()
	if forma is BoxShape3D:
		var bm := BoxMesh.new(); bm.size = (forma as BoxShape3D).size; mi.mesh = bm
	elif forma is CapsuleShape3D:
		var cm := CapsuleMesh.new(); cm.radius=(forma as CapsuleShape3D).radius; cm.height=(forma as CapsuleShape3D).height; mi.mesh = cm
	else: return
	var mat := StandardMaterial3D.new(); mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat; mi.transform = t
	padre.add_child(mi)
func _puntos(padre: Node, ps: Array, col: Color, r: float) -> void:
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
	var e := SphereMesh.new(); e.radius = r; e.height = r*2; mm.mesh = e
	mm.instance_count = ps.size()
	for i in ps.size(): mm.set_instance_transform(i, Transform3D(Basis(), ps[i]))
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm
	var mat := StandardMaterial3D.new(); mat.albedo_color = col; mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmi.material_override = mat
	padre.add_child(mmi)
func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	await get_tree().create_timer(2.0).timeout
	# cápsulas de palo (naranja) y colisiones del jugador (azul)
	for sbody in b.find_children("*", "StaticBody3D", true, false):
		var col: Color = Color(1,0.4,0,0.3) if (sbody as Node).name.begins_with("Percha") else Color(0.2,0.4,1,0.25)
		for cs in (sbody as Node).find_children("*","CollisionShape3D",true,false):
			var sh := (cs as CollisionShape3D).shape
			if sh is ConcavePolygonShape3D: continue
			_caja(sbody, sh, (cs as Node3D).transform, col)
	# caja del casco (verde)
	for cs in b.find_children("CollisionShape3D", "CollisionShape3D", false, false):
		var sh := (cs as CollisionShape3D).shape
		if sh is BoxShape3D: _caja(b, sh, (cs as Node3D).transform, Color(0,1,0.2,0.2))
	# anclas (rojo) y libres (amarillo) de las velas
	var g := b.global_transform
	for sb in b.find_children("*", "SoftBody3D", true, false):
		var s := sb as SoftBody3D
		var nm := (s as Node).name.replace("PanoFisico_","")
		var l := b.find_children(nm, "MeshInstance3D", true, false)
		if l.is_empty(): continue
		var cols: PackedColorArray = (l[0] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var anc := []; var lib := []
		for k in cols.size():
			var p := s.get_point_transform(k)
			if cols[k].b > 0.5: anc.append(p)
			elif k % 3 == 0: lib.append(p)   # 1 de cada 3 libres, para no saturar
		_puntos(get_tree().current_scene, anc, Color(1,0,0), 0.06)
		_puntos(get_tree().current_scene, lib, Color(1,1,0), 0.03)
	# camara
	var cam := Camera3D.new(); add_child(cam); cam.fov = 55.0; cam.make_current()
	var o := b.global_position
	var ade := -b.global_transform.basis.z; var der := b.global_transform.basis.x
	cam.global_position = o - ade * 4.0 - der * 12.0 + Vector3.UP * 6.0
	cam.look_at(o + Vector3.UP * 4.0, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await _foto("diag_colores.png")
	# --- prueba de control con el barco GIRADO 90 grados ---
	b.rotation.y = PI/2.0
	await get_tree().process_frame
	var jug: CharacterBody3D = (load("res://scenes/character/player.tscn") as PackedScene).instantiate()
	b.add_child(jug); jug.position = Vector3(0, 3.0, 0)
	await get_tree().create_timer(1.0).timeout
	var p0 := jug.global_position
	var w := InputEventKey.new(); w.keycode = KEY_W; w.physical_keycode = KEY_W; w.pressed = true
	Input.parse_input_event(w)
	for i in 60: await get_tree().physics_frame
	var mov := jug.global_position - p0
	var fwd := -jug.global_transform.basis.z
	print("barco girado 90. Con W el personaje se movio %v (%.2f m). Su 'delante' global es %v. Producto escalar=%.2f (1=perfecto)"
		% [mov, mov.length(), fwd, mov.normalized().dot(fwd) if mov.length()>0.1 else 0.0])
	# timón en primera persona: gobierno false + tecla A no debe mover la caña
	b.set("gobierno", false)
	var esq: Skeleton3D = b.find_children("*","Skeleton3D",true,false)[0]
	var it := esq.find_bone("timon")
	var a0 := esq.get_bone_pose_rotation(it).get_euler().y
	var a := InputEventKey.new(); a.keycode = KEY_A; a.physical_keycode = KEY_A; a.pressed = true
	Input.parse_input_event(a)
	for i in 60: await get_tree().physics_frame
	var a1 := esq.get_bone_pose_rotation(it).get_euler().y
	print("timon en 1a persona (gobierno=false), tras pulsar A: giro %.3f -> %.3f grados (debe ~0)" % [rad_to_deg(a0), rad_to_deg(a1)])
	get_tree().quit()
