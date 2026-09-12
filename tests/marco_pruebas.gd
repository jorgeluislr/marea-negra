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


func paquete(nombre: String) -> void:
	_paquete = nombre
	print("\n── %s ──" % nombre)


func comprobar(condicion: bool, que: String, detalle := "") -> bool:
	if condicion:
		ok += 1
		print("  OK    %s%s" % [que, "  (%s)" % detalle if detalle != "" else ""])
	else:
		fallos.append("%s / %s%s" % [_paquete, que, "  (%s)" % detalle if detalle != "" else ""])
		print("  FALLO %s%s" % [que, "  (%s)" % detalle if detalle != "" else ""])
	return condicion


## Para magnitudes medidas: se compara contra una tolerancia explícita, nunca por igualdad.
func casi(valor: float, esperado: float, tol: float, que: String) -> bool:
	return comprobar(absf(valor - esperado) <= tol, que,
		"%.3f vs %.3f ± %.3f" % [valor, esperado, tol])


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
	print("\n═══ %d pruebas OK, %d fallos ═══" % [ok, fallos.size()])
	for f in fallos:
		print("   FALLO: %s" % f)
	return 1 if not fallos.is_empty() else 0
