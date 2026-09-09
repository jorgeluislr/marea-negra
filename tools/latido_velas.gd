extends Node

## Busca el "latido" de las velas: mide, frame a frame, cuanto se MUEVE el pano y lo compara
## con las dos fuentes periodicas del juego (el bamboleo del casco y las rafagas del viento).
##
## Va con VENTANA a proposito: --headless no simula SoftBody3D y los puntos se quedan
## congelados, asi que todo mediria cero.

const SEGUNDOS := 30.0

## Que pano se mide. Estaba fija en la mayor, y la mayor lleva `capa_perchas = 0`: no choca con
## las capsulas, asi que su latido NO puede venir de un anclaje atrapado. El foque si choca.
@export var vela := "foque"

var _barco: Node3D
var _tela: Node
var _cuerpo: SoftBody3D
var _prev: PackedVector3Array
var _t := 0.0
var _serie: Array = []
var _n_puntos := 0
var _percha: Array = []
var _prev_percha := Vector3.ZERO
var _pico := 0.0
var _pico_t := 0.0


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_barco = esc.instantiate() as Node3D
	add_child(_barco)
	# CONDICIONES REALES: el viento conserva sus rafagas y su rolada. Anularlas deja la percha
	# quieta y el latido no aparece; es lo que paso en la primera medida.
	Viento.direccion_base = Vector3(0, 0, 1)   # de popa: el barco va a sotavento
	_barco.set("anclado", false)
	await get_tree().create_timer(2.5).timeout
	for h in _barco.get_children():
		if h.has_method("datos_depuracion") and str(h.get("nombre_malla")) == vela:
			_tela = h
	if _tela == null:
		print("no encuentro '%s'" % vela); get_tree().quit(1); return
	print("midiendo el latido de '%s' (choca con perchas: %s)"
		% [vela, (_tela.datos_depuracion()["cuerpo"] as SoftBody3D).collision_mask != 0])
	var d: Dictionary = _tela.datos_depuracion()
	_cuerpo = d["cuerpo"]
	# SoftBody3D no tiene get_point_count(): el numero de puntos sale de la mascara de anclajes
	_n_puntos = (d["fijo"] as PackedByteArray).size()
	_percha = _barco.find_children("Percha_botavara", "StaticBody3D", true, false)
	_prev = _puntos()
	print("midiendo %.0f s de la vela mayor (%d puntos, percha=%s)..." % [SEGUNDOS, _n_puntos, not _percha.is_empty()])


func _puntos() -> PackedVector3Array:
	var inv := _barco.global_transform.affine_inverse()
	var p := PackedVector3Array()
	for i in _n_puntos:
		p.append(inv * _cuerpo.get_point_transform(i))
	return p


func _physics_process(delta: float) -> void:
	if _cuerpo == null:
		return
	_t += delta
	var ahora := _puntos()
	var suma := 0.0
	for i in ahora.size():
		suma += ahora[i].distance_to(_prev[i])
	_prev = ahora
	var salto := 0.0
	if not _percha.is_empty():
		var pos: Vector3 = _barco.global_transform.affine_inverse() * (_percha[0] as Node3D).global_position
		salto = pos.distance_to(_prev_percha) / delta if _prev_percha != Vector3.ZERO else 0.0
		_prev_percha = pos
	_serie.append([_t, suma / maxf(ahora.size(), 1) / delta, Viento.fuerza, salto])
	if salto > _pico:
		_pico = salto
		_pico_t = _t
	if _t >= SEGUNDOS:
		_informe()
		get_tree().quit()


func _informe() -> void:
	var n := _serie.size()
	print("\nt(s)  mov_pano(m/s)  viento  barco_y")
	for k in range(0, n, maxi(1, n / 60)):
		var f: Array = _serie[k]
		print("%5.2f  %13.5f  %6.3f  %10.5f" % [f[0], f[1], f[2], f[3]])
	# frecuencia dominante del movimiento del pano, por transformada discreta
	var med := 0.0
	for f in _serie:
		med += f[1]
	med /= n
	var dur: float = _serie[n - 1][0] - _serie[0][0]
	print("\nmovimiento medio del pano: %.5f m/s" % med)
	print("periodo  amplitud_pano  amplitud_viento  amplitud_percha")
	var mejor := 0.0
	var mejor_p := 0.0
	for k in range(1, 80):
		var frec := float(k) / dur
		var re := [0.0, 0.0, 0.0]
		var im := [0.0, 0.0, 0.0]
		for f in _serie:
			var a: float = TAU * frec * f[0]
			for c in 3:
				re[c] += (f[c + 1] - (med if c == 0 else 0.0)) * cos(a)
				im[c] += (f[c + 1] - (med if c == 0 else 0.0)) * sin(a)
		var amp := []
		for c in 3:
			amp.append(2.0 * sqrt(re[c] * re[c] + im[c] * im[c]) / n)
		if amp[0] > mejor:
			mejor = amp[0]
			mejor_p = 1.0 / frec
		if amp[0] > med * 0.25 or amp[1] > 0.05 or amp[2] > 0.02:
			print("%7.2f s %13.5f %16.4f %15.5f" % [1.0 / frec, amp[0], amp[1], amp[2]])
	print("\n>> el pano late con periodo %.2f s (amplitud %.5f m/s)" % [mejor_p, mejor])
	print(">> (medido en el espacio del BARCO: el bamboleo del casco no cuenta)")
	print(">> el bamboleo del casco tiene periodo %.2f s, y su VELOCIDAD %.2f s" % [TAU / 1.2, TAU / 2.4])
	print(">> las rafagas del viento: %.2f s, %.2f s y %.2f s" % [TAU / 0.7, TAU / 1.9, TAU / 3.3])
