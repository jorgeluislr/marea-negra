shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

// Agua del juego. La FORMA de la ola no está aquí: está en `oleaje.gdshaderinc`, que es la
// misma definición que responde el autoload `Oleaje` a quien pregunte desde GDScript. Aquí
// solo se deforma la malla con ella y se pinta.
//
// `world_vertex_coords` porque el oleaje se evalúa en coordenadas de MUNDO: la malla del agua
// persigue a la cámara, y si la ola dependiera de la posición local viajaría con ella — el mar
// se quedaría quieto respecto al barco por mucho que el barco navegue.
//
// El reflejo lo aporta el SSR del WorldEnvironment. La estela la dibuja `agua_estela.gdshaderinc`
// con el rastro que lleva `mar.gd` (ver `Estela`).
#include "res://assets/shaders/oleaje.gdshaderinc"
#include "res://assets/shaders/agua_detalle.gdshaderinc"
#include "res://assets/shaders/agua_estela.gdshaderinc"

uniform vec4 color_agua : source_color = vec4(0.04, 0.16, 0.24, 1.0);
uniform vec4 color_cresta : source_color = vec4(0.07, 0.30, 0.32, 1.0);
uniform float rugosidad : hint_range(0.0, 0.4) = 0.05;
uniform float especular : hint_range(0.0, 1.0) = 0.5;
uniform float metalico : hint_range(0.0, 1.0) = 0.0;

// Cuánto tapa la espuma de la estela el agua donde la hay. DÓNDE la hay lo decide
// `agua_estela()`.
uniform float espuma_intensidad : hint_range(0.0, 1.0) = 0.75;
// Cuánto tapa la espuma de las crestas el agua donde la hay. DÓNDE la hay lo decide
// `agua_espuma()`: cuando la ola se afila hasta romper, no cuando está alta.
uniform float espuma_cresta : hint_range(0.0, 1.0) = 0.9;
// A partir de dónde se apaga el relieve de la estela en la normal, en metros. Mismo motivo que
// `ola_alcance`: lejos, una ola corta dibujada solo en la normal no es relieve sino un encaje que
// hierve con la cámara.
uniform float alcance_fino = 150.0;
// Curvatura de la Tierra: el agua lejana se hunde `d²/2R`. Es lo que hace que el disco de agua
// no se acabe en un canto visible —a 20 km cae 31 m, que desde la altura de un palo es
// exactamente donde está el horizonte— y lo que obliga a que todo lo que flote lejos se hunda
// igual, o flotaría por encima de su propia agua. Lo pone `mar.gd` desde el autoload
// `Horizonte`, que es quien lleva el número.
uniform float radio_tierra = 6371000.0;

// ── Recorte del casco ────────────────────────────────────────────────────────
// Quita (discard) el agua que cae dentro de la BODEGA del barco, que es el único sitio por donde
// se ve —sus escotillas—. Es una caja, en ejes del barco, medida de la propia malla de la bodega
// y enviada por mar.gd; el barco la gira consigo, así que aquí no hay pose que reconstruir.
//
// Que la caja sea la bodega y no el contorno del casco no es un detalle: la bodega deja medio
// metro de holgura hasta el forro por cada banda, y como caja y casco están los dos en ejes del
// barco no pueden desplazarse el uno respecto al otro, se incline como se incline. Y su techo y
// su suelo hacen de límite vertical, en lugar de los cinco metros que había: al levantarse el
// casco sobre una ola el agua queda por debajo de la caja y deja de recortarse, que es justo
// cuando el hueco se vería desde fuera porque ya no hay casco delante.
uniform bool recorte_activo = false;
uniform mat4 barco_inv = mat4(1.0);         // mundo -> ejes del barco
uniform vec3 recorte_min = vec3(0.0);
uniform vec3 recorte_max = vec3(0.0);

varying vec3 world_pos;
// Dónde estaba este punto ANTES de que la ola lo arrastrase. Hace falta guardarlo porque en
// Gerstner el punto se corre también en horizontal: la normal y la espuma se evalúan en el
// punto de reposo, no donde acabó.
varying vec2 reposo;
// Distancia horizontal a la cámara: es lo que decide cuánta ola se puede dibujar aquí.
varying float lejania;
// Lo que la ola ha subido este punto: decide el tono de la cresta.
varying float alto_ola;


void vertex() {
	reposo = VERTEX.xz;
	lejania = distance(reposo, CAMERA_POSITION_WORLD.xz);
	vec3 d_ola = oleaje_desplaz_lod(reposo, lejania);
	alto_ola = d_ola.y;
	VERTEX += d_ola;
	VERTEX.y -= lejania * lejania / (2.0 * radio_tierra);
	world_pos = VERTEX;
}


void fragment() {
	// Recorte del casco: si este punto del agua cae dentro de la silueta del barco,
	// no se dibuja → se ve el interior real de la lancha, nunca el mar dentro.
	if (recorte_activo) {
		vec3 en_barco = (barco_inv * vec4(world_pos, 1.0)).xyz;
		if (all(greaterThan(en_barco, recorte_min)) && all(lessThan(en_barco, recorte_max))) {
			discard;
		}
	}

	// Normal de la ola: analítica, no por diferencias finitas. El punto se desplaza también en
	// horizontal, así que restar dos alturas medidas en x y en x+e no da la pendiente que se ve.
	vec3 n_ola = oleaje_normal_lod(reposo, lejania);
	vec2 pendiente = -n_ola.xz / n_ola.y;
	// El detalle por debajo de la ola, en el punto de REPOSO para que viaje con el agua. Lo que
	// mide un píxel sobre el agua decide qué se dibuja aquí y qué pasa a la rugosidad.
	float huella = max(length(dFdx(world_pos.xz)), length(dFdy(world_pos.xz)));
	vec4 detalle = agua_detalle(reposo, lejania, huella);
	pendiente += detalle.xy;
	// Encima, la estela del barco: en el punto donde ESTÁ el agua, porque el rastro está en el
	// mundo, no en el agua que la ola ha corrido.
	vec4 estela = agua_estela(world_pos.xz);
	float fino = 1.0 - smoothstep(alcance_fino * 0.5, alcance_fino, lejania);
	pendiente += estela.xy * fino;
	vec3 n_mundo = normalize(vec3(-pendiente.x, 1.0, -pendiente.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_mundo, 0.0)).xyz);

	// La cresta es agua fina y deja pasar la luz: se aclara hacia `color_cresta`.
	vec3 col = mix(color_agua.rgb, color_cresta.rgb, agua_tono_cresta(alto_ola));
	// Dos espumas: la de la cresta que rompe y la del rastro del barco.
	float espuma = agua_espuma(reposo, lejania) * espuma_cresta;
	espuma = max(espuma, estela.z * espuma_intensidad);
	col = mix(col, vec3(0.85, 0.92, 1.0), espuma);

	ALBEDO = col;
	// La pendiente que no se ha dibujado es rugosidad: en GGX α² hace de pendiente cuadrática
	// media, y Godot toma α = rugosidad².
	float alfa = sqrt(pow(rugosidad, 4.0) + detalle.w);
	// La espuma es aire y agua revueltos: mate, no refleja como la lámina.
	ROUGHNESS = mix(sqrt(alfa), 0.85, espuma);
	METALLIC = metalico;
	SPECULAR = especular;
}
