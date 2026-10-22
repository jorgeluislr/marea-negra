class_name AgujaRosa
extends Control

## Una aguja de la rosa, dibujada apuntando ARRIBA (al norte) y girada por la rosa con
## `rotation_degrees`, que es el rumbo de carta: 0 al norte y en sentido horario, igual que el
## giro de un `Control` con la y de la pantalla hacia abajo.

enum Forma { RUMBO, VIENTO }

@export var forma := Forma.RUMBO
@export var color := EstiloHud.ROJO_CARTA


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	match forma:
		Forma.RUMBO:
			var punta := c + Vector2(0, -r * 0.72)
			var cola := c + Vector2(0, r * 0.3)
			var ancho := r * 0.09
			draw_colored_polygon(PackedVector2Array([punta, c + Vector2(ancho, 0), cola,
				c + Vector2(-ancho, 0)]), color)
			draw_circle(c, r * 0.06, EstiloHud.LATON)
		Forma.VIENTO:
			# En el aro, apuntando hacia dentro: el viento entra por ahí.
			var fuera := c + Vector2(0, -r * 1.0)
			var dentro := c + Vector2(0, -r * 0.8)
			draw_line(fuera, dentro, color, r * 0.05, true)
			draw_colored_polygon(PackedVector2Array([dentro + Vector2(0, r * 0.08),
				dentro + Vector2(-r * 0.07, -r * 0.02), dentro + Vector2(r * 0.07, -r * 0.02)]),
				color)
