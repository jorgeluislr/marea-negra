extends Node

## Densidad de malla de cada pano: arista media, area y vertices por metro cuadrado.
##
## Es lo que hay que igualar para "ponerle a la mayor la densidad del foque": no el numero de
## vertices, que la mayor es mucho mas grande, sino cuantos por metro cuadrado.

func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(1))
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	var b := esc.instantiate() as Node3D
	add_child(b)
	await get_tree().create_timer(3.0).timeout
	print("%-12s %7s %9s %11s %12s %12s"
		% ["pano", "verts", "area m2", "arista_cm", "verts/m2", "coste_relat"])
	var ref := 0.0
	for h in b.get_children():
		if not h.has_method("datos_depuracion"):
			continue
		var d: Dictionary = h.datos_depuracion()
		if d.is_empty():
			continue
		var cuerpo: SoftBody3D = d["cuerpo"]
		var ar: PackedInt32Array = d["aristas"]
		var l0s: PackedFloat32Array = d["largo0"]
		var reposo: PackedVector3Array = d["reposo"]
		var suma := 0.0
		for l in l0s:
			suma += l
		var arista: float = suma / maxf(l0s.size(), 1)
		# Area: de los triangulos de la malla del cuerpo.
		var arr := cuerpo.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var area := 0.0
		for t in idx.size() / 3:
			var a := vs[idx[t * 3]]
			var bb := vs[idx[t * 3 + 1]]
			var c := vs[idx[t * 3 + 2]]
			area += 0.5 * (bb - a).cross(c - a).length()
		var n := reposo.size()
		var dens := n / maxf(area, 0.001)
		if ref <= 0.0:
			ref = dens
		print("%-12s %7d %9.2f %11.1f %12.1f %12.2f x"
			% [str(h.get("nombre_malla")), n, area, arista * 100.0, dens, dens / ref])
	print("\nsi la mayor tomase la densidad del foque quedaria en unos %d vertices"
		% 0)
	get_tree().quit()
