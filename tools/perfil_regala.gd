extends Node

## A qué altura pasa la regala a lo largo de la eslora, y cuánto margen deja sobre ella el
## ánima de un cañón puesto ahí. Es lo que decide dónde puede ir una pieza a barbeta: si el
## ánima no supera la borda, el tiro sale contra su propia madera.
##
## Usa `Barco.altura_regala_en`, la MISMA función que consulta la prueba, para que lo que se
## mide aquí y lo que se comprueba allí no puedan discrepar.

## Altura del eje del ánima sobre la cubierta, para el cañón que toque.
@export var eje_anima := 0.513
@export var cubierta := 1.640

var _barco: Node3D


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_barco = esc.instantiate() as Node3D
	add_child(_barco)
	_barco.set("anclado", true)
	await get_tree().create_timer(4.0).timeout
	var y_anima := cubierta + eje_anima
	print("ánima a %.3f (local)  |  z = eslora, proa en −Z" % y_anima)
	print(" %6s %8s %8s   %s" % ["z", "regala", "margen", ""])
	var z := -4.0
	while z <= 4.01:
		var g: Vector3 = _barco.to_global(Vector3(1.2, cubierta, z))
		var reg_g: float = float(_barco.call("altura_regala_en", g))
		var reg: float = _barco.to_local(Vector3(0, reg_g, 0)).y
		var margen := y_anima - reg
		print(" %+6.2f %8.3f %+8.3f   %s" % [z, reg, margen, "OK" if margen > 0.05 else "justo"])
		z += 0.5
	get_tree().quit(0)
