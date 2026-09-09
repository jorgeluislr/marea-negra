extends Node

## Perfil de radio del mastil a lo largo de su eje, y donde caen los anclajes de la bandera.
##
## Sirve para dimensionar los tramos de `perchas_solidas`: una capsula toma el radio MAXIMO de
## su tramo, asi que hay que saber cuanto varia el palo dentro de cada uno.

const BINS := 40


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	var barco := esc.instantiate() as Node3D
	add_child(barco)
	await get_tree().create_timer(2.5).timeout

	var skel := barco.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var mi := barco.find_children("mastil_v3", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var tr := _relativo(mi, skel)
	var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

	var c := Vector3.ZERO
	for v in vs:
		c += tr * v
	c /= float(vs.size())
	var cov := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for v in vs:
		var d := (tr * v) - c
		cov.x += d * d.x
		cov.y += d * d.y
		cov.z += d * d.z
	var eje := Vector3(0.577, 0.577, 0.577)
	for _it in 24:
		eje = (cov.x * eje.x + cov.y * eje.y + cov.z * eje.z).normalized()
	var mitad := 0.0
	for v in vs:
		mitad = maxf(mitad, absf(((tr * v) - c).dot(eje)))

	var rmax := []
	var n := []
	for _k in BINS:
		rmax.append(0.0); n.append(0)
	for v in vs:
		var q := (tr * v) - c
		var t: float = q.dot(eje)
		var k := int(clampf((t + mitad) / (mitad * 2.0), 0.0, 0.99999) * BINS)
		rmax[k] = maxf(rmax[k], (q - eje * t).length())
		n[k] += 1

	print("mastil: largo %.3f m, eje %s" % [mitad * 2.0, eje])
	for k in BINS:
		var t0 := -mitad + mitad * 2.0 * float(k) / BINS
		print("  %2d  t=%+6.3f..%+6.3f  r_max=%6.1f mm  (%d v)"
			% [k, t0, t0 + mitad * 2.0 / BINS, float(rmax[k]) * 1000.0, n[k]])

	# Donde estan las anclas de la bandera, en el mismo eje.
	for h in barco.get_children():
		if not h.has_method("datos_depuracion"):
			continue
		if str(h.get("nombre_malla")).find("bandera") < 0:
			continue
		var d: Dictionary = h.datos_depuracion()
		var cuerpo: SoftBody3D = d["cuerpo"]
		var fijo: PackedByteArray = d["fijo"]
		var tmin := 1e9; var tmax := -1e9; var dmin := 1e9; var dmax := 0.0
		for i in fijo.size():
			if fijo[i] != 1:
				continue
			var p: Vector3 = skel.global_transform.affine_inverse() * cuerpo.get_point_transform(i)
			var q := p - c
			var t: float = q.dot(eje)
			var r := (q - eje * t).length()
			tmin = minf(tmin, t); tmax = maxf(tmax, t)
			dmin = minf(dmin, r); dmax = maxf(dmax, r)
		print("bandera: %d anclas, t = %+.3f..%+.3f, radio %.1f..%.1f mm"
			% [fijo.count(1), tmin, tmax, dmin * 1000.0, dmax * 1000.0])
		var k0 := int(clampf((tmin + mitad) / (mitad * 2.0), 0.0, 0.99999) * BINS)
		var k1 := int(clampf((tmax + mitad) / (mitad * 2.0), 0.0, 0.99999) * BINS)
		print("  ocupa los bins %d..%d de %d" % [k0, k1, BINS])
		# Penetracion real en cada capsula del mastil, con el MISMO codigo que la comprobacion.
		var cuerpoPercha := barco.find_children("Percha_mastil_v3", "StaticBody3D", true, false)[0] as StaticBody3D
		for hijo in cuerpoPercha.get_children():
			var cs := hijo as CollisionShape3D
			var cap := cs.shape as CapsuleShape3D
			var tc := cuerpoPercha.global_transform * cs.transform
			var peor := 0.0
			var n_dentro := 0
			var rmin_local := 1e9
			for i in fijo.size():
				if fijo[i] != 1:
					continue
				var q := tc.affine_inverse() * cuerpo.get_point_transform(i)
				var media := maxf(cap.height * 0.5 - cap.radius, 0.0)
				var y: float = clampf(q.y, -media, media)
				var dd := q.distance_to(Vector3(0.0, y, 0.0))
				rmin_local = minf(rmin_local, dd)
				if cap.radius - dd > 0.0005:
					n_dentro += 1
					peor = maxf(peor, cap.radius - dd)
			print("  %s: r=%.1f mm h=%.2f m -> %d anclas dentro, hasta %.1f mm; dist minima al eje %.1f mm"
				% [cs.name, cap.radius * 1000.0, cap.height, n_dentro, peor * 1000.0, rmin_local * 1000.0])
		print("  escala global del esqueleto: %s" % skel.global_transform.basis.get_scale())
	get_tree().quit()


func _relativo(n: Node, raiz: Node) -> Transform3D:
	var t := Transform3D(); var x := n
	while x != null and x != raiz:
		if x is Node3D: t = (x as Node3D).transform * t
		x = x.get_parent()
	return t
