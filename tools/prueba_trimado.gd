extends Node
## Cuanto estira el TRIMADO ahora que la tela ya no nace rota.
##
## Se fija el viento a una banda, se deja asentar, y se INVIERTE de golpe: la percha barre de
## un extremo al otro, que es el movimiento que abria las aristas hasta 1,13 m. Se mide durante
## el barrido y al terminar. El suavizado se pone por linea de ordenes:
##   godot --path . tools/prueba_trimado.tscn -- suav=1.8
@export var carpeta := ""

var _suav := 0.4
var _navegando := false

func _ready() -> void: _correr()

func _velas() -> Array:
	var bs := get_tree().get_nodes_in_group("barco_activo")
	if bs.is_empty():
		return []
	var l := []
	for v in bs[0].get_children():
		if v.has_method("datos_depuracion"):
			l.append(v)
	return l

func _medir(etq: String) -> void:
	var bs0 := get_tree().get_nodes_in_group("barco_activo")
	var b0: Node3D = bs0[0] if not bs0.is_empty() else null
	var linea := "%-18s vel %5.2f y %6.3f " % [etq,
		absf(b0.get("velocidad")) if b0 != null else 0.0, b0.position.y if b0 != null else 0.0]
	for v in _velas():
		var d: Dictionary = v.datos_depuracion()
		if d.is_empty():
			continue
		var cuerpo: SoftBody3D = d["cuerpo"]
		var ar: PackedInt32Array = d["aristas"]
		var l0: PackedFloat32Array = d["largo0"]
		var suma := 0.0; var peor := 0.0; var malos := 0; var peor_m := 0.0
		for e in l0.size():
			var largo: float = cuerpo.get_point_transform(ar[e * 2]).distance_to(
				cuerpo.get_point_transform(ar[e * 2 + 1]))
			var f: float = absf(largo - l0[e]) / maxf(l0[e], 0.0001)
			suma += f; peor = maxf(peor, f); peor_m = maxf(peor_m, absf(largo - l0[e]))
			if f > 0.25:
				malos += 1
		var apa: Variant = v.get("aparejo")
		var ang: float = rad_to_deg(apa.get("_ang_trim")) if apa != null else 0.0
		linea += "| %s med %5.2f%% peor %4.0f%% (%.3f m) >25%%:%3d trim %6.1f " % [
			v.name.substr(9, 6), 100.0 * suma / maxf(l0.size(), 1), 100.0 * peor, peor_m, malos, ang]
	print(linea)

## OJO: asignar `Viento.direccion` NO sirve — el autoload la recalcula cada frame desde
## `direccion_base` con su bamboleo y sus rafagas, y pisa lo que le pongas. Para tener viento
## de verdad constante hay que tocar la BASE y anular la variacion.
func _viento(dir: Vector3) -> void:
	Viento.direccion_base = dir
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	Viento.fuerza_base = 1.0

func _correr() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("suav="):
			_suav = float(a.substr(5))
		if a == "nav":
			_navegando = true
	# Viento a una banda mientras la tela se monta y se asienta.
	var t := 0.0
	while t < 6.0:
		_viento(Vector3(1, 0, 0))
		var bs := get_tree().get_nodes_in_group("barco_activo")
		if not bs.is_empty():
			bs[0].set("anclado", not _navegando)
		t += get_process_delta_time()
		await get_tree().physics_frame
	for v in _velas():
		var apa: Variant = v.get("aparejo")
		if apa != null:
			apa.trimado_suavizado = _suav
	print("=== suavizado de trimado = %.2f  |  %s ===" % [_suav, "NAVEGANDO" if _navegando else "anclado"])
	_medir("antes del barrido")

	# El viento rola 180 grados de golpe: la percha se va a la otra banda.
	t = 0.0
	var prox := 0.0
	while t < 14.0:
		_viento(Vector3(-1, 0, 0))
		t += get_process_delta_time()
		if t >= prox:
			_medir("barriendo t=%4.1f" % t)
			prox = t + 0.25
		await get_tree().physics_frame
	_medir("al terminar")
	get_tree().quit()
