class_name IconoEstado
extends Control

## Un icono de estado: el marco de latón con su disco de pergamino, la tinta del icono encima y un
## aro de color por fuera que dice el estado (verde puesto, apagado quitado…). Debajo, la tecla.
##
## `icono` es la tinta de Meshy, ya en transparente (`tools/procesar_iconos_hud.gd`);
## `icono_inactivo`, si lo hay, sustituye al apagado (el timón pasa a tricornio en cubierta). Sin
## imágenes se dibuja el marcador provisional con `texto`.

@export var icono: Texture2D
@export var icono_inactivo: Texture2D
@export var marco: Texture2D
@export var texto := ""
@export var tecla := ""
@export var color_activo := EstiloHud.VERDE
@export var color_inactivo := EstiloHud.APAGADO

## Si es mayor que cero, en vez de imagen se pintan tantos triángulos de «play» en tinta: el
## icono de travesía, con uno a tiempo normal y dos o cuatro al acelerar. Se dibujan y no se
## generan porque son geometría pura y así cualquier multiplicador nuevo sale solo.
var triangulos := 0:
	set(v):
		if v != triangulos:
			triangulos = v
			queue_redraw()

## Los iconos que solo adornan (daños, munición) se dejan encendidos desde la escena.
@export var activo := false:
	set(v):
		if v != activo:
			activo = v
			queue_redraw()


func poner(nuevo_texto: String, nueva_tecla: String) -> void:
	if nuevo_texto != texto or nueva_tecla != tecla:
		texto = nuevo_texto
		tecla = nueva_tecla
		queue_redraw()


func _draw() -> void:
	var lado := minf(size.x, size.y - 16.0)
	var c := Vector2(size.x * 0.5, lado * 0.5)
	var r := lado * 0.5
	draw_circle(c, r, color_activo if activo else color_inactivo)
	var f := EstiloHud.letra()
	if marco != null:
		var m := r * 0.88
		draw_texture_rect(marco, Rect2(c - Vector2(m, m), Vector2(m, m) * 2.0), false,
			Color(1, 1, 1) if activo else Color(0.78, 0.74, 0.68))
	else:
		draw_circle(c, r * 0.8, EstiloHud.PERGAMINO if activo else EstiloHud.PERGAMINO_OSCURO)
	var tinta := icono_inactivo if (not activo and icono_inactivo != null) else icono
	if triangulos > 0:
		_dibujar_triangulos(c, r)
	elif tinta != null:
		var m := r * 0.58
		draw_texture_rect(tinta, Rect2(c - Vector2(m, m), Vector2(m, m) * 2.0), false,
			Color(1, 1, 1, 1.0 if activo or icono_inactivo != null else 0.5))
	else:
		var tam := int(r * 0.42)
		draw_string(f, Vector2(0, c.y + tam * 0.35), texto, HORIZONTAL_ALIGNMENT_CENTER, size.x,
			tam, EstiloHud.TINTA)
	if tecla != "":
		draw_string_outline(f, Vector2(0, size.y - 2), tecla, HORIZONTAL_ALIGNMENT_CENTER, size.x,
			13, 4, Color(0, 0, 0, 0.7))
		draw_string(f, Vector2(0, size.y - 2), tecla, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13,
			EstiloHud.PERGAMINO)


## Centro del disco, en coordenadas del icono: donde van el marco y lo que se pinta dentro.
func centro_disco() -> Vector2:
	var lado := minf(size.x, size.y - 16.0)
	return Vector2(size.x * 0.5, lado * 0.5)


## Los triángulos en fila y pegados, como el avance rápido de un reproductor: el ancho de la fila
## cabe en el disco y cada uno es algo más alto que ancho.
##
## Se centran por su CENTRO DE MASAS y no por su caja: la tinta de un triángulo se carga hacia la
## base (su centro está a un tercio del ancho), y centrado por la caja se ve corrido a la
## izquierda. La fila entera tiene el centro en `x0 + ancho·(n−1)/2 + ancho/3`.
func triangulos_dibujados() -> Array[PackedVector2Array]:
	var c := centro_disco()
	var r := c.y
	var sale: Array[PackedVector2Array] = []
	if triangulos <= 0:
		return sale
	var ancho := minf(r * 0.62, r * 1.1 / float(triangulos))
	var alto := minf(ancho * 1.15, r * 0.75)
	var x0 := c.x - ancho * float(triangulos - 1) * 0.5 - ancho / 3.0
	for i in triangulos:
		var x := x0 + ancho * float(i)
		sale.append(PackedVector2Array([Vector2(x, c.y - alto * 0.5), Vector2(x + ancho, c.y),
			Vector2(x, c.y + alto * 0.5)]))
	return sale


func _dibujar_triangulos(_c: Vector2, _r: float) -> void:
	for tri in triangulos_dibujados():
		draw_colored_polygon(tri, EstiloHud.TINTA)
