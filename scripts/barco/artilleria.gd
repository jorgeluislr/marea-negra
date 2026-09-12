class_name Artilleria
extends Resource

## Dónde va UNA pieza de artillería en un barco. Es dato, no comportamiento: quien actúa es
## `Canon`. Mismo reparto que `Carga` (el bulto) y `Aparejo` (la driza).
##
## Existe por lo mismo que `Carga`: el armamento no debe estar soldado dentro del `.glb` del
## casco. Así se cambia el número de piezas editando una lista —pasar de cuatro a seis es
## añadir dos entradas— sin tocar nada de la lógica de tiro.

## Posición respecto al barco, en metros. Es la del CENTRO de la caja del cañón, que es donde
## la biblioteca pone el origen de sus piezas: para que la cureña apoye en cubierta hay que
## sumarle media altura del cañón (0,3575 m). Ojo: 0,395 es la del modelo de la ALTA, que es un
## 4 libras; el del juego va reducido ×0,90476 a 3 libras, y esa reducción baja la media altura.
@export var posicion := Vector3.ZERO

## +1 tira a estribor (+X del barco), −1 a babor. Con la proa en −Z, estribor cae en +X.
@export var lado := 1.0

@export_file("*.glb", "*.tscn") var modelo := "res://assets/models/canon.glb"

@export var recarga := 5.0

## Nombre del nodo, para reconocerlo en el árbol y en los mensajes de las pruebas.
@export var nombre := ""


func instanciar() -> Canon:
	var c := Canon.new()
	c.modelo = modelo
	c.lado = lado
	c.recarga = recarga
	c.position = posicion
	c.name = nombre if nombre != "" else "Canon"
	return c
