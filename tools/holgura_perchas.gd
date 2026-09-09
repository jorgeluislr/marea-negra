extends Node

## Cuanto se puede adelgazar cada capsula sin dejar de parar el pano: mide la distancia de los
## puntos ANCLADOS al eje de cada percha, y la compara con el radio que tiene puesto.
##
## Tambien mide el radio REAL de la percha por tramos: una capsula tiene radio constante y los
## palos son conicos, asi que arriba sobra tanto como se estrecha el palo.

var _barco: Node3D


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_barco = esc.instantiate() as Node3D
	add_child(_barco)
	await get_tree().create_timer(2.5).timeout
	var perchas := []
	for c in _barco.find_children("Percha_*", "StaticBody3D", true, false):
		var cs := c.get_child(0) as CollisionShape3D
		var cap := cs.shape as CapsuleShape3D
		perchas.append({"nodo": c, "forma": cs, "r": cap.radius, "h": cap.height,
						"nombre": c.name.replace("Percha_", "")})
	# radio real de cada percha por tramos, medido de su malla
	print("\n== radio REAL de cada percha por tramos (la capsula usa el maximo) ==")
	for per in perchas:
		var l := _barco.find_children(per["nombre"], "MeshInstance3D", true, false)
		if l.is_empty():
			continue
		var mi := l[0] as MeshInstance3D
		var t: Transform3D = (per["nodo"] as Node3D).global_transform * (per["forma"] as Node3D).transform
		var inv := t.affine_inverse()
		var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var media: float = maxf(per["h"] * 0.5 - per["r"], 0.0)
		var tramos := []
		for k in 6:
			tramos.append([1e9, 0.0, 0])
		for v in vs:
			var q := inv * (mi.global_transform * v)
			var f: float = clampf((q.y + media) / maxf(media * 2.0, 1e-6), 0.0, 0.9999)
			var k := int(f * 6)
			var r := Vector2(q.x, q.z).length()
			tramos[k][0] = minf(tramos[k][0], r)
			tramos[k][1] = maxf(tramos[k][1], r)
			tramos[k][2] += 1
		var s := "%-12s capsula r=%.3f  ->  " % [per["nombre"], per["r"]]
		for k in 6:
			if tramos[k][2] > 0:
				s += "[%.3f] " % tramos[k][1]
			else:
				s += "[  -  ] "
		print(s + "  (radio maximo real por tramo, de un extremo al otro)")
	# distancia de los anclados al eje de cada percha
	print("\n== distancia de los puntos ANCLADOS al eje de cada percha ==")
	print("%-12s %-12s %9s %9s %9s  %s" % ["vela", "percha", "r_capsula", "min_ancla", "sobra", "veredicto"])
	for h in _barco.get_children():
		if not h.has_method("datos_depuracion"):
			continue
		var d: Dictionary = h.datos_depuracion()
		if not d.has("cuerpo"):
			continue
		var cuerpo: SoftBody3D = d["cuerpo"]
		var fijo: PackedByteArray = d["fijo"]
		for per in perchas:
			var t: Transform3D = (per["nodo"] as Node3D).global_transform * (per["forma"] as Node3D).transform
			var inv := t.affine_inverse()
			var media: float = maxf(per["h"] * 0.5 - per["r"], 0.0)
			var dmin := 1e9
			var n_dentro := 0
			for i in fijo.size():
				if fijo[i] != 1:
					continue
				var q := inv * cuerpo.get_point_transform(i)
				var y: float = clampf(q.y, -media, media)
				var dd := q.distance_to(Vector3(0.0, y, 0.0))
				dmin = minf(dmin, dd)
				if dd < per["r"]:
					n_dentro += 1
			if dmin > 1e8:
				continue
			var sobra: float = per["r"] - dmin
			if n_dentro > 0:
				print("%-12s %-12s %9.4f %9.4f %+9.4f  %d anclados dentro: hay que quitar %.1f mm"
					% [str(h.get("nombre_malla")), per["nombre"], per["r"], dmin, sobra,
					   n_dentro, sobra * 1000.0])
	get_tree().quit()
