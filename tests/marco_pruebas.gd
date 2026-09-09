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


func menor_que(valor: float, tope: float, que: String) -> bool:
	return comprobar(valor < tope, que, "%.3f < %.3f" % [valor, tope])


func mayor_que(valor: float, minimo: float, que: String) -> bool:
	return comprobar(valor > minimo, que, "%.3f > %.3f" % [valor, minimo])


func resumen() -> int:
	print("\n═══ %d pruebas OK, %d fallos ═══" % [ok, fallos.size()])
	for f in fallos:
		print("   FALLO: %s" % f)
	return 1 if not fallos.is_empty() else 0
