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
#include "res://assets/shaders/agua_detalle.gdshaderinc"
#include "res://assets/shaders/agua_estela.gdshaderinc"

const int MUESTRAS = 64;
const float RANGO = 16.0;   // ±8 m: paso de 0,25 mm con los 16 bits

uniform vec2 puntos[MUESTRAS];
uniform int modo = 0;   // 0 = altura, 1 = arrastre en x, 2 = arrastre en z, 3 = normal.y
// 4 / 5 = pendiente total dibujada en x / z (ola con su LOD + relieve fino), 6 = varianza de
// pendiente que no cabe en el píxel, 7 = cuánto se aclara la cresta, 8 = espuma, 9 = espuma de la
// estela, 10 = altura de la estela. Las tres a `dist` metros de la cámara y con `huella`
// metros de píxel: es lo que decide qué se dibuja y qué pasa a la rugosidad.
uniform float dist = 0.0;
uniform float huella = 0.01;

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
	} else if (modo == 3) {
		v = oleaje_normal(p).y;
	} else {
		vec3 n = oleaje_normal_lod(p, dist);
		vec4 fino = agua_detalle(p, dist, huella);
		if (modo == 4) {
			v = -n.x / n.y + fino.x;
		} else if (modo == 5) {
			v = -n.z / n.y + fino.y;
		} else if (modo == 6) {
			v = fino.w;
		} else if (modo == 7) {
			v = agua_tono_cresta(oleaje_desplaz(p).y);
		} else if (modo == 8) {
			v = agua_espuma(p, dist);
		} else if (modo == 9) {
			v = agua_estela(p).z;
		} else {
			v = agua_estela(p).w;
		}
	}
	float x = clamp(v / RANGO + 0.5, 0.0, 1.0) * 255.0;
	float alto = floor(x);
	COLOR = vec4(alto / 255.0, x - alto, 0.0, 1.0);
}
