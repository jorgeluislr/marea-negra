extends Node
## Ajustes globales del juego (autoload "Ajustes"). Se ampliará con el menú de
## opciones. Guarda el VOLUMEN DE LA MÚSICA (0.0–1.0) y la DIFICULTAD del capitán de IA. El futuro
## menú llamará a los `set_*` y todo lo que escuche las señales se actualiza en vivo.
##
## Se guardan en `ruta` (un `ConfigFile` en `user://`) cada vez que cambian por un `set_*`, y se
## leen al arrancar. Las pruebas cambian `ruta` antes de tocar nada, para no pisar los del jugador.

signal volumen_musica_cambiado(valor: float)
signal dificultad_cambiada(nivel: String)

## Los niveles de dificultad, de más fácil a más difícil. Lo que cambia cada uno vive en
## `CapitanIA.NIVELES`, que es quien lo usa; aquí solo se elige.
const DIFICULTADES := ["facil", "normal", "dificil"]

@export_range(0.0, 1.0) var volumen_musica := 1.0   # 0 = silencio, 1 = máximo (nivel base)
## Dificultad del capitán de IA: «facil», «normal» o «dificil». Ver `CapitanIA.NIVELES`.
@export_enum("facil", "normal", "dificil") var dificultad := "normal"
## Semilla de la puntería de los capitanes de IA. 0 = una distinta en cada partida; otra cifra hace
## que se repitan los mismos errores, que es lo que necesitan las pruebas y las medidas.
var semilla := 0

var ruta := "user://ajustes.cfg"


func _ready() -> void:
	cargar()


func set_volumen_musica(v: float) -> void:
	volumen_musica = clampf(v, 0.0, 1.0)
	volumen_musica_cambiado.emit(volumen_musica)
	guardar()


func set_dificultad(nivel: String) -> void:
	if not nivel in DIFICULTADES:
		push_warning("Ajustes: dificultad desconocida «%s»; se queda en «%s»." % [nivel, dificultad])
		return
	dificultad = nivel
	dificultad_cambiada.emit(dificultad)
	guardar()


func guardar() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volumen_musica", volumen_musica)
	cfg.set_value("juego", "dificultad", dificultad)
	return cfg.save(ruta) == OK


## Lee los ajustes guardados. Devuelve false, sin tocar nada, si no había archivo.
func cargar() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(ruta) != OK:
		return false
	volumen_musica = clampf(float(cfg.get_value("audio", "volumen_musica", volumen_musica)), 0.0, 1.0)
	var d := String(cfg.get_value("juego", "dificultad", dificultad))
	if d in DIFICULTADES:
		dificultad = d
	return true
