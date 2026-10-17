extends Node3D

## Cuánto se hunde un `SoftBody3D` en un cuerpo estático, sin barco ni viento de por medio.
##
## Un paño de 2 × 2 m con aristas de 25 cm (como la mayor), cogido por dos esquinas, cae con una
## gravedad dada sobre una forma de 20 cm de radio, y se mide lo más hondo que queda un punto
## suyo dentro de ella tras asentarse. Separa el CONTACTO del motor de todo lo demás:
##
##     godot --path . tools/lona_contra_capsula.tscn --max-fps 120 -- capsula 40
##     godot --path . tools/lona_contra_capsula.tscn --max-fps 120 -- caja 40
##     godot --path . tools/lona_contra_capsula.tscn --max-fps 120 -- esfera 10 20
##
## Argumentos: forma (capsula, caja, esfera, cilindro), gravedad en m/s², precisión del solver y
## altura inicial del paño sobre el eje (por debajo de 0,20 nace atravesando la forma).

const R := 0.20


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func():
		push_error("se acabo el tiempo"); get_tree().quit(1))
	var a := OS.get_cmdline_user_args()
	var forma: String = a[0] if a.size() > 0 else "capsula"
	var g := float(a[1]) if a.size() > 1 else 40.0
	var prec := int(a[2]) if a.size() > 2 else 20
	# Altura del paño sobre el eje de la forma al empezar: con menos de R nace ATRAVESÁNDOLA.
	var alto := float(a[3]) if a.size() > 3 else R + 0.2
	PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, g)

	# La forma, tumbada a lo largo de X, con su centro en el origen.
	var sh: Shape3D
	match forma:
		"capsula":
			var c := CapsuleShape3D.new(); c.radius = R; c.height = 3.0; sh = c
		"cilindro":
			var c := CylinderShape3D.new(); c.radius = R; c.height = 3.0; sh = c
		"caja":
			var c := BoxShape3D.new(); c.size = Vector3(2 * R, 3.0, 2 * R); sh = c
		"esfera":
			var c := SphereShape3D.new(); c.radius = R; sh = c
	var st := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = sh
	cs.rotation = Vector3(0, 0, PI / 2)
	st.add_child(cs)
	add_child(st)

	# El paño, horizontal a 40 cm por encima, cogido por las dos esquinas de un lado para que
	# cuelgue sobre la forma y no resbale entero.
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	pm.subdivide_width = 7
	pm.subdivide_depth = 7
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pm.get_mesh_arrays())
	var sb := SoftBody3D.new()
	sb.mesh = am
	sb.position = Vector3(0, alto, 0.0)
	sb.simulation_precision = prec
	sb.total_mass = 1.0
	sb.linear_stiffness = 0.9
	add_child(sb)
	await get_tree().physics_frame
	var vs: PackedVector3Array = am.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var anclas := []
	for i in vs.size():
		if absf(vs[i].z + 1.0) < 0.01 and absf(absf(vs[i].x) - 1.0) < 0.01:
			var n := Node3D.new()
			add_child(n)
			n.global_position = sb.to_global(vs[i])
			sb.set_point_pinned(i, true, n.get_path())
			anclas.append(i)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.0, 4.0)
	cam.look_at(Vector3.ZERO)

	var t := 0.0
	var peor := 0.0
	while t < 4.0:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	var dentro := 0
	for i in vs.size():
		var p := sb.get_point_transform(i)
		var d := _dentro(forma, p)
		if d > 0.0:
			dentro += 1
			peor = maxf(peor, d)
	print("RESULTADO %s g=%.0f precision=%d alto=%.2f: %d de %d puntos dentro, el más hondo %.1f mm"
		% [forma, g, prec, alto, dentro, vs.size(), peor * 1000.0])
	get_tree().quit(0)


## Cuánto está un punto DENTRO de la forma (positivo) o fuera (negativo), en metros.
func _dentro(forma: String, p: Vector3) -> float:
	match forma:
		"capsula", "cilindro":
			if absf(p.x) > 1.5:
				return -1.0
			return R - Vector2(p.y, p.z).length()
		"caja":
			if absf(p.x) > 1.5:
				return -1.0
			return minf(R - absf(p.y), R - absf(p.z))
		"esfera":
			return R - p.length()
	return -1.0
