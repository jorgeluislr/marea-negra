shader_type canvas_item;
render_mode unshaded;

// Saca por pantalla lo que dice el shader del oleaje, para poder compararlo con el espejo de
// GDScript. Es la única forma de leer una función de shader desde código: lo que el vertex
// shader hace con la malla del agua no se puede consultar.
//
// Un píxel por punto y UN valor por pasada, repartido entre el rojo y el verde para tener 16
// bits: con los 8 de un canal el paso sería de 6 cm y no se distinguiría un error de fórmula
// del redondeo. El azul y el alfa se dejan fijos —un alfa variable activaría la mezcla y lo
// que se leería ya no sería lo escrito.
//
// Va en 8 bits por canal y no en media precisión porque un `SubViewport` con `use_hdr_2d` no
// llega a pintarse (medido: devuelve basura), mientras que el de 8 bits no toca los colores
// (escrito 0,25 → leído 0,25098, que es exactamente su cuantización).
#include "res://assets/shaders/oleaje.gdshaderinc"

const int MUESTRAS = 64;
const float RANGO = 16.0;   // ±8 m: paso de 0,25 mm con los 16 bits

uniform vec2 puntos[MUESTRAS];
uniform int modo = 0;   // 0 = altura, 1 = arrastre en x, 2 = arrastre en z, 3 = normal.y

void fragment() {
	int i = int(floor(UV.x * float(MUESTRAS)));
	vec2 p = puntos[i];
	float v = 0.0;
	if (modo == 0) {
		v = oleaje_desplaz(p).y;
	} else if (modo == 1) {
		v = oleaje_desplaz(p).x;
	} else if (modo == 2) {
		v = oleaje_desplaz(p).z;
	} else {
		v = oleaje_normal(p).y;
	}
	float x = clamp(v / RANGO + 0.5, 0.0, 1.0) * 255.0;
	float alto = floor(x);
	COLOR = vec4(alto / 255.0, x - alto, 0.0, 1.0);
}
