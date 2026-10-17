extends Node
## La mayor trimada a cada banda y en dos rumbos, desde una cámara fija AL BARCO.
##
## Ni "la botavara sube 0,74 m" ni "pasa a 10 cm del obenque" dicen cómo se ve. Y la cámara
## tiene que ir sujeta al barco: en ejes de mundo la toma se va en cuanto el casco orza y las
## fotos dejan de ser comparables.
##
##     godot --path . tools/foto_trimado.tscn -- --carpeta=<ruta>

var carpeta := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--carpeta="):
			carpeta = a.substr(10)
	get_tree().create_timer(300.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	await get_tree().create_timer(7.0).timeout
	Oleaje.asentar()
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		print("no hay barco"); get_tree().quit(1); return
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50.0
	cam.far = 25000.0
	cam.make_current()
	# beta = ángulo del viento desde la proa; lado +1 = viento por estribor (percha a babor).
	for caso in [[45.0, 1.0, "cenida"], [90.0, 1.0, "traves"], [150.0, 1.0, "popa_percha_babor"],
			[150.0, -1.0, "popa_percha_estribor"]]:
		var beta: float = caso[0]
		var lado: float = caso[1]
		var desde := Vector3(sin(deg_to_rad(beta)) * lado, 0.0, -cos(deg_to_rad(beta)))
		var t := 0.0
		while t < 16.0:
			Viento.direccion_base = (b.global_transform.basis * -desde).normalized()
			b.set("anclado", true)
			await get_tree().physics_frame
			t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		for vista in ["costado", "popa"]:
			var o := b.global_position
			var der := b.global_transform.basis.x
			var ade := -b.global_transform.basis.z
			var ojo: Vector3 = o + der * -18.0 + Vector3.UP * 7.0 if vista == "costado" 					else o - ade * 20.0 + Vector3.UP * 9.0
			cam.global_position = ojo
			cam.look_at(o + Vector3.UP * 5.0, Vector3.UP)
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			var nom := "%s_%s.png" % [caso[2], vista]
			get_viewport().get_texture().get_image().save_png(carpeta.path_join(nom))
			print("FOTO %s" % nom)
	get_tree().quit(0)
