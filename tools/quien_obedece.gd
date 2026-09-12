extends Node

## ¿Cuántos barcos obedecen las teclas del jugador? Con la entrada donde está hoy —dentro de
## `Barco`— la respuesta es TODOS, y por eso hay que sacarla de ahí.
##
## `Input.is_key_pressed` y `_unhandled_input` no distinguen destinatario: son globales y el
## evento se reparte a todo el árbol. Mientras el juego instancia un solo barco no se nota, así
## que este fallo no se puede ver hasta que hay dos en el agua — que es exactamente lo que hace
## falta para un capitán de IA.
##
## Se miden las tres familias de mando por separado, porque salen de sitios distintos del código
## y podrían arreglarse a medias:
##
##   · TIMÓN     — `Input.is_key_pressed(KEY_A/D)` leído en `_physics_process`. Se mide el GIRO
##                 en grados con la A mantenida un segundo.
##   · MANIOBRA  — W/S/ESPACIO por `_unhandled_input`. Se mira si cambió el estado de la vela.
##   · ARTILLERÍA— Q/E/R por `_unhandled_input`. Se cuentan los disparos que salen de verdad,
##                 enganchándose a la señal `disparo` de cada pieza: contar `banda_apuntada`
##                 no valdría, porque apuntar no gasta pólvora y un barco recargando no dispara.
##
## Las dos balandras van separadas 60 m: con sus cajas de casco solapadas `move_and_slide`
## empuja una contra otra y el giro medido llevaría dentro el empujón de la vecina.
##
## No mide tela, así que vale con `--headless` (más rápido y sin ventana):
##     godot --path . --headless tools/quien_obedece.tscn

const SEPARACION := 60.0
const ESPERA := 4.0        ## Para que el modelo cargue y la artillería se monte (es diferida).
const RODAJE := 3.0        ## Navegando, para que cojan velocidad antes de tocar el timón.
const MANTENER := 1.0      ## Cuánto se mantiene pulsada la A.
const GIRO_MINIMO := 1.0   ## Grados a partir de los cuales se considera que obedeció.

var _barcos: Array[Node3D] = []
var _disparos := {}


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	for i in 2:
		var b := esc.instantiate() as Node3D
		b.name = "Balandra%d" % i
		add_child(b)
		b.global_position = Vector3(SEPARACION * float(i), b.global_position.y, 0.0)
		_barcos.append(b)
		_disparos[b] = 0
	# El JUGADOR va en el primero. Es lo que decide quién obedece el teclado: el mando cuelga
	# del barco y traduce teclas en órdenes, así que el segundo barco no puede oírlas.
	(_barcos[0] as Barco).tomar_mando_jugador()
	await get_tree().create_timer(ESPERA).timeout
	_enganchar_canones()

	print("═══ ¿Quién obedece las teclas? ═══")
	print("dos balandras, sólo una lleva jugador a bordo\n")

	await _medir_timon()
	await _medir_maniobra()
	await _medir_artilleria()
	get_tree().quit(0)


## Cada pieza avisa cuando escupe. Es la única cuenta honesta de un disparo: `disparar_banda`
## devuelve cuántas respondieron, pero nadie llama a ese método desde fuera y las que están
## recargando no salen.
func _enganchar_canones() -> void:
	for b in _barcos:
		for n in b.find_children("*", "", true, false):
			if n.has_method("disparar") and n.has_signal("disparo"):
				n.connect("disparo", func(_d: Vector3, _h: Vector3): _disparos[b] += 1)


func _viento_fijo() -> void:
	# Asignar `Viento.direccion` no fija nada: el autoload lo recalcula cada frame desde la BASE.
	Viento.direccion_base = Vector3(0, 0, -1)
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	Viento.fuerza_base = 1.0


func _navegar(segundos: float) -> void:
	var t := 0.0
	while t < segundos:
		_viento_fijo()
		for b in _barcos:
			b.set("anclado", false)
		t += get_process_delta_time()
		await get_tree().process_frame


## Timón: la A mantenida. Se mide el rumbo antes y después, en grados.
func _medir_timon() -> void:
	await _navegar(RODAJE)
	var antes: Array[float] = []
	for b in _barcos:
		antes.append(b.global_rotation.y)
	_pulsar(KEY_A, true)
	await _navegar(MANTENER)
	_pulsar(KEY_A, false)

	var obedecen := 0
	print("── timón (tecla A mantenida %.1f s) ──" % MANTENER)
	for i in _barcos.size():
		var giro := rad_to_deg(wrapf(_barcos[i].global_rotation.y - antes[i], -PI, PI))
		var si := absf(giro) > GIRO_MINIMO
		if si:
			obedecen += 1
		print("  %-10s giró %+7.2f°   %s" % [_barcos[i].name, giro, "OBEDECE" if si else "quieto"])
	print("  → %d de %d barcos obedecen el timón (debe ser 1)\n" % [obedecen, _barcos.size()])


## Maniobra: la W alterna la vela delantera. Se mira el estado, no la señal, porque lo que se
## quiere saber es si el barco acabó con la vela cambiada.
func _medir_maniobra() -> void:
	var antes: Array[bool] = []
	for b in _barcos:
		antes.append(bool(b.get("vela_delantera")))
	await _tecla(KEY_W)
	await _navegar(0.5)

	var obedecen := 0
	print("── maniobra (tecla W: vela delantera) ──")
	for i in _barcos.size():
		var ahora := bool(_barcos[i].get("vela_delantera"))
		var si := ahora != antes[i]
		if si:
			obedecen += 1
		print("  %-10s vela %s → %s   %s" % [_barcos[i].name,
			"abierta" if antes[i] else "cerrada", "abierta" if ahora else "cerrada",
			"OBEDECE" if si else "quieto"])
	print("  → %d de %d barcos obedecen la maniobra (debe ser 1)\n" % [obedecen, _barcos.size()])


## Artillería: E apunta a estribor y R hace fuego. Se cuentan las balas que salen.
func _medir_artilleria() -> void:
	for b in _barcos:
		_disparos[b] = 0
	# Controles nuevos: B enciende el modo battle, la flecha derecha apunta a estribor y el
	# fuego es el clic izquierdo. E y R ya no son las teclas.
	await _tecla(KEY_B)
	await _tecla(KEY_RIGHT)
	await _clic_izquierdo()
	await _navegar(0.5)

	var obedecen := 0
	print("── artillería (B + flecha derecha + clic: fuego a estribor) ──")
	for b in _barcos:
		var n: int = _disparos[b]
		if n > 0:
			obedecen += 1
		print("  %-10s %d disparos   %s" % [b.name, n, "OBEDECE" if n > 0 else "quieto"])
	print("  → %d de %d barcos abren fuego (debe ser 1)\n" % [obedecen, _barcos.size()])


func _pulsar(k: int, pulsada: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = pulsada
	Input.parse_input_event(e)


func _tecla(k: int) -> void:
	for pulsada in [true, false]:
		_pulsar(k, pulsada)
		await get_tree().process_frame


## El fuego va por el botón principal del ratón desde que los controles pasaron al jugador.
func _clic_izquierdo() -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var s2 := InputEventMouseButton.new()
	s2.button_index = MOUSE_BUTTON_LEFT
	s2.pressed = false
	Input.parse_input_event(s2)
	for i in 4:
		await get_tree().process_frame
