extends Node
## Corre las pruebas del juego sobre el mundo real y devuelve 1 si algo falla.
##
##     godot --path . tests/pruebas.tscn                 # todas (1 m 40 s)
##     godot --path . tests/pruebas.tscn -- tela         # solo un paquete
##     godot --path . tests/pruebas.tscn -- barco mundo  # los que quieras
##
## Poder correr UN paquete importa porque el ciclo de trabajo es escribir la prueba, verla
## FALLAR, arreglar y verla pasar: son dos tiradas por prueba, y esperar la batería entera cada
## vez sale caro. La completa se pasa igual antes de dar nada por bueno.
##
## Con ventana a proposito: `--headless` NO simula SoftBody3D (los puntos se quedan congelados
## y toda la tela mide "perfecta"), y con `-s` no existen los autoloads, asi que `Viento` no
## esta y no compila nada que lo use. Un test por paquete, en el orden en que se apoyan.

func _ready() -> void:
	_correr()


func _correr() -> void:
	# Margen para que el modelo cargue, la tela se monte y el reloj se estabilice.
	await get_tree().create_timer(4.0).timeout
	var pide := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		pide.append(String(a).to_lower())
	var m := MarcoPruebas.new()
	print("═══ Marea Negra: pruebas%s ═══"
		% ("" if pide.is_empty() else " (%s)" % ", ".join(pide)))
	if pide.is_empty() or pide.has("barco"):
		await BarcoTest.correr(m, get_tree())
	if pide.is_empty() or pide.has("artilleria"):
		await ArtilleriaTest.correr(m, get_tree())
	if pide.is_empty() or pide.has("tela"):
		await TelaTest.correr(m, get_tree())
	if pide.is_empty() or pide.has("ia"):
		await IaTest.correr(m, get_tree())
	if pide.is_empty() or pide.has("mundo"):
		await MundoTest.correr(m, get_tree())
	get_tree().quit(m.resumen())
