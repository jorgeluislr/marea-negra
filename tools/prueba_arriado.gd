extends SceneTree

## Al TRIMAR la vela (girar el hueso 'vela'), cuanto cree vela_fisica.gd que se ha arriado?
## Compara la medida GLOBAL (la del script) con la medida LOCAL (la correcta).

func _init() -> void:
	var ps: PackedScene = load("res://assets/models/balandra.glb")
	var raiz := ps.instantiate()
	get_root().add_child(raiz)
	await process_frame
	var skel := (raiz.find_children("*", "Skeleton3D", true, false)[0]) as Skeleton3D

	var b_vela := skel.find_bone("vela")
	var b_driza := skel.find_bone("driza")
	var b_pico := skel.find_bone("driza_pico")
	var rest_vela := skel.get_bone_rest(b_vela).basis.get_rotation_quaternion()

	print("recorrido driza = 6.929 m | recorrido pico = 5.494 m\n")
	print("trim | driza: despl.GLOBAL -> arriado que CREE el script | despl.LOCAL (correcto)")
	for grados in [0.0, 5.0, 10.0, 20.0, 30.0, 45.0]:
		var q := rest_vela * Quaternion(Vector3(0, 1, 0), deg_to_rad(grados))
		skel.set_bone_pose_rotation(b_vela, q)
		await process_frame

		var dg: Vector3 = skel.get_bone_global_pose(b_driza).origin - skel.get_bone_global_rest(b_driza).origin
		var dl: Vector3 = skel.get_bone_pose_position(b_driza) - skel.get_bone_rest(b_driza).origin
		var pg: Vector3 = skel.get_bone_global_pose(b_pico).origin - skel.get_bone_global_rest(b_pico).origin
		var arr_g := clampf(dg.length() / 6.929, 0.0, 1.0)
		var arr_l := clampf(dl.length() / 6.929, 0.0, 1.0)
		print("%5.1f | GLOBAL %6.3f m -> arriado %.3f  (s=%.2f)  | LOCAL %6.3f m -> arriado %.3f  | pico GLOBAL %6.3f m -> %.3f"
			% [grados, dg.length(), arr_g, clampf(arr_g * 1.6, 0.0, 1.0),
			dl.length(), arr_l, pg.length(), clampf(pg.length() / 5.494, 0.0, 1.0)])
	quit()
