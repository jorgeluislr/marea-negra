class_name Carta
extends Resource

## Lo que hace falta para dibujar la carta: el marco, el papel y la escala. DATOS; quien los usa
## es `CartaNautica`.
##
## La carta es una VENTANA que se arrastra con el ratón sobre un mundo que puede ser tan grande como
## haga falta (el Caribe entero, si llega). Por eso no hay una imagen que "sea" el mapa:
##
## - el **marco** es una imagen fija en pantalla, cortada en nueve partes por `rect_interior` (las
##   esquinas quedan enteras y los lados se repiten), así que vale para cualquier pantalla;
## - el **papel** es una baldosa que se repite anclada al MUNDO, de modo que se desliza con la carta;
## - las **costas** no están en ninguna imagen: son una malla 2D en metros de mundo (`costas`), que
##   `tools/hornear_islas.tscn` saca de los mismos contornos del `Archipielago` de los que sale el
##   relieve, y por eso caen siempre donde están las islas. La vista la escala; los límites de la
##   vista son los del archipiélago.
##
## Norte arriba: +X del mundo es la derecha de la carta y −Z es arriba.

## Imagen del marco. Solo se usa su borde: el interior no se dibuja.
@export var marco: Texture2D
## La línea interior del marco en la imagen, en píxeles. La MIDE `tools/medir_carta.tscn`.
@export var rect_interior := Rect2(105, 107, 727, 727)
## Baldosa de papel. Sin ella se pinta un pergamino liso.
@export var papel: Texture2D
## Toda la tierra de la carta, en metros de mundo: rellenos y líneas de costa con su color.
@export var costas: Mesh
## Rosa de los vientos, con transparencia. Va QUIETA en una esquina de la ventana, no anclada al
## mundo: es un adorno y una referencia del norte, no un sitio. Sale de la propia carta de Meshy
## (`tools/recortar_rosa.tscn`).
@export var rosa: Texture2D
## Alto de la rosa en fracción del alto de la ventana.
@export_range(0.05, 0.2) var rosa_alto := 0.16
## Cuántos metros de mundo cubre una baldosa de papel.
@export var papel_metros := 1500.0
## Escala al abrir y sus límites, en metros por píxel de pantalla.
@export var metros_por_pixel := 6.0
@export var metros_por_pixel_min := 0.75
@export var metros_por_pixel_max := 100.0
## Cuánto cambia la escala cada paso de rueda.
@export var paso_zoom := 1.25


## Márgenes del marco para un `NinePatchRect`: izquierda, arriba, derecha, abajo.
func margenes() -> Array[int]:
	var t := marco.get_size() if marco != null else rect_interior.end
	return [int(rect_interior.position.x), int(rect_interior.position.y),
		int(t.x - rect_interior.end.x), int(t.y - rect_interior.end.y)]
