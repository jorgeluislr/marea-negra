extends SceneTree
## Mide la pose de vela arriada sobre la piel real del .glb, con la misma cuenta que hace
## control_izado.gd. No usa el sistema de poses del Skeleton3D (fuera del árbol no evalúa):
## compone la matriz de piel a mano, global_pose * global_rest⁻¹, que para un hueso con los
## padres en reposo es  padre_global_rest * pose_local * rest⁻¹ * padre_global_rest⁻¹.
##   E:\Godot\...\Godot_console.exe --path . --headless -s tools/verificar_arriado.gd

func _tr(n: Node, raiz: Node) -> Transform3D:
	var t := Transform3D(); var x := n
	while x != null and x != raiz:
		if x is Node3D: t = (x as Node3D).transform * t
		x = x.get_parent()
	return t

## Matriz que aplica a la piel el arriado completo de un hueso (_izado = 0 en control_izado).
func _piel(s: Skeleton3D, hueso: String, recorrido: float, giro: float, eje: Vector3) -> Transform3D:
	var i := s.find_bone(hueso)
	if i < 0:
		print("  FALTA EL HUESO ", hueso); return Transform3D()
	var reposo := s.get_bone_rest(i)
	var base := reposo.basis
	if not is_zero_approx(giro):
		base = reposo.basis * Basis(eje.normalized(), deg_to_rad(giro))
	var pose := Transform3D(base, reposo.origin + reposo.basis.y.normalized() * -recorrido)
	var pg := Transform3D()
	var p := s.get_bone_parent(i)
	if p >= 0: pg = s.get_bone_global_rest(p)
	return pg * pose * reposo.affine_inverse() * pg.affine_inverse()

func _initialize() -> void:
	var b: Node3D = (load("res://scenes/barcos/balandra.tscn") as PackedScene).instantiate()
	var s := b.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hs: Array[String] = []
	for i in s.get_bone_count(): hs.append(s.get_bone_name(i))
	print("huesos: ", hs)
	# Los mismos valores que lleva scenes/barcos/balandra.tscn.
	var M := {}
	for i in s.get_bone_count(): M[s.get_bone_name(i)] = Transform3D()
	M["driza"] = _piel(s, "driza", 6.929, 0.0, Vector3(0, 0, 1))
	M["driza_pico"] = _piel(s, "driza_pico", 5.494, 19.7, Vector3(0, 0, 1))
	M["driza_foque"] = _piel(s, "driza_foque", 7.722, 0.0, Vector3(0, 0, 1))
	var datos := {}
	for nodo in b.find_children("*", "MeshInstance3D", true, false):
		var mi := nodo as MeshInstance3D
		if mi.mesh == null: continue
		var arr := mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var hu: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var pe: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var tr := _tr(mi, s)
		var antes := PackedVector3Array(); var ahora := PackedVector3Array()
		var acum := {}
		for k in vs.size():
			var p := tr * vs[k]
			var q := Vector3.ZERO
			if hu.size() >= vs.size() * 4:
				for j in 4:
					var w := pe[k * 4 + j]
					if w <= 0.0: continue
					var nb := s.get_bone_name(hu[k * 4 + j])
					acum[nb] = float(acum.get(nb, 0.0)) + w
					q += (M[nb] * p) * w
			else: q = p
			antes.append(p); ahora.append(q)
		datos[mi.name] = [antes, ahora, acum, vs.size()]
	var alto_bot := -INF
	for q in (datos["botavara"][1] as PackedVector3Array): alto_bot = maxf(alto_bot, q.y)
	print("botavara: cara alta en y = %.3f  (referencia de 'sobre botavara')" % alto_bot)
	for nm in ["pico", "soporte_pico", "vela_mayor", "aros_vela_mayor", "foque", "aros_foque", "escota_foque_e", "estay_proa", "botavara"]:
		if not datos.has(nm): print(nm, ": NO ESTA"); continue
		var d: Array = datos[nm]
		var antes: PackedVector3Array = d[0]; var ahora: PackedVector3Array = d[1]
		var ymin := INF; var ymax := -INF; var def := 0.0; var baja := 0.0
		for k in ahora.size():
			ymin = minf(ymin, ahora[k].y); ymax = maxf(ymax, ahora[k].y)
			baja = maxf(baja, antes[k].y - ahora[k].y)
			if k > 0:
				var l0 := (antes[k] - antes[0]).length(); var l1 := (ahora[k] - ahora[0]).length()
				def = maxf(def, absf(l1 - l0))
		# Eje largo de la pieza: el de mayor extensión (x o z del modelo), no uno fijo.
		var bb := AABB(ahora[0], Vector3.ZERO)
		for q in ahora: bb = bb.expand(q)
		var ex := bb.size.x >= bb.size.z
		var lo := ahora[0]; var hi := ahora[0]
		for q in ahora:
			var c := q.x if ex else q.z
			if c < (lo.x if ex else lo.z): lo = q
			if c > (hi.x if ex else hi.z): hi = q
		var dl := absf(hi.x - lo.x) if ex else absf(hi.z - lo.z)
		var inc := 0.0
		if dl > 0.01: inc = rad_to_deg(atan2(hi.y - lo.y, dl))
		var pesos := ""
		for k in d[2]: pesos += "%s=%.2f " % [k, float(d[2][k]) / float(d[3])]
		print("%-16s baja %.2f m  sobre botavara=[%+.3f,%+.3f]  incl=%+.2f  deform=%.3f mm  %s"
			% [nm, baja, ymin - alto_bot, ymax - alto_bot, inc, def * 1000.0, pesos])
	b.free()
	quit(0)
