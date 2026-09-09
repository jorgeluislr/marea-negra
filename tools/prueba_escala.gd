extends Node
## ¿Está el personaje a escala? Mide su cápsula, su altura de ojos, el ancho de cubierta a sus
## pies y la altura de la borda, todo en metros de mundo, y fotografía mirando al través.
@export var carpeta := ""

func _ready() -> void: _correr()

func _pulsar(k: int) -> void:
	var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var u := InputEventKey.new(); u.keycode = k; u.physical_keycode = k; u.pressed = false
	Input.parse_input_event(u)
	await get_tree().process_frame

func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))

func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	await _pulsar(KEY_F)
	await get_tree().create_timer(1.5).timeout
	var jug := b.find_child("Player", false, false) as CharacterBody3D
	var cs := jug.find_child("CollisionShape3D", false, false) as CollisionShape3D
	var cap := cs.shape as CapsuleShape3D
	var cam := jug.find_children("*", "Camera3D", true, false)[0] as Camera3D
	print("personaje: capsula radio %.2f alto %.2f | escala nodo %v | escala global %v"
		% [cap.radius, cap.height, jug.scale, jug.global_transform.basis.get_scale()])
	print("barco: escala nodo %v | Modelo escala %v" % [b.scale, (b.find_child("Modelo", false, false) as Node3D).scale])
	print("camara: fov %.1f  ojos a %.2f m sobre los pies  (global y %.2f)"
		% [cam.fov, cam.global_position.y - (jug.global_position.y - cap.height * 0.5), cam.global_position.y])
	# ancho de cubierta a los pies del personaje, con rayos al través
	var esp := b.get_world_3d().direct_space_state
	var pies := jug.global_position - Vector3.UP * (cap.height * 0.5 - 0.05)
	var der := b.global_transform.basis.x
	var ancho := []
	for lado in [-1.0, 1.0]:
		var par := PhysicsRayQueryParameters3D.create(pies + Vector3.UP * 0.35, pies + Vector3.UP * 0.35 + der * lado * 6.0)
		par.collision_mask = 4
		var r := esp.intersect_ray(par)
		ancho.append(0.0 if r.is_empty() else (r["position"] as Vector3).distance_to(pies + Vector3.UP * 0.35))
	print("cubierta: %.2f m a babor + %.2f m a estribor = %.2f m de manga a sus pies" % [ancho[0], ancho[1], ancho[0] + ancho[1]])
	# altura de la borda respecto a los pies
	var par2 := PhysicsRayQueryParameters3D.create(pies + der * 1.2 + Vector3.UP * 3.0, pies + der * 1.2)
	par2.collision_mask = 4
	var r2 := esp.intersect_ray(par2)
	if not r2.is_empty():
		print("borda: su cara alta esta a %.2f m sobre los pies (una persona mide %.2f)" % [(r2["position"] as Vector3).y - pies.y, cap.height])
	# y la manga en el centro del barco, no solo en el timon
	jug.position = Vector3(0, 3.0, 0)
	await get_tree().create_timer(1.2).timeout
	var pies2 := jug.global_position - Vector3.UP * (cap.height * 0.5 - 0.05)
	var an2 := []
	for lado in [-1.0, 1.0]:
		var pr := PhysicsRayQueryParameters3D.create(pies2 + Vector3.UP * 0.35, pies2 + Vector3.UP * 0.35 + der * lado * 6.0)
		pr.collision_mask = 4
		var rr := esp.intersect_ray(pr)
		an2.append(0.0 if rr.is_empty() else (rr["position"] as Vector3).distance_to(pies2 + Vector3.UP * 0.35))
	print("cubierta en el centro: %.2f + %.2f = %.2f m de manga" % [an2[0], an2[1], an2[0] + an2[1]])
	# fotos: al través y mirando a los pies
	var piv := jug.find_child("CameraPivot", false, false) as Node3D
	jug.rotation.y = 0.0
	piv.rotation.x = 0.0
	jug.rotate_y(-PI / 2.0)
	await get_tree().create_timer(0.4).timeout
	await _foto("esc_traves.png")
	piv.rotation.x = -0.85
	await get_tree().create_timer(0.4).timeout
	await _foto("esc_pies.png")
	get_tree().quit()
