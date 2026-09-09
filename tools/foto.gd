extends Node
## Herramienta de sesión: cámara propia (la orbital del juego sobrescribe la suya cada frame),
## colocada sobre la proa del barco activo, y varias capturas. Se quita cuando no haga falta.

@export var carpeta := ""
@export var espera := 3.5

func _ready() -> void:
	_disparar()

func _barco() -> Node3D:
	var g := get_tree().get_nodes_in_group("barco_activo")
	return g[0] as Node3D if not g.is_empty() else null

func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(carpeta.path_join(nombre))
	print("FOTO %s" % nombre)

func _disparar() -> void:
	await get_tree().create_timer(espera).timeout
	var b := _barco()
	if b == null:
		print("FOTO: sin barco activo"); get_tree().quit(1); return
	print("barco activo: %s en %s" % [b.name, b.global_position])
	# ¿qué hay del paño físico?
	for sb in b.find_children("*", "SoftBody3D", true, false):
		var s := sb as SoftBody3D
		var aabb := AABB(s.get_point_transform(0), Vector3.ZERO)
		for k in 253:
			aabb = aabb.expand(s.get_point_transform(k))
		print("  %s: caja %s  centro %s" % [s.name, aabb.size, aabb.get_center()])
	for mi in b.find_children("foque", "MeshInstance3D", true, false):
		print("  malla original 'foque' visible=%s" % (mi as MeshInstance3D).visible)

	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 60.0
	cam.make_current()
	var o := b.global_position
	var ade := -b.global_transform.basis.z
	var der := b.global_transform.basis.x
	var arr := Vector3.UP
	var tomas := {
		"fis_general.png": [o + ade * 6.0 + der * 13.0 + arr * 5.0, o + ade * 3.0 + arr * 4.0],
		"fis_foque.png": [o + ade * 9.0 + der * 7.0 + arr * 4.5, o + ade * 7.5 + arr * 4.0],
		"fis_proa.png": [o + ade * 14.0 + der * 1.5 + arr * 3.5, o + ade * 7.0 + arr * 3.5],
		"fis_lejos.png": [o + ade * 10.0 + der * 26.0 + arr * 8.0, o + arr * 4.0],
	}
	for nombre in tomas:
		var t: Array = tomas[nombre]
		cam.global_position = t[0]
		cam.look_at(t[1], Vector3.UP)
		await get_tree().create_timer(0.35).timeout
		await _foto(nombre)
	get_tree().quit()
