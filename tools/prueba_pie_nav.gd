extends Node
## Foto del pie de la mayor NAVEGANDO (botavara trimada), de cerca, desde varios angulos.
@export var carpeta := ""
func _ready() -> void: _correr()
func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	var esq: Skeleton3D = b.find_children("*","Skeleton3D",true,false)[0]
	# viento marcado para que trime
	Viento.direccion = Vector3(1,0,0.8).normalized(); Viento.fuerza = 1.3
	var cam := Camera3D.new(); add_child(cam); cam.fov = 50.0; cam.make_current()
	await get_tree().create_timer(8.0).timeout
	print("angulo_vela trim = %.1f grados" % rad_to_deg(esq.get_bone_pose_rotation(esq.find_bone("vela")).get_euler().y))
	# lado de sotavento (hacia donde abomba), viendo el pie a lo largo de la botavara
	var o := b.global_position
	var ade := -b.global_transform.basis.z; var der := b.global_transform.basis.x
	# camara alta detras-babor mirando el pie
	cam.global_position = o - ade * 5.0 + der * 9.0 + Vector3.UP * 5.0
	cam.look_at(o - ade * 2.0 + Vector3.UP * 3.2, Vector3.UP)
	await get_tree().create_timer(0.3).timeout
	await _foto("pie_nav_a.png")
	# desde arriba mirando el pie contra la botavara
	cam.global_position = o - ade * 2.0 + der * 3.0 + Vector3.UP * 7.0
	cam.look_at(o - ade * 3.5 + Vector3.UP * 2.8, Vector3.UP)
	await get_tree().create_timer(0.3).timeout
	await _foto("pie_nav_b.png")
	get_tree().quit()
