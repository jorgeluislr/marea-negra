extends Node
## Ajustes globales del juego (autoload "Ajustes"). Se ampliará con el menú de
## opciones. De momento guarda el VOLUMEN DE LA MÚSICA (0.0–1.0). El futuro menú
## llamará a set_volumen_musica() y todo lo que escuche la señal se actualiza en vivo.

signal volumen_musica_cambiado(valor: float)

@export_range(0.0, 1.0) var volumen_musica := 1.0   # 0 = silencio, 1 = máximo (nivel base)


func set_volumen_musica(v: float) -> void:
	volumen_musica = clampf(v, 0.0, 1.0)
	volumen_musica_cambiado.emit(volumen_musica)
