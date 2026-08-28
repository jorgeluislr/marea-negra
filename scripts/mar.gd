extends MeshInstance3D
## Gestiona el mar: shader de agua + estela bajo el barco + recorte del casco.
## Encuentra el barco por el grupo "barco_activo" (sin rutas fijas), así funciona con
## cualquier embarcación instanciada o cambiada en runtime. Lee la forma del recorte
## de los parámetros del propio barco.

@export var barco_path: NodePath  # opcional: respaldo si no hay nada en el grupo

const MAX_ESTELA := 16
const VIDA := 3.0
const INTERVALO := 0.12
const MOV_MINIMO := 0.05

var _mat: ShaderMaterial
var _barco: Node3D
var _estela: Array[Vector4] = []
var _t_gota := 0.0
var _ultima_pos := Vector3.ZERO


func _ready() -> void:
	_mat = material_override as ShaderMaterial
	if _mat == null:
		_mat = get_active_material(0) as ShaderMaterial
	if _mat == null:
		push_warning("mar.gd: el agua no tiene un ShaderMaterial (agua.gdshader).")
	for i in range(MAX_ESTELA):
		_estela.append(Vector4.ZERO)


func _barco_activo() -> Node3D:
	if _barco == null or not is_instance_valid(_barco):
		_barco = get_tree().get_first_node_in_group("barco_activo") as Node3D
		if _barco == null and barco_path != NodePath():
			_barco = get_node_or_null(barco_path) as Node3D
		if _barco:
			_ultima_pos = _barco.global_position
	return _barco


func _process(delta: float) -> void:
	if _mat == null:
		return

	# Envejecer los anillos de estela.
	for i in range(MAX_ESTELA):
		var e: Vector4 = _estela[i]
		if e.w > 0.5:
			e.z += delta
			if e.z > VIDA:
				e = Vector4.ZERO
			_estela[i] = e

	var barco := _barco_activo()
	if barco:
		_t_gota += delta
		var pos := barco.global_position
		if _t_gota >= INTERVALO and pos.distance_to(_ultima_pos) > MOV_MINIMO:
			_t_gota = 0.0
			_ultima_pos = pos
			_anadir_gota(pos)
		# Recorte del casco (forma y pose la aporta el propio barco).
		var fwd := -barco.global_transform.basis.z
		var fwd2 := Vector2(fwd.x, fwd.z)
		if fwd2.length() > 0.0001:
			fwd2 = fwd2.normalized()
		_mat.set_shader_parameter("recorte_activo", true)
		_mat.set_shader_parameter("barco_pos", Vector2(pos.x, pos.z))
		_mat.set_shader_parameter("barco_dir", fwd2)
		_mat.set_shader_parameter("barco_radio", barco.recorte_radio)
		_mat.set_shader_parameter("recorte_proa_exp", barco.recorte_proa_exp)
		_mat.set_shader_parameter("recorte_popa_exp", barco.recorte_popa_exp)
	else:
		_mat.set_shader_parameter("recorte_activo", false)

	_mat.set_shader_parameter("estela", _estela)


func _anadir_gota(pos: Vector3) -> void:
	var idx := 0
	var mas_viejo := -1.0
	for i in range(MAX_ESTELA):
		if _estela[i].w < 0.5:
			idx = i
			mas_viejo = -1.0
			break
		if _estela[i].z > mas_viejo:
			mas_viejo = _estela[i].z
			idx = i
	_estela[idx] = Vector4(pos.x, pos.z, 0.0, 1.0)
