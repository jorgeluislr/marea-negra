extends Node

## En que espacio gira el shader la bandera, y en que espacio DEBERIA girarla.
##
## `TelaShader` calcula el eje del mastil como la vertical del MUNDO llevada al espacio local de
## la malla: `mi.global_transform.basis.inverse() * UP`. Pero la malla de la bandera esta
## SKINNEADA al hueso `giro_bandera`, y en Godot la piel se aplica DESPUES del vertex(), asi que
## lo que el shader mueve son coordenadas de REPOSO y luego la piel las rota. Si la piel no es la
## identidad, el eje que usa el shader no es el eje del mastil.
##
## Se compara: el eje que usa el shader, el eje real del mastil, y el eje que habria que usar.

func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(1))
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	var b := esc.instantiate() as Node3D
	add_child(b)
	await get_tree().create_timer(3.0).timeout

	var skel := b.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var mi := b.find_children("bandera", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var hueso := skel.find_bone("giro_bandera")

	print("malla 'bandera': padre %s, skeleton=%s, skin=%s"
		% [mi.get_parent().name, mi.skeleton, "si" if mi.skin != null else "NO"])
	print("  su global_transform.basis:")
	var bs := mi.global_transform.basis
	print("    x %s\n    y %s\n    z %s" % [bs.x, bs.y, bs.z])
	print("  escala %s" % bs.get_scale())

	# El eje que USA el shader.
	var eje_shader := (bs.inverse() * Vector3.UP).normalized()
	# El eje REAL del mastil, en mundo.
	var rest := skel.get_bone_global_rest(hueso)
	var eje_mastil_mundo := (skel.global_transform.basis * (rest.basis * Vector3(0, 1, 0))).normalized()
	# La piel: de espacio de reposo de la malla a espacio del esqueleto.
	var piel := rest
	if mi.skin != null:
		for i in mi.skin.get_bind_count():
			if mi.skin.get_bind_bone(i) == hueso or mi.skin.get_bind_name(i) == "giro_bandera":
				piel = rest * mi.skin.get_bind_pose(i)
	# Eje del mastil llevado al espacio en el que el shader mueve los vertices (reposo de malla).
	var eje_correcto := (piel.affine_inverse().basis
		* (skel.global_transform.basis.inverse() * eje_mastil_mundo)).normalized()

	print("\neje del mastil en MUNDO           %s" % eje_mastil_mundo)
	print("eje que USA el shader (local)     %s" % eje_shader)
	print("eje CORRECTO (espacio de reposo)  %s" % eje_correcto)
	print("\ndesfase entre el que usa y el correcto: %.1f grados"
		% rad_to_deg(acos(clampf(absf(eje_shader.dot(eje_correcto)), -1.0, 1.0))))
	print("inclinacion real del mastil: %.1f grados sobre la vertical"
		% rad_to_deg(acos(clampf(eje_mastil_mundo.dot(Vector3.UP), -1.0, 1.0))))
	get_tree().quit()
