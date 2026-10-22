extends Node
## Enciende el clima del juego: el calendario continúa la fecha guardada y el viento de fondo sopla
## como sopla el alisio en esa fecha (ver `ClimaCaribe`).
##
## Va en `main_world.tscn`, pero solo se enciende cuando ese mundo ES la escena que se juega. Las
## pruebas (`tests/pruebas.tscn`), la tormenta y las herramientas de `tools/` instancian el mismo
## mundo dentro de otra escena, fijan el viento a mano y no deben tocar el calendario guardado.


func _ready() -> void:
	var escena := get_tree().current_scene
	if escena != null and (escena == owner or escena == self):
		activar()


func activar() -> void:
	Calendario.persistente = true
	if not Calendario.cargar():
		Calendario.nueva_partida()
		Calendario.guardar()
	Viento.seguir_calendario = true
	Viento.aplicar_calendario()
	Oleaje.rolar_de_golpe()
