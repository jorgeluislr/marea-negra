extends Node
## ¿En qué espacio devuelve SoftBody3D.get_point_transform? Lo contrasto con el nodo de anclaje
## de ese mismo vértice, del que sé su posición local y global.
func _ready() -> void: _correr()
func _correr() -> void:
	await get_tree().create_timer(2.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	var sb := b.find_children("*", "SoftBody3D", true, false)[0] as SoftBody3D
	var esq: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
	var anclas := esq.find_children("Ancla_foque_*", "Node3D", false, false)
	print("esqueleto global origen %v" % esq.global_transform.origin)
	print("softbody transform %v  global %v" % [sb.transform.origin, sb.global_transform.origin])
	for i in mini(3, anclas.size()):
		var a := anclas[i] as Node3D
		var k := int(a.name.get_slice("_", 2))
		var p := sb.get_point_transform(k)
		print("  vert %d: punto %v | ancla local %v | ancla global %v | dif con local %.4f | dif con global %.4f"
			% [k, p, a.position, a.global_position, (p - a.position).length(), (p - a.global_position).length()])
	get_tree().quit()
