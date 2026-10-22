extends Node
## Corre las pruebas del juego sobre el mundo real y devuelve 1 si algo falla.
##
##     godot --path . tests/pruebas.tscn                     # todas (unos 5 min)
##     godot --path . tests/pruebas.tscn -- tela             # solo un paquete
##     godot --path . tests/pruebas.tscn -- barco mundo      # los que quieras
##     godot --path . tests/pruebas.tscn -- tela/costura     # un solo escenario
##     godot --path . tests/pruebas.tscn -- barco/timon tela/anclas
##
## Mientras se hace TDD se corre SOLO el escenario que se está escribiendo: son dos tiradas por
## prueba —verla fallar y verla pasar— y esperar la batería entera cada vez sale caro. La
## completa se pasa al final, antes de dar nada por bueno. Un filtro que no casa con nada es un
## FALLO, no un verde: el resumen dice qué escenarios hay.
##
## `barco`, `artilleria` y `tela` están partidos en escenarios que se preparan solos (rumbo,
## viento, ancla, modo) y dejan el barco como lo encontraron; `ia`, `mundo`, `mapa` y `origen`
## solo se pueden pedir enteros.
##
## Con ventana a propósito: `--headless` NO simula SoftBody3D (los puntos se quedan congelados
## y toda la tela mide "perfecta"), y con `-s` no existen los autoloads, así que `Viento` no
## está y no compila nada que lo use. Un test por paquete, en el orden en que se apoyan.

func _ready() -> void:
	_correr()


func _correr() -> void:
	# Margen para que el modelo cargue, la tela se monte y el reloj se estabilice.
	await get_tree().create_timer(4.0).timeout
	var m := MarcoPruebas.new()
	m.pedir(OS.get_cmdline_user_args())
	var pide := m.pedido()
	print("═══ Marea Negra: pruebas%s ═══"
		% ("" if pide.is_empty() else " (%s)" % ", ".join(pide)))
	var arbol := get_tree()
	if m.quiere_paquete("barco"):
		await BarcoTest.correr(m, arbol)
	if m.quiere_paquete("artilleria"):
		await ArtilleriaTest.correr(m, arbol)
	if m.quiere_paquete("tela"):
		await TelaTest.correr(m, arbol)
	if m.quiere_paquete("ia", false):
		await IaTest.correr(m, arbol)
	if m.quiere_paquete("mundo", false):
		await MundoTest.correr(m, arbol)
	if m.quiere_paquete("mapa", false):
		await MapaTest.correr(m, arbol)
	if m.quiere_paquete("clima"):
		await ClimaTest.correr(m, arbol)
	if m.quiere_paquete("hud"):
		await HudTest.correr(m, arbol)
	if m.quiere_paquete("travesia"):
		await TravesiaTest.correr(m, arbol)
	if m.quiere_paquete("municion"):
		await MunicionTest.correr(m, arbol)
	if m.quiere_paquete("menu"):
		await MenuTest.correr(m, arbol)
	# El último: monta su propio mundo a 50 km y suelta el de la batería.
	if m.quiere_paquete("origen", false):
		await OrigenTest.correr(m, arbol)
	get_tree().quit(m.resumen())
