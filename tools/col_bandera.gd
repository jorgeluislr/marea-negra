extends Node
## Que trae la capa `Col` de la bandera de la balandra: R (cuanto se mueve), G (soy bandera),
## B (ancla). Es lo que necesita `TelaShader` para ondear sin fisica, como la de la lancha.

func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit(1))
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	var b := esc.instantiate() as Node3D
	add_child(b)
	await get_tree().create_timer(2.0).timeout
	for nombre in ["bandera", "vela_mayor", "foque"]:
		var l := b.find_children(nombre, "MeshInstance3D", true, false)
		if l.is_empty():
			print("%-12s no encontrada" % nombre); continue
		var mi := l[0] as MeshInstance3D
		var malla: Mesh = mi.mesh
		if mi is SoftBody3D:
			# El SoftBody sustituye la malla; la de autor la guarda el control de tela.
			for h in b.get_children():
				if h.has_method("datos_depuracion") and str(h.get("nombre_malla")) == nombre:
					malla = (h.get("_malla_original") as MeshInstance3D).mesh
		var arr := malla.surface_get_arrays(0)
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		if cols.is_empty():
			print("%-12s SIN capa de color" % nombre); continue
		var rmin := 2.0; var rmax := -1.0; var gmin := 2.0; var gmax := -1.0
		var n_b := 0
		var suma_r := 0.0
		for c in cols:
			rmin = minf(rmin, c.r); rmax = maxf(rmax, c.r)
			gmin = minf(gmin, c.g); gmax = maxf(gmax, c.g)
			suma_r += c.r
			if c.b > 0.5: n_b += 1
		print("%-12s %5d verts   R %.3f..%.3f (media %.3f)   G %.3f..%.3f   azules %d"
			% [nombre, cols.size(), rmin, rmax, suma_r / cols.size(), gmin, gmax, n_b])
	get_tree().quit()
