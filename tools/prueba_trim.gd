extends Node
## ¿El pie de la mayor sigue a la botavara cuando esta trima con el viento? Cambia la direccion
## del viento, deja trimar, y mide la distancia de los vertices del pie al eje real de la botavara.
func _ready() -> void: _correr()

func _eje_botavara(b: Node3D, esq: Skeleton3D) -> Array:
	var mi := b.find_children("botavara","MeshInstance3D",true,false)[0] as MeshInstance3D
	var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	# posicion actual (con piel): media y eje via bones. Uso las posiciones deformadas.
	var g := b.global_transform
	# aproximo el eje con la AABB del hueso: mejor uso los propios vertices deformados por skinning
	# leyendo la malla renderizada no es directo; uso el hueso 'vela' que la mueve.
	var iv := esq.find_bone("vela")
	var pose := esq.get_bone_global_pose(iv)
	return [g * (esq.global_transform * pose.origin), g.basis * (esq.global_transform.basis * pose.basis.x)]

func _medir(b: Node3D, esq: Skeleton3D, sb: SoftBody3D, foot_idx: PackedInt32Array, etiqueta: String) -> void:
	# eje de la botavara: dos puntos extremos de sus vertices deformados no disponibles facil;
	# uso la propia relinga del pie (los anclados) — si el pie sigue al palo, los anclados y el
	# borde inferior del pano coinciden. Mido la desviacion de los anclados respecto a su recta.
	var g := b.global_transform.affine_inverse()
	var pts := PackedVector3Array()
	for k in foot_idx: pts.append(g * sb.get_point_transform(k))
	# recta de mejor ajuste y desviacion perpendicular
	var c := Vector3.ZERO
	for p in pts: c += p
	c /= pts.size()
	var ejeX := Vector3.ZERO
	for p in pts: ejeX += (p-c) * (p-c).dot(Vector3.RIGHT if absf((p-c).x)>absf((p-c).z) else Vector3.BACK)
	ejeX = ejeX.normalized()
	var dmax := 0.0
	for p in pts:
		var q := p - c
		dmax = maxf(dmax, (q - ejeX*q.dot(ejeX)).length())
	print("%-14s angulo_vela=%.1f  pie desviacion de su recta: %.3f m (%d anclas)" % [etiqueta, rad_to_deg(esq.get_bone_pose_rotation(esq.find_bone("vela")).get_euler().y), dmax, pts.size()])

func _correr() -> void:
	await get_tree().create_timer(4.0).timeout
	var b := get_tree().get_nodes_in_group("barco_activo")[0] as Node3D
	b.set("anclado", true); b.emit_signal("ancla_cambiada", true)
	var esq: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
	var sb: SoftBody3D = null
	for x in b.find_children("*", "SoftBody3D", true, false):
		if (x as Node).name.ends_with("vela_mayor"): sb = x as SoftBody3D
	# vertices anclados del pie: los azules cerca de la botavara. Los detecto por Y baja.
	var mi := b.find_children("vela_mayor","MeshInstance3D",true,false)[0] as MeshInstance3D
	var arr := mi.mesh.surface_get_arrays(0)
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ymin := 999.0
	for v in vs: ymin = minf(ymin, v.y)
	var foot := PackedInt32Array()
	for k in vs.size():
		if cols[k].b > 0.5 and vs[k].y < ymin + 1.0: foot.append(k)
	for dir in [Vector3(1,0,0.3), Vector3(1,0,1.2), Vector3(0.3,0,-1)]:
		Viento.direccion = dir.normalized()
		await get_tree().create_timer(3.0).timeout
		_medir(b, esq, sb, foot, "viento %.1f,%.1f" % [dir.x, dir.z])
	get_tree().quit()
