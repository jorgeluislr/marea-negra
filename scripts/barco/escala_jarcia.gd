class_name EscalaJarcia
extends Area3D

## Una escala de flechastes por la que se trepa: dónde está, hacia dónde sube y cuánto mide.
##
## Existe porque trepar NO es un problema de colisionadores, y eso está medido: un peldaño de
## 3,4 cm de grueso con 38 cm hasta el siguiente no sostiene a nadie. Posando al personaje encima
## de uno y soltándolo, la cápsula cae **43,9 m** —hasta el agua—, la caja 1,91 y el cilindro 1,77;
## y trepando desde cubierta a base de empujar y saltar, sube 1,54 / 1,13 / 0,43 m y se para.
## Cambiar su figura no lo arregla (`tools/subir_por_obenques.tscn` mide las tres).
##
## Así que la escala es un MODO, como en cualquier juego: el personaje se engancha y sube pegado
## al plano de la jarcia, con la física de la cápsula apagada mientras dura. Este nodo es lo que
## el personaje necesita saber para hacerlo, y nada más: no mueve a nadie.
##
## Se construye midiendo los propios flechastes del modelo (`Barco._montar_escalas()`), así que
## vale para cualquier casco que traiga su jarcia y no hay números escritos a mano.
##
## **Los ejes se guardan en LOCAL y se sirven en global**: el barco navega, escora y cabecea, y
## una escala con direcciones de mundo se despegaría de su propio palo en cuanto la ola levante
## la proa.

## De abajo arriba, en el espacio del barco.
var dir_subida := Vector3.UP
## A lo largo de los peldaños, en el espacio del barco.
var dir_lateral := Vector3.RIGHT
## Recorrido útil a lo largo de `dir_subida`, medido desde `global_position`.
var alto := 0.0
## Medio ancho: hasta dónde se puede correr uno de lado por los peldaños.
var ancho := 0.0
## Cuánto se separa el personaje del plano de la jarcia, hacia FUERA del barco. Se trepa desde la
## regala con el cuerpo al aire y la escala contra el pecho, que es como se sube en un barco.
var separacion := 0.45
## Hacia dónde es "fuera".
var dir_fuera := Vector3.RIGHT


func subida() -> Vector3:
	return (global_transform.basis * dir_subida).normalized()


func lateral() -> Vector3:
	return (global_transform.basis * dir_lateral).normalized()


func fuera() -> Vector3:
	return (global_transform.basis * dir_fuera).normalized()


## Dónde tiene que ponerse el personaje para estar agarrado a la escala en la altura `s` y el
## corrimiento lateral `l`, los dos ya limitados por quien llama.
func sitio(s: float, l: float) -> Vector3:
	return global_position + subida() * s + lateral() * l + fuera() * separacion


## En qué altura y corrimiento de ESTA escala cae un punto del mundo.
func donde(pos: Vector3) -> Vector2:
	var v := pos - global_position
	return Vector2(v.dot(subida()), v.dot(lateral()))


func _ready() -> void:
	# Solo mira al personaje (capa 4): nada más tiene que enterarse de que hay una escala.
	collision_layer = 0
	collision_mask = 8
	monitorable = false
	body_entered.connect(_entra)
	body_exited.connect(_sale)


## Duck-typing, como `on_interact`: la escala no sabe qué es un `Jugador`, solo avisa a lo que
## sepa escuchar. Así un futuro personaje de IA trepando no necesita tocar esto.
func _entra(cuerpo: Node) -> void:
	if cuerpo.has_method("escala_cerca"):
		cuerpo.escala_cerca(self)


func _sale(cuerpo: Node) -> void:
	if cuerpo.has_method("escala_lejos"):
		cuerpo.escala_lejos(self)
