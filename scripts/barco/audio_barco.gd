extends Node3D
## Sonido del barco: ambiente (viento y mar) y efectos posicionados (agua en el costado, driza
## y flameo de lona).
##
## Se cuelga del barco, como los demás controles, y se monta solo: crea sus reproductores en
## runtime y encuentra el mástil y la vela midiendo las mallas, sin números a mano.
##
## Reglas de reparto, que no son arbitrarias:
##
##  - **Ambiente (viento, mar): NO posicional, y solo del barco activo.** Son el fondo de la
##    escena, no un objeto que suena en un sitio. Con dos barcos en pantalla, dos camas de
##    viento sonando a la vez se sumarían y quedaría el doble de fuerte; por eso se silencian
##    en los barcos que no gobiernas (grupo `barco_activo`).
##  - **Efectos: `AudioStreamPlayer3D`**, colgados del barco para que viajen con él y suenen
##    donde están — la driza en el mástil, el flameo en la vela.
##
## El viento **cruza entre dos camas** en vez de subir el volumen de una: la de viento fuerte
## lleva el silbido de la jarcia, que con viento flojo no debe oírse. Con un solo archivo no
## hay manera de que ese silbido aparezca solo cuando sopla de verdad.

const A_VIENTO_CALMA := preload("res://assets/audio/viento_calma.wav")
const A_VIENTO_FUERTE := preload("res://assets/audio/viento_fuerte.wav")
## Cama base: grabación de campo desde la proa de un velero (viento sostenido y agua rompiendo).
## Sustituye a `mar.wav`, que era sintético — una grabación real de exactamente la situación del
## juego gana por goleada, y trae detalles que el ruido filtrado no da. Lo sintético se queda
## para lo que una grabación NO puede hacer: responder a la fuerza del viento.
const A_PROA := preload("res://assets/audio/ambiente_proa.wav")
const A_AGUA := preload("res://assets/audio/agua_casco.wav")
const A_DRIZA := preload("res://assets/audio/driza.wav")
const A_FLAMEO := [
	preload("res://assets/audio/flameo_golpe_1.wav"),
	preload("res://assets/audio/flameo_golpe_2.wav"),
	preload("res://assets/audio/flameo_golpe_3.wav"),
	preload("res://assets/audio/flameo_golpe_4.wav"),
]

@export var activo := true
@export_range(-40.0, 12.0) var volumen := 0.0        ## Ajuste general, en dB.

@export_group("Viento y mar")
## Fuerza de viento a la que se oye solo la cama de calma, y a la que se oye solo la de fuerte.
@export var viento_min := 0.35
@export var viento_max := 1.45
## El viento sintetizado ya no es la cama principal: va ENCIMA de la grabacion de proa, y su
## trabajo es lo unico que un archivo fijo no puede hacer — responder a la fuerza y sacar el
## silbido de la jarcia cuando sopla. Por eso entra bastante mas bajo que antes.
@export_range(-40.0, 6.0) var viento_db := -14.0
@export_range(-40.0, 6.0) var proa_db := -6.0

@export_group("Agua en el costado")
@export_range(-40.0, 6.0) var agua_db := -7.0
## Velocidad a la que el agua suena a tope. Por debajo baja en proporción.
@export var agua_vel_max := 8.0

@export_group("Driza")
@export_range(-40.0, 12.0) var driza_db := 2.0
## Cuánto se tiene que mover un hueso de driza en un frame para considerar que se está izando.
@export var driza_umbral := 0.0015
@export var huesos_driza: Array[String] = ["driza", "driza_pico", "driza_foque"]

@export_group("Flameo")
@export_range(-40.0, 6.0) var flameo_db := -9.0
## Golpes por segundo con la vela del todo desventada.
@export var flameo_tasa_max := 5.0
## Por debajo de este desaprovechamiento del viento no se considera que flamee.
@export_range(0.0, 1.0) var flameo_umbral := 0.35

var _barco: Barco
var _skel: Skeleton3D
var _viento_a: AudioStreamPlayer
var _viento_b: AudioStreamPlayer
var _proa: AudioStreamPlayer
var _agua: AudioStreamPlayer3D
var _driza: AudioStreamPlayer3D
var _flameo: AudioStreamPlayer3D
var _huesos: PackedInt32Array = PackedInt32Array()
var _pos_ant: PackedVector3Array = PackedVector3Array()
var _t_flameo := 0.0
var _listo := false
var _primer_frame := true


func _ready() -> void:
	if not activo:
		set_process(false)
		return
	_montar.call_deferred()


## El barco se presenta en su `_ready` y con eso basta: este nodo es una pieza SUYA, no algo
## que tenga que ir a buscarlo subiendo por el árbol.
func configurar(barco: Barco) -> void:
	_barco = barco


## Centro de una malla del modelo, en espacio GLOBAL. Sirve para colocar los emisores sin
## números a mano: la driza suena en el mástil y el flameo en la vela, los tenga donde los tenga
## cada barco.
func _centro_de(nombre: String) -> Vector3:
	var l := _barco.find_children(nombre, "MeshInstance3D", true, false)
	if l.is_empty():
		return _barco.global_transform.origin
	var mi := l[0] as MeshInstance3D
	return mi.global_transform * mi.get_aabb().get_center()


func _amb(flujo: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = flujo
	p.volume_db = db
	add_child(p)
	p.play()
	return p


func _emisor(flujo: AudioStream, db: float, donde: Vector3, bucle: bool,
		alcance := 12.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = flujo
	p.volume_db = db
	# `unit_size` es la distancia a la que empieza a atenuar. Con 12 y la cámara de navegación
	# a ~24 m, todo lo del barco perdía 6 dB y se lo comía el ambiente.
	p.unit_size = alcance
	p.max_distance = 120.0
	_barco.add_child(p)
	p.global_position = donde
	if bucle:
		p.play()
	return p


func _montar() -> void:
	if _barco == null:
		return
	var es := _barco.find_children("*", "Skeleton3D", true, false)
	if not es.is_empty():
		_skel = es[0] as Skeleton3D

	_viento_a = _amb(A_VIENTO_CALMA, -80.0)
	_viento_b = _amb(A_VIENTO_FUERTE, -80.0)
	_proa = _amb(A_PROA, -80.0)

	var centro := _barco.global_transform.origin
	_agua = _emisor(A_AGUA, -80.0, centro, true)
	_driza = _emisor(A_DRIZA, driza_db + volumen, _centro_de("mastil_v3"), false, 30.0)
	_flameo = _emisor(A_FLAMEO[0], flameo_db + volumen, _centro_de("vela_mayor"), false)

	# Estado inicial de los huesos de driza, para detectar movimiento por diferencia.
	if _skel != null:
		for nm in huesos_driza:
			var b := _skel.find_bone(nm)
			if b >= 0:
				_huesos.append(b)
				_pos_ant.append(_skel.get_bone_pose_position(b))
	_listo = true
	print("audio_barco: %d huesos de driza vigilados, emisor driza en %s" % [
		_huesos.size(), str(_driza.global_position)])
	if OS.get_cmdline_user_args().has("probar_driza"):
		_probar_driza()


## Autotest: cierra la vela y vuelca lo que ve el detector, para no depender de pulsar teclas.
##   godot --path . --quit-after 900 -- probar_driza
func _probar_driza() -> void:
	await get_tree().create_timer(2.0).timeout
	print("--- cerrando vela ---")
	_barco.set_vela_trasera(false)
	for i in 90:
		var mov := 0.0
		for k in _huesos.size():
			var b: int = _huesos[k]
			mov = maxf(mov, _skel.get_bone_pose_position(b).distance_to(_skel.get_bone_rest(b).origin))
		if i % 6 == 0:
			print("  f%02d  recorrido=%.3f m  sonando=%s  vol=%.1f" % [
				i, mov, _driza.playing, _driza.volume_db])
		await get_tree().process_frame
	print("--- abriendo vela ---")
	_barco.set_vela_trasera(true)
	for i in 60:
		if i % 10 == 0:
			print("  izando f%02d sonando=%s" % [i, _driza.playing])
		await get_tree().process_frame


## ¿Se está izando o arriando algo ahora mismo?
##
## Se mira la posición LOCAL del hueso, no la global. `driza` y `driza_pico` cuelgan de
## `vela`, así que al TRIMAR su origen global se desplaza (medido: 9,3 cm a 45° en el pico)
## sin que nadie haya tocado la driza, y el sonido sonaba en bucle todo el rato — mezclado
## con el ambiente hasta parecer que no sonaba. En local solo cambia lo que mueve el propio
## `control_izado`, que es justo lo que hay que oír.
func _hay_driza() -> bool:
	if _skel == null:
		return false
	var mueve := false
	# El primer frame solo sirve para tomar referencia: al montar, los huesos todavia no tienen
	# su pose definitiva y el salto se detectaba como un izado fantasma nada mas arrancar.
	var estrena := _primer_frame
	_primer_frame = false
	for i in _huesos.size():
		var p := _skel.get_bone_pose_position(_huesos[i])
		if not estrena and p.distance_to(_pos_ant[i]) > driza_umbral:
			mueve = true
		_pos_ant[i] = p
	return mueve


func _process(delta: float) -> void:
	if not _listo:
		return

	# El ambiente solo suena en el barco que gobiernas (ver cabecera). Si no hay ninguno marcado
	# —porque el proyecto todavía no use el grupo— suena igual: mejor eso que quedarse mudo.
	var mando := _barco.is_in_group("barco_activo")
	if not mando and get_tree().get_nodes_in_group("barco_activo").is_empty():
		mando = true

	var f: float = Viento.fuerza
	var t := clampf((f - viento_min) / maxf(viento_max - viento_min, 0.01), 0.0, 1.0)
	var mudo := -80.0
	_viento_a.volume_db = (viento_db + volumen + linear_to_db(maxf(1.0 - t, 0.0001))) if mando else mudo
	_viento_b.volume_db = (viento_db + volumen + linear_to_db(maxf(t, 0.0001))) if mando else mudo
	# Un pelín de tono con la fuerza: el ruido filtrado solo no basta para notar la ráfaga.
	_viento_a.pitch_scale = 0.92 + 0.16 * t
	_viento_b.pitch_scale = 0.94 + 0.14 * t
	# La grabacion sube un poco con el viento, pero poco: ya lleva su propio oleaje dentro.
	_proa.volume_db = (proa_db + volumen + linear_to_db(clampf(0.75 + 0.25 * t, 0.0, 1.0))) if mando else mudo

	# Agua en el costado: por velocidad del casco.
	var vel := absf(_barco.velocidad)
	var vn := clampf(vel / maxf(agua_vel_max, 0.01), 0.0, 1.0)
	_agua.volume_db = agua_db + volumen + linear_to_db(maxf(vn, 0.0001))
	_agua.pitch_scale = 0.85 + 0.30 * vn

	# Driza: mientras algún hueso se mueve, suena. El archivo no va en bucle, así que si el
	# recorrido dura más se relanza solo al acabar; y si el jugador suelta a medias, termina de
	# sonar en vez de cortarse en seco, que es lo natural.
	if _hay_driza() and not _driza.playing:
		_driza.play()

	# Flameo: la cadencia sale de cuánto NO está aprovechando el viento la vela. `factor_viento`
	# es el mismo número que usa el casco para propulsarse, así que el sonido y el movimiento del
	# barco no pueden contradecirse.
	var desventa := 0.0
	desventa = 1.0 - clampf(_barco.factor_viento(), 0.0, 1.0)
	var abierta := _barco.vela_trasera
	if abierta and desventa > flameo_umbral and Viento.fuerza > 0.15:
		var tasa: float = flameo_tasa_max * (desventa - flameo_umbral) / maxf(1.0 - flameo_umbral, 0.01)
		_t_flameo += delta * tasa
		if _t_flameo >= 1.0:
			_t_flameo = randf() * 0.35
			_flameo.stream = A_FLAMEO[randi() % A_FLAMEO.size()]
			_flameo.pitch_scale = randf_range(0.88, 1.12)
			_flameo.play()
	else:
		_t_flameo = 0.0
