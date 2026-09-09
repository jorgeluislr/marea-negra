extends Node
## Coste y comportamiento con las DOS velas en física. Mide física y proceso (el script mueve
## 1.400 nodos de anclaje al recoger, y eso es GDScript, no solver), arría la mayor y fotografía.
@export var carpeta := ""

func _ready() -> void: _correr()

func _caja(b: Node3D, sb: SoftBody3D, n: int) -> String:
	var inv := b.global_transform.affine_inverse()
	var lo := Vector3.INF; var hi := -Vector3.INF
	for k in n:
		var q := inv * sb.get_point_transform(k)
		lo = Vector3(minf(lo.x, q.x), minf(lo.y, q.y), minf(lo.z, q.z))
		hi = Vector3(maxf(hi.x, q.x), maxf(hi.y, q.y), maxf(hi.z, q.z))
	var t := hi - lo
	return "%.2f x %.2f x %.2f" % [t.x, t.y, t.z]

func _medir(n: int) -> String:
	var f := 0.0; var pr := 0.0
	for i in n:
		await get_tree().process_frame
		f += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		pr += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	return "fisica %.3f ms | proceso %.3f ms" % [f / n, pr / n]

func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))

func _correr() -> void:
	await get_tree().create_timer(3.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	var sbs := b.find_children("*", "SoftBody3D", true, false)
	var mayor: SoftBody3D = null
	var foque: SoftBody3D = null
	for x in sbs:
		if (x as Node).name.ends_with("vela_mayor"): mayor = x as SoftBody3D
		else: foque = x as SoftBody3D
	var cam := Camera3D.new(); add_child(cam); cam.fov = 60.0; cam.make_current()
	var o := b.global_position
	var ade := -b.global_transform.basis.z
	var der := b.global_transform.basis.x
	cam.global_position = o + ade * 2.0 + der * 24.0 + Vector3.UP * 8.0
	cam.look_at(o + Vector3.UP * 5.0, Vector3.UP)
	await get_tree().create_timer(1.0).timeout
	print("izadas   %s | mayor %s | foque %s" % [await _medir(150), _caja(b, mayor, 1347), _caja(b, foque, 253)])
	await _foto("may_izada.png")
	b.set("vela_trasera", false); b.emit_signal("vela_trasera_cambiada", false)
	await get_tree().create_timer(4.0).timeout
	print("arriando %s | mayor %s" % [await _medir(150), _caja(b, mayor, 1347)])
	await get_tree().create_timer(5.0).timeout
	print("arriada  %s | mayor %s" % [await _medir(150), _caja(b, mayor, 1347)])
	await _foto("may_arriada.png")
	b.set("vela_trasera", true); b.emit_signal("vela_trasera_cambiada", true)
	await get_tree().create_timer(8.0).timeout
	print("reizada  %s | mayor %s" % [await _medir(150), _caja(b, mayor, 1347)])
	await _foto("may_reizada.png")
	get_tree().quit()
