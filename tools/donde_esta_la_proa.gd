extends Node

## Mide, DENTRO del juego, en que sentido del eje Z del barco cae la proa.
##
## Va como ESCENA y no con `-s`: sin autoloads, `barco.gd` no compila porque usa `Viento`.
## Y hace falta medirlo asi porque deducirlo de la basis del nodo `Modelo` escrita en el
## .tscn es donde se confunden filas con columnas y la carga acaba en el lado contrario.

func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	var b := esc.instantiate()
	add_child(b)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var marcas := {}
	for nombre in ["botalon", "cranse_botalon", "timon_retopo", "mastil_v3"]:
		var l := b.find_children(nombre, "MeshInstance3D", true, false)
		if l.is_empty():
			continue
		var mi := l[0] as MeshInstance3D
		var t := Transform3D()
		var x: Node = mi
		while x != null and x != b:
			if x is Node3D:
				t = (x as Node3D).transform * t
			x = x.get_parent()
		var c: Vector3 = t * mi.mesh.get_aabb().get_center()
		marcas[nombre] = c
		print("%-16s respecto al barco: (%+7.3f, %+7.3f, %+7.3f)" % [nombre, c.x, c.y, c.z])
	var helm := b.get_node_or_null("HelmPosition") as Node3D
	if helm != null:
		print("%-16s (timonel, popa):   (%+7.3f, %+7.3f, %+7.3f)"
			% ["HelmPosition", helm.position.x, helm.position.y, helm.position.z])
	var modelo := b.get_node_or_null("Modelo") as Node3D
	if modelo != null:
		var bs := modelo.transform.basis
		print("\nbasis del nodo Modelo: X=(%+.0f,%+.0f,%+.0f) Y=(%+.0f,%+.0f,%+.0f) Z=(%+.0f,%+.0f,%+.0f)"
			% [bs.x.x, bs.x.y, bs.x.z, bs.y.x, bs.y.y, bs.y.z, bs.z.x, bs.z.y, bs.z.z])
	if marcas.has("botalon"):
		var pz: float = marcas["botalon"].z
		print(">> la PROA del barco cae en %sZ (botalon en Z=%+.3f)" % ["+" if pz > 0.0 else "-", pz])
	var carga := b.get_node_or_null("Cargamento")
	if carga != null:
		for h in carga.get_children():
			var n3 := h as Node3D
			print("carga %-22s (%+7.3f, %+7.3f, %+7.3f)"
				% [n3.name, n3.position.x, n3.position.y, n3.position.z])
	get_tree().quit()
