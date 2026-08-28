extends AudioStreamPlayer
## Música de fondo en bucle.
## El nivel BASE es el 'Volume Db' del nodo (lo ajustas en el Inspector: súbelo para
## más volumen). El autoload "Ajustes" (Ajustes.volumen_musica, 0.0–1.0) lo ESCALA
## por encima, para el futuro slider de opciones; se actualiza en vivo.

@export var ruta := "res://assets/audio/musica.ogg"
@export_range(0.0, 1.0) var volumen_defecto := 1.0   # volumen si aún no existe Ajustes

var _base_db := 0.0
var _vol := 1.0


func _ready() -> void:
	_base_db = volume_db   # nivel base que pusiste en el Inspector

	var pista: AudioStream = stream
	if pista == null:
		pista = load(ruta)
	if pista == null:
		push_warning("musica.gd: no se encontró la pista en %s" % ruta)
		return
	if pista is AudioStreamOggVorbis:
		(pista as AudioStreamOggVorbis).loop = true
	elif pista is AudioStreamMP3:
		(pista as AudioStreamMP3).loop = true
	elif pista is AudioStreamWAV:
		(pista as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream = pista

	var ajustes := get_node_or_null("/root/Ajustes")
	if ajustes:
		_vol = ajustes.volumen_musica
		ajustes.volumen_musica_cambiado.connect(_on_volumen)
	else:
		_vol = volumen_defecto

	_aplicar()
	play()


func _on_volumen(v: float) -> void:
	_vol = v
	_aplicar()


func _aplicar() -> void:
	# Nivel final = base (Inspector) + escala del ajuste (0..1 → -inf..0 dB).
	var escala_db := linear_to_db(_vol) if _vol > 0.001 else -80.0
	volume_db = _base_db + escala_db
