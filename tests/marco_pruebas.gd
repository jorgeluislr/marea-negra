class_name MarcoPruebas
extends RefCounted

## Mini-marco de pruebas del juego. No hay framework: son cuatro funciones y un contador.
##
## Las pruebas de este proyecto **no pueden correr con `-s`** (con `-s` los autoloads no se
## instancian y `Viento` no existe) ni con `--headless` (headless NO simula `SoftBody3D`: los
## puntos se quedan congelados y toda la tela mide "perfecta"). Por eso son una ESCENA que se
## lanza con ventana:
##
##     godot --path . tests/pruebas.tscn
##
## Devuelve 1 si algo falla, así que sirve tal cual en un script o en CI con pantalla virtual.

var ok := 0
var fallos: Array[String] = []
var _paquete := ""

## Lo que se pidió por la línea de órdenes: `paquete` corre el paquete entero y
## `paquete/escenario` solo ese escenario. Vacío es la batería completa.
var _pide := PackedStringArray()
## Cada filtro que llegó a correr algo. Un filtro que no corre nada es una errata, y una errata
## que no dice nada sale en verde: es la misma trampa que el paquete que no compila.
var _servidos := {}
## Los escenarios que cada paquete ofrece, para decir cuáles hay cuando se pide uno que no.
var _ofrecidos := {}


func pedir(args: PackedStringArray) -> void:
	_pide.clear()
	for a in args:
		_pide.append(String(a).to_lower())


func pedido() -> PackedStringArray:
	return _pide


## Si hay que entrar en el paquete: se pidió entero o alguno de sus escenarios. Con
## `partido = false` —los paquetes que no tienen escenarios— solo cuenta pedirlo entero: entrar
## por `ia/algo` correría el paquete completo y daría por servido lo que no existe.
func quiere_paquete(nombre: String, partido := true) -> bool:
	if _pide.is_empty() or _pide.has(nombre):
		return true
	if partido:
		for p in _pide:
			if p.begins_with(nombre + "/"):
				return true
	return false


func paquete(nombre: String) -> void:
	_paquete = nombre
	_ofrecidos[nombre] = []
	if _pide.has(nombre):
		_servidos[nombre] = true
	print("\n── %s ──" % nombre)


## Si hay que correr este escenario del paquete en curso. Cada escenario se prepara SOLO —rumbo,
## viento, ancla, modo— y deja el barco como lo encontró, así que se puede pedir suelto:
##
##     godot --path . tests/pruebas.tscn -- tela/costura
func escenario(nombre: String) -> bool:
	# Array y no PackedStringArray: este es de VALOR, y el append caía en una copia.
	(_ofrecidos[_paquete] as Array).append(nombre)
	var completo := "%s/%s" % [_paquete, nombre]
	var corre := _pide.is_empty() or _pide.has(_paquete) or _pide.has(completo)
	if corre:
		if _pide.has(completo):
			_servidos[completo] = true
		print("  · %s" % nombre)
	return corre


func comprobar(condicion: bool, que: String, detalle := "") -> bool:
	if condicion:
		ok += 1
		print("  OK    %s%s" % [que, "  (%s)" % detalle if detalle != "" else ""])
	else:
		fallos.append("%s / %s%s" % [_paquete, que, "  (%s)" % detalle if detalle != "" else ""])
		print("  FALLO %s%s" % [que, "  (%s)" % detalle if detalle != "" else ""])
	return condicion


## Para magnitudes medidas: se compara contra una tolerancia explícita, nunca por igualdad.
##
## Acepta `detalle` igual que las demás. No lo aceptaba, aunque el comentario de abajo decía que
## sí: el 17 de octubre de 2026 una prueba nueva lo pasó por costumbre, como estaba escrito.
func casi(valor: float, esperado: float, tol: float, que: String, detalle := "") -> bool:
	var txt := "%.3f vs %.3f ± %.3f" % [valor, esperado, tol]
	if detalle != "":
		txt += "  " + detalle
	return comprobar(absf(valor - esperado) <= tol, que, txt)


## El `detalle` es opcional y se AÑADE a la comparación, no la sustituye: sigue viéndose el
## número que falló y además lo que quieras contar de él.
##
## Lleva detalle porque no llevarlo era una trampa: `comprobar` y `casi` lo aceptan y estas dos
## no, así que quien conoce el marco lo escribe por costumbre y se lleva un error de parseo
## —"Too many arguments"— que en GDScript no es un fallo de prueba sino un fallo de COMPILACIÓN.
## Y al no compilar un paquete, cae `pruebas.gd` entero: la batería se corta a media tirada y
## sale con código 0, o sea en verde. Pasó dos veces el 11 de septiembre de 2026, en dos
## sesiones distintas y sin conocerse. Cuando dos personas tropiezan igual, la firma es el
## problema.
func menor_que(valor: float, tope: float, que: String, detalle := "") -> bool:
	var txt := "%.3f < %.3f" % [valor, tope]
	if detalle != "":
		txt += "  " + detalle
	return comprobar(valor < tope, que, txt)


func mayor_que(valor: float, minimo: float, que: String, detalle := "") -> bool:
	var txt := "%.3f > %.3f" % [valor, minimo]
	if detalle != "":
		txt += "  " + detalle
	return comprobar(valor > minimo, que, txt)


func resumen() -> int:
	for p in _pide:
		if not _servidos.has(p):
			var paq := p.get_slice("/", 0)
			var nombres := PackedStringArray(_ofrecidos.get(paq, []))
			var hay := "escenarios de '%s': %s" % [paq, ", ".join(nombres)] if not nombres.is_empty() \
				else "'%s' no existe o no está partido en escenarios: pídelo entero" % paq
			fallos.append("se pidió '%s' y no corrió nada  (%s)" % [p, hay])
	print("\n═══ %d pruebas OK, %d fallos ═══" % [ok, fallos.size()])
	for f in fallos:
		print("   FALLO: %s" % f)
	return 1 if not fallos.is_empty() else 0
