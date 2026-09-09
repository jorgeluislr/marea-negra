extends Node
## Herramienta de sesion: la vela mayor desde el traves, navegando, para ver el sombreado.
## Reducir la malla recalcula las normales, y un facetado no lo detecta ninguna medida de
## distancia: hay que mirarlo.

@export var carpeta := ""

func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func(): get_tree().quit(1))
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	var b := esc.instantiate() as Node3D
	add_child(b)
	Viento.direccion_base = Vector3(1, 0, 0)
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	for i in 700:
		b.set("anclado", false)
		await get_tree().process_frame
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 45.0
	cam.make_current()
	var o := b.global_position
	var ade := -b.global_transform.basis.z
	var der := b.global_transform.basis.x
	var tomas := {
		"mayor_traves.png": [o + der * 14.0 + Vector3.UP * 5.5, o + Vector3.UP * 5.0],
		"mayor_cerca.png": [o + der * 6.0 + ade * 2.0 + Vector3.UP * 4.5, o + Vector3.UP * 4.5],
	}
	for nombre in tomas:
		var t: Array = tomas[nombre]
		cam.global_position = t[0]
		cam.look_at(t[1], Vector3.UP)
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
		print("FOTO %s" % nombre)
	get_tree().quit()
