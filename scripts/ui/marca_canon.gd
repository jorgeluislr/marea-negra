class_name MarcaCanon
extends Control

## Un cañón en la silueta de la batería: la pieza en hierro y un anillo que se llena mientras
## recarga. Lleno y en verde, lista para tirar.
##
## `carga` y `lista` se leen de la pieza cada frame (`Canon.carga()`, `Canon.listo()`); se
## exponen para que la prueba lea lo mismo que se pinta.

var canon: Node
## El cañón visto desde arriba, con la boca hacia arriba en la imagen; se gira hacia su banda.
var icono: Texture2D
var carga := 1.0
var lista := true


func _process(_delta: float) -> void:
	if canon == null or not is_instance_valid(canon):
		return
	var c := float(canon.call("carga"))
	var l := bool(canon.call("listo"))
	if c != carga or l != lista:
		carga = c
		lista = l
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var grueso := r * 0.22
	draw_arc(c, r - grueso * 0.5, 0.0, TAU, 32, EstiloHud.PERGAMINO_OSCURO, grueso, true)
	if lista:
		draw_arc(c, r - grueso * 0.5, 0.0, TAU, 32, EstiloHud.VERDE, grueso, true)
	elif carga > 0.0:
		draw_arc(c, r - grueso * 0.5, -PI * 0.5, -PI * 0.5 + TAU * carga, 32, EstiloHud.LATON,
			grueso, true)
	var hierro := EstiloHud.HIERRO
	if not lista:
		hierro.a = 0.45
	if icono == null:
		draw_circle(c, r * 0.58, hierro)
		return
	# La boca hacia fuera de su costado: estribor a la derecha de la silueta (proa arriba).
	var giro := PI * 0.5 if canon != null and canon.call("banda") == "estribor" else -PI * 0.5
	draw_set_transform(c, giro)
	var m := r * 0.72
	draw_texture_rect(icono, Rect2(-Vector2(m, m), Vector2(m, m) * 2.0), false,
		Color(1, 1, 1, 1.0 if lista else 0.5))
	draw_set_transform(Vector2.ZERO)
