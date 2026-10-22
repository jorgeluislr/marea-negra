class_name ClimaTest
extends RefCounted

## Paquete `clima`: el calendario del juego y el viento del Caribe que sale de él.
##
## El viento de fondo sopla de donde sopla el alisio en las Islas Vírgenes según la fecha: del ENE
## y más del norte en invierno (los "Christmas winds"), del E-ESE en verano, más una variación por
## días que se SIEMBRA con la fecha. La fuerza no la toca (la decidió el usuario el 18-10-2026:
## solo la dirección, coherente con el mapa del Caribe).
##
## A `Calendario` y al `Clima` se les llama por nombre de nodo, y a `ClimaCaribe` cargando su
## script, para que sin ellos lo que salga en rojo sea la comprobación y no la batería entera
## caída por un error de parseo (ver `MarcoPruebas.menor_que`).

const CLIMA_CARIBE := "res://scripts/mundo/clima_caribe.gd"
const CLIMA_NODO := "res://scripts/mundo/clima.gd"
const RUTA_PRUEBA := "user://calendario_prueba.cfg"
## Lo más deprisa que puede rolar el viento de fondo, en grados por segundo REAL. El mar rola
## hacia `direccion_base` con un filtro de 90 s y, al girar, cada cresta a D metros del pivote se
## corre D·ω encima de su velocidad: a 0,05 °/s y 300 m son 0,26 m/s contra 6 m/s de la ola.
const ROLE_MAXIMO := 0.05


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("clima")
	var cal = arbol.root.get_node_or_null("Calendario")
	var cc = load(CLIMA_CARIBE) if ResourceLoader.exists(CLIMA_CARIBE) else null
	m.comprobar(cal != null, "existe el autoload Calendario")
	m.comprobar(cc != null, "existe ClimaCaribe")
	if m.escenario("bateria"):
		_bateria(m)
	if cal == null or cc == null:
		return
	if m.escenario("calendario"):
		_calendario(m, cal)
	if m.escenario("guardado"):
		_guardado(m, cal)
	if m.escenario("clima_medio"):
		_clima_medio(m, cal, cc)
	if m.escenario("variacion"):
		_variacion(m, cal, cc)
	if m.escenario("lento"):
		_lento(m, cal, cc)
	if m.escenario("viento"):
		await _viento(m, arbol, cal, cc)
	if m.escenario("activar"):
		await _activar(m, arbol, cal, cc)


## La batería corre el mundo dentro de `pruebas.tscn`: el clima NO se enciende ahí, porque las
## pruebas fijan el viento a mano y no deben tocar el calendario guardado del jugador.
static func _bateria(m: MarcoPruebas) -> void:
	m.comprobar(Viento.get("seguir_calendario") == false,
		"en la batería el viento no sigue al calendario", str(Viento.get("seguir_calendario")))
	var cal = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Calendario")
	m.comprobar(cal != null and cal.get("persistente") == false,
		"en la batería el calendario no se guarda")


static func _calendario(m: MarcoPruebas, cal) -> void:
	m.comprobar(cal.dia_juliano(2000, 1, 1) == 2451545, "el 1-1-2000 es el día juliano 2451545",
		str(cal.dia_juliano(2000, 1, 1)))
	var mal := ""
	var j0: int = cal.dia_juliano(1714, 1, 1)
	for k in 1500:
		var f: Vector3i = cal.fecha_de(j0 + k)
		if cal.dia_juliano(f.x, f.y, f.z) != j0 + k:
			mal = "%d → %s" % [j0 + k, f]
			break
	m.comprobar(mal == "", "fecha y día juliano van y vuelven durante cuatro años", mal)
	m.comprobar(cal.fecha_de(cal.dia_juliano(1716, 2, 29)) == Vector3i(1716, 2, 29),
		"1716 es bisiesto")
	m.comprobar(cal.dia_juliano(1700, 3, 1) - cal.dia_juliano(1700, 2, 28) == 1,
		"1700 no es bisiesto (gregoriano)")
	var antes: float = cal.instante
	cal.nueva_partida()
	m.comprobar(cal.fecha() == Vector3i(1715, 3, 1), "una partida nueva empieza el 1-3-1715",
		str(cal.fecha()))
	var i0: float = cal.instante
	cal.avanzar(1440.0)
	m.casi(cal.instante - i0, 1.0, 1e-9, "24 minutos reales son un día de juego")
	cal.poner(1715, 7, 15, 12.0)
	m.comprobar(cal.temporada_huracanes(), "el 15 de julio es temporada de huracanes")
	cal.poner(1715, 11, 30, 12.0)
	m.comprobar(cal.temporada_huracanes(), "el 30 de noviembre todavía lo es")
	cal.poner(1715, 12, 1, 12.0)
	m.comprobar(not cal.temporada_huracanes(), "el 1 de diciembre ya no")
	cal.poner(1716, 2, 15, 18.5)
	m.casi(cal.hora(), 18.5, 1e-6, "la hora se pone y se lee")
	cal.instante = antes


static func _guardado(m: MarcoPruebas, cal) -> void:
	var ruta_antes: String = cal.ruta
	var antes: float = cal.instante
	cal.ruta = RUTA_PRUEBA
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_PRUEBA))
	m.comprobar(not cal.cargar(), "sin archivo, cargar() dice que no había nada")
	cal.poner(1717, 9, 3, 6.25)
	var guardado: float = cal.instante
	m.comprobar(cal.guardar(), "guardar() escribe el archivo")
	cal.nueva_partida()
	m.comprobar(cal.cargar(), "cargar() lo lee")
	m.casi(cal.instante, guardado, 1e-6, "y vuelve a la fecha guardada, hora incluida")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_PRUEBA))
	cal.ruta = ruta_antes
	cal.instante = antes


## Media circular de los rumbos (de dónde sopla, grados) muestreados cada hora en [a, b).
static func _rumbo_medio(cc, a: float, b: float) -> float:
	var s := Vector2.ZERO
	var t := a
	while t < b:
		var r := deg_to_rad(float(cc.rumbo(t)))
		s += Vector2(sin(r), cos(r))
		t += 1.0 / 24.0
	return fposmod(rad_to_deg(atan2(s.x, s.y)), 360.0)


static func _clima_medio(m: MarcoPruebas, cal, cc) -> void:
	var ene := _rumbo_medio(cc, cal.dia_juliano(1716, 1, 1), cal.dia_juliano(1716, 2, 1))
	m.comprobar(ene > 45.0 and ene < 90.0, "en enero el viento medio viene del cuadrante NE",
		"%.1f°" % ene)
	var jul := _rumbo_medio(cc, cal.dia_juliano(1716, 7, 1), cal.dia_juliano(1716, 8, 1))
	m.comprobar(jul >= 90.0 and jul < 120.0, "en julio viene del E-ESE", "%.1f°" % jul)
	var inv := _rumbo_medio(cc, cal.dia_juliano(1715, 12, 1), cal.dia_juliano(1716, 3, 1))
	var ver := _rumbo_medio(cc, cal.dia_juliano(1716, 6, 1), cal.dia_juliano(1716, 9, 1))
	m.mayor_que(ver - inv, 15.0, "el invierno sopla más del norte que el verano",
		"invierno %.1f°, verano %.1f°" % [inv, ver])
	var fuera := ""
	for mes in range(1, 13):
		var a: int = cal.dia_juliano(1716, mes, 1)
		var b: int = cal.dia_juliano(1716 + (1 if mes == 12 else 0), mes % 12 + 1, 1)
		var r := _rumbo_medio(cc, a, b)
		if r < 50.0 or r > 115.0:
			fuera += " mes %d: %.1f°" % [mes, r]
	m.comprobar(fuera == "", "todos los meses el alisio viene entre el NE y el ESE", fuera)
	# Muestreo horario de un año entero: el poniente es rarísimo en el alisio.
	var oeste := 0
	var n := 0
	var t: float = cal.dia_juliano(1716, 1, 1)
	while t < cal.dia_juliano(1717, 1, 1):
		var r := fposmod(float(cc.rumbo(t)), 360.0)
		if r > 180.0:
			oeste += 1
		n += 1
		t += 1.0 / 24.0
	m.menor_que(float(oeste) / n, 0.01, "menos del 1 % de las horas sopla del oeste",
		"%d de %d" % [oeste, n])


static func _variacion(m: MarcoPruebas, cal, cc) -> void:
	var t: float = cal.dia_juliano(1716, 1, 10) + 0.37
	m.comprobar(cc.rumbo(t) == cc.rumbo(t), "la misma fecha da el mismo viento")
	# Y no depende de lo que se haya preguntado antes ni en qué orden.
	var muestras := []
	for k in 50:
		muestras.append(cal.dia_juliano(1715, 3, 1) + k * 13.7)
	var primero := []
	for x in muestras:
		primero.append(cc.rumbo(x))
	cc.rumbo(cal.dia_juliano(1790, 5, 5))
	muestras.reverse()
	primero.reverse()
	var distinto := 0
	for i in muestras.size():
		if cc.rumbo(muestras[i]) != primero[i]:
			distinto += 1
	m.comprobar(distinto == 0, "ni del orden en que se pregunta", "%d distintos" % distinto)
	m.comprobar(cc.rumbo(t) != cc.rumbo(t + 365.0),
		"el mismo día de otro año sopla distinto (la semilla es la fecha entera)")
	# Hay días de un viento y días de otro: la desviación del rumbo de mediodía dentro de un mes.
	var vals := []
	var a: int = cal.dia_juliano(1716, 1, 1)
	for d in 31:
		vals.append(float(cc.rumbo(a + d + 0.5)) - float(cc.rumbo_medio(cc.fraccion_del_anio(a + d + 0.5))))
	var med := 0.0
	for v in vals:
		med += v
	med /= vals.size()
	var var_ := 0.0
	for v in vals:
		var_ += (v - med) * (v - med)
	var desv := sqrt(var_ / vals.size())
	m.comprobar(desv > 5.0 and desv < 25.0, "de un día a otro el rumbo varía entre 5 y 25° (desviación)",
		"%.1f°" % desv)


static func _lento(m: MarcoPruebas, cal, cc) -> void:
	# Cada 5 minutos de juego —5 segundos reales— durante un año entero.
	var paso := 5.0 / 1440.0
	var seg_reales: float = paso * cal.SEGUNDOS_POR_DIA
	var t: float = cal.dia_juliano(1716, 1, 1)
	var fin: float = cal.dia_juliano(1717, 1, 1)
	var prev := float(cc.rumbo(t))
	var peor := 0.0
	var donde := t
	while t < fin:
		t += paso
		var r := float(cc.rumbo(t))
		var w := absf(wrapf(r - prev, -180.0, 180.0)) / seg_reales
		if w > peor:
			peor = w
			donde = t
		prev = r
	m.menor_que(peor, ROLE_MAXIMO, "el viento de fondo rola despacio (°/s reales)",
		"%.4f °/s el %s" % [peor, cal.fecha_de(int(donde))])


## Con el viento siguiendo al calendario, `direccion_base` es la del clima de esa fecha, en ejes
## del mundo: el norte es −Z y el este +X (ver `Archipielago.de_lat_lon`).
static func _viento(m: MarcoPruebas, arbol: SceneTree, cal, cc) -> void:
	var antes_base: Vector3 = Viento.direccion_base
	var antes_inst: float = cal.instante
	cal.poner(1716, 1, 15, 12.0)
	Viento.set("seguir_calendario", true)
	await arbol.process_frame
	await arbol.process_frame
	var esperado: Vector3 = cc.direccion(cal.instante)
	var ang := rad_to_deg(Viento.direccion_base.normalized().angle_to(esperado))
	m.menor_que(ang, 0.5, "el viento de fondo es el del clima de la fecha", "%.2f°" % ang)
	var d := Viento.direccion_base.normalized()
	m.comprobar(d.x < 0.0 and d.z > 0.0, "en enero sopla HACIA el OSO (viene del ENE)", str(d))
	var r := deg_to_rad(float(cc.rumbo(cal.instante)))
	var hacia := Vector3(-sin(r), 0.0, cos(r))
	m.menor_que(rad_to_deg(esperado.angle_to(hacia)), 0.01,
		"direccion() apunta adonde sopla el rumbo que da rumbo()")
	Viento.set("seguir_calendario", false)
	Viento.direccion_base = antes_base
	cal.instante = antes_inst
	await arbol.process_frame


## Lo que hace el nodo `Clima` al arrancar el juego: continuar la fecha guardada, poner el viento
## a seguirla y dejar el mar YA orientado (si rolase desde el rumbo de fábrica, el primer minuto
## se vería todo el mar barriendo de lado).
static func _activar(m: MarcoPruebas, arbol: SceneTree, cal, cc) -> void:
	if not m.comprobar(ResourceLoader.exists(CLIMA_NODO), "existe el nodo Clima"):
		return
	var antes_base: Vector3 = Viento.direccion_base
	var antes_inst: float = cal.instante
	var ruta_antes: String = cal.ruta
	cal.ruta = RUTA_PRUEBA
	cal.poner(1716, 1, 20, 9.0)
	cal.guardar()
	var guardado: float = cal.instante
	cal.nueva_partida()
	var clima := (load(CLIMA_NODO) as Script).new() as Node
	arbol.root.add_child(clima)
	m.comprobar(Viento.get("seguir_calendario") == false,
		"fuera de la escena principal el Clima no se enciende solo")
	clima.call("activar")
	m.casi(cal.instante, guardado, 1e-6, "al activarse continúa la fecha guardada")
	m.comprobar(Viento.get("seguir_calendario") == true, "y pone el viento a seguir al calendario")
	m.comprobar(cal.get("persistente") == true, "y el calendario a guardarse")
	var esperado: Vector3 = cc.direccion(cal.instante)
	m.menor_que(rad_to_deg(Viento.direccion_base.angle_to(esperado)), 0.5,
		"el viento ya es el de la fecha")
	var eje: Vector2 = Oleaje.get("_eje")
	var e2 := Vector2(esperado.x, esperado.z).normalized()
	m.menor_que(rad_to_deg(absf(eje.angle_to(e2))), 0.5, "y el mar ya rueda con él, sin rolar",
		"%.2f°" % rad_to_deg(absf(eje.angle_to(e2))))
	# Deja todo como estaba para lo que corre detrás.
	clima.queue_free()
	cal.set("persistente", false)
	Viento.set("seguir_calendario", false)
	Viento.direccion_base = antes_base
	Oleaje.call("rolar_de_golpe")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_PRUEBA))
	cal.ruta = ruta_antes
	cal.instante = antes_inst
	await arbol.process_frame
