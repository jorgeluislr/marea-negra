extends MultiMeshInstance3D
## Indicador de viento sobre el agua: un ">>>" (tres puntas seguidas) que apunta
## hacia DONDE SOPLA el viento (Viento.direccion) y acompaña al barco.

@export var barco_path: NodePath      # barco al que sigue el indicador
@export var altura := 0.2             # altura sobre el agua (y=0)
@export var tam := 2.5                # tamaño del glifo
@export var desfase := 5.0            # distancia a barlovento (el lado de donde viene el viento)
@export_range(0.3, 1.5) var separacion := 0.6  # separación entre las 3 puntas (× tam)
@export var color := Color(0.55, 0.8, 1.0)

var _barco: Node3D


func _ready() -> void:
	_barco = get_node_or_null(barco_path) as Node3D
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _crear_glifo(tam)
	mm.instance_count = 1
	multimesh = mm
	material_override = _crear_material()


func _process(_delta: float) -> void:
	if multimesh == null:
		return
	# Giro hacia la dirección del viento (horizontal).
	var w := Viento.direccion
	w.y = 0.0
	if w.length() < 0.001:
		w = Vector3.FORWARD
	w = w.normalized()
	var base := Basis(Vector3.UP, atan2(w.x, w.z))
	# Colocado en BARLOVENTO (el lado de donde VIENE el viento = -dirección) y apuntando
	# a lo largo del viento → las flechas quedan siempre orientadas HACIA el barco.
	if _barco == null or not is_instance_valid(_barco):
		_barco = get_tree().get_first_node_in_group("barco_activo") as Node3D
		if _barco == null and barco_path != NodePath():
			_barco = get_node_or_null(barco_path) as Node3D
	var c := Vector3.ZERO
	if _barco:
		c = _barco.global_position
	var pos := c - w * desfase
	multimesh.set_instance_transform(0, Transform3D(base, Vector3(pos.x, altura, pos.z)))


func _crear_material() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, 0.2)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.8
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# Glifo ">>>": tres puntas (cabezas de flecha) seguidas a lo largo de +Z.
func _crear_glifo(s: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var largo := s * 0.5      # largo de cada punta
	var ancho := s * 0.4      # medio ancho de cada punta
	var sep := s * separacion # separación entre puntas
	for k in range(3):
		var cz := (float(k) - 1.0) * sep
		verts.append(Vector3(-ancho, 0.0, cz - largo * 0.5))
		verts.append(Vector3(ancho, 0.0, cz - largo * 0.5))
		verts.append(Vector3(0.0, 0.0, cz + largo * 0.5))
	var normals := PackedVector3Array()
	for _k in range(verts.size()):
		normals.append(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
