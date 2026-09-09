extends Node
## ¿El paño se asienta o flamea? Mide el grueso del paño físico cada medio segundo.
func _ready() -> void: _correr()
func _correr() -> void:
	await get_tree().create_timer(1.0).timeout
	var g := get_tree().get_nodes_in_group("barco_activo")
	var b := g[0] as Node3D
	var sb := b.find_children("*", "SoftBody3D", true, false)[0] as SoftBody3D
	var esq: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
	print("viento %s fuerza %.2f" % [Viento.direccion, Viento.fuerza])
	var linea := ""
	for paso in 30:
		await get_tree().create_timer(0.5).timeout
		var aabb := AABB(sb.get_point_transform(0), Vector3.ZERO)
		for k in 253: aabb = aabb.expand(sb.get_point_transform(k))
		linea += " %.2f" % aabb.size.x
	print("grueso cada 0,5 s:" + linea)
	get_tree().quit()
