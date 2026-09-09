extends Node

## Experimento decisivo: si la bandera obedece al area de OTRO pano, es que las areas se pisan.
##
## Se apaga el viento global y se enciende una sola area cada vez, con una gravedad enorme y
## hacia un lado distinto. Se mira hacia donde se va la bandera.


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	var barco := esc.instantiate() as Node3D
	add_child(barco)
	Viento.direccion_base = Vector3(0, 0, 1)
	barco.set("anclado", true)
	await get_tree().create_timer(5.0).timeout

	var ctrl: Node = null
	for h in barco.get_children():
		if h.has_method("datos_depuracion") and str(h.get("nombre_malla")).find("bandera") >= 0:
			ctrl = h
	var d: Dictionary = ctrl.datos_depuracion()
	var cuerpo: SoftBody3D = d["cuerpo"]
	var fijo: PackedByteArray = d["fijo"]
	var areas := {}
	for a in barco.find_children("AreaViento_*", "Area3D", true, false):
		areas[(a as Area3D).name] = a as Area3D

	# Que nadie recalcule la gravedad: se paran los controles de tela.
	for h in barco.get_children():
		if h.has_method("datos_depuracion"):
			h.set_process(false)

	print("%-24s %s" % ["area con gravedad 30 hacia +X", "vuelo de la bandera"])
	for nombre in areas:
		for otro in areas:
			(areas[otro] as Area3D).gravity = 0.01
		var ar: Area3D = areas[nombre]
		ar.gravity = 30.0
		ar.gravity_direction = Vector3(1, 0, 0)
		await get_tree().create_timer(4.0).timeout
		var anc := Vector3.ZERO; var na := 0
		var lej := Vector3.ZERO; var nl := 0
		var inv := barco.global_transform.affine_inverse()
		for i in fijo.size():
			var p := inv * cuerpo.get_point_transform(i)
			if fijo[i] == 1: anc += p; na += 1
			else: lej += p; nl += 1
		var v := (lej / float(nl)) - (anc / float(na))
		print("  %-22s -> (%+.2f, %+.2f, %+.2f)   |%.2f| m" % [nombre, v.x, v.y, v.z, v.length()])
	get_tree().quit()
