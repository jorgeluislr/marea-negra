class_name TemaMenu
extends RefCounted

## Tema de los menús (principal y de pausa): tinta sobre pergamino con marco de latón, los colores
## y la letra de `EstiloHud`. Los botones no llevan caja hasta que el ratón o el foco pasan por
## encima; el pulsado (la dificultad elegida) va en tinta con letra de pergamino.
##
## Los paneles llevan el marco de Meshy (`MARCO`, de `tools/procesar_menu.gd`) como nueve-parches:
## las esquinas —latón, anclas y volutas— se quedan a su tamaño y los bordes se estiran con el
## panel. Si falta la imagen, una caja lisa de pergamino con borde de latón.

const MARCO := "res://assets/textures/ui/marco_menu.png"
## Izquierda, arriba, derecha y abajo del recuadro liso del marco, en píxeles de `MARCO`: lo que
## imprime `tools/procesar_menu.gd`. Los botones van dentro, con `HOLGURA` más.
const MARGENES_MARCO := [98, 118, 99, 111]
const HOLGURA := 8


static func crear() -> Theme:
	var t := Theme.new()
	t.default_font = EstiloHud.letra()
	t.default_font_size = 22
	t.set_color("font_color", "Label", EstiloHud.TINTA)
	for estado in ["font_color", "font_focus_color", "font_hover_color"]:
		t.set_color(estado, "Button", EstiloHud.TINTA)
	for estado in ["font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(estado, "Button", EstiloHud.PERGAMINO)
	t.set_stylebox("normal", "Button", caja(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	t.set_stylebox("hover", "Button", caja(EstiloHud.PERGAMINO_OSCURO, EstiloHud.LATON))
	t.set_stylebox("focus", "Button", caja(Color(0, 0, 0, 0), EstiloHud.LATON))
	t.set_stylebox("pressed", "Button", caja(EstiloHud.TINTA_SUAVE, EstiloHud.LATON))
	t.set_stylebox("hover_pressed", "Button", caja(EstiloHud.TINTA, EstiloHud.LATON))
	t.set_stylebox("panel", "PanelContainer", marco())
	return t


static func marco() -> StyleBox:
	if not ResourceLoader.exists(MARCO):
		return caja(Color(EstiloHud.PERGAMINO, 0.94), EstiloHud.LATON, 3, 24)
	var c := StyleBoxTexture.new()
	c.texture = load(MARCO)
	for i in 4:
		c.set_texture_margin(i as Side, MARGENES_MARCO[i])
		c.set_content_margin(i as Side, MARGENES_MARCO[i] + HOLGURA)
	return c


static func caja(fondo: Color, borde: Color, ancho := 2, margen := 8) -> StyleBoxFlat:
	var c := StyleBoxFlat.new()
	c.bg_color = fondo
	c.border_color = borde
	c.set_border_width_all(ancho)
	c.set_corner_radius_all(3)
	c.set_content_margin_all(margen)
	return c

