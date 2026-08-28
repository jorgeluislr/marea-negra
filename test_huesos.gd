extends SceneTree
## Test de CLI: lista los huesos del esqueleto de la lancha y comprueba que los tres
## controles (vela, timón, izado) encuentran el suyo.
##   godot --path . --headless -s test_huesos.gd
##
## Con -s los autoloads NO se instancian, así que los scripts que usan Viento fallan al
## compilar ("Identifier not found: Viento"). Es esperable y no afecta a esta comprobación.

func _init() -> void:
	var barco: Node3D = load("res://scenes/barcos/lancha.tscn").instantiate()
	root.add_child(barco)
	await process_frame

	var sk: Skeleton3D = null
	for c in barco.find_children("*", "Skeleton3D", true, false):
		sk = c
		break
	if sk == null:
		print("SIN SKELETON3D")
		quit()
		return

	var nombres: Array[String] = []
	for i in sk.get_bone_count():
		nombres.append(sk.get_bone_name(i))
	print("HUESOS (", sk.get_bone_count(), "): ", nombres)

	for n in ["vela", "driza", "timon"]:
		var idx := sk.find_bone(n)
		var rest := sk.get_bone_rest(idx) if idx >= 0 else Transform3D.IDENTITY
		print("  ", n, " -> idx ", idx, ("  rest.origin=%s  eje_Y=%s" % [rest.origin, rest.basis.y.normalized()]) if idx >= 0 else "  (AUSENTE: el control hace no-op)")

	for nodo in ["ControlVela", "ControlTimon", "ControlIzado"]:
		print("  nodo ", nodo, ": ", "presente" if barco.get_node_or_null(nodo) else "FALTA")

	# Movimiento real de los huesos, aplicado igual que en los scripts de control.
	var d := sk.find_bone("driza")
	if d >= 0:
		var rest := sk.get_bone_rest(d)
		sk.force_update_all_bone_transforms()
		var p0: Vector3 = sk.get_bone_global_pose(d).origin
		sk.set_bone_pose_position(d, rest.origin + rest.basis.y.normalized() * -0.77)
		sk.force_update_all_bone_transforms()
		var p1: Vector3 = sk.get_bone_global_pose(d).origin
		var mundo: Vector3 = sk.global_transform.basis * (p1 - p0)
		print("IZADO: driza baja ", (p1 - p0).length(), " en el modelo -> ", mundo, " en el mundo")

	var t := sk.find_bone("timon")
	if t >= 0:
		var rest_t := sk.get_bone_rest(t)
		var q := rest_t.basis.get_rotation_quaternion() * Quaternion(Vector3(0, 1, 0), deg_to_rad(35.0))
		sk.force_update_all_bone_transforms()
		var b0: Basis = sk.get_bone_global_pose(t).basis
		sk.set_bone_pose_rotation(t, q)
		sk.force_update_all_bone_transforms()
		var b1: Basis = sk.get_bone_global_pose(t).basis
		print("TIMON: gira ", rad_to_deg(b0.z.signed_angle_to(b1.z, b0.y)), " grados sobre el eje del hueso")
	quit()
