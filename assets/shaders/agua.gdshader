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
// El reflejo lo aporta el SSR del WorldEnvironment. La estela (rastro de anillos) la rellena
// `mar.gd` con la posición del barco.
#include "res://assets/shaders/oleaje.gdshaderinc"

uniform vec4 color_agua : source_color = vec4(0.04, 0.16, 0.24, 1.0);
uniform float rugosidad : hint_range(0.0, 0.4) = 0.05;
uniform float especular : hint_range(0.0, 1.0) = 0.5;
uniform float metalico : hint_range(0.0, 1.0) = 0.0;

const int MAX_ESTELA = 16;
uniform vec4 estela[MAX_ESTELA];        // xy = mundo (x,z), z = edad(seg), w = activo
uniform float vida_estela = 3.0;
uniform float vel_expansion = 1.6;
uniform float amplitud_estela = 0.08;
uniform float espuma_intensidad : hint_range(0.0, 1.0) = 0.15;
// Espuma de las crestas: aparece cuando la ola se afila hasta romper, no cuando está alta.
uniform float espuma_cresta : hint_range(0.0, 1.0) = 0.5;
uniform float rizado = 0.005;           // detalle fino, solo para la normal
// A partir de dónde se apaga el relieve fino, en metros. Mismo motivo que `ola_alcance`: el
// rizado tiene 2,5 m de período y la estela 90 cm, así que a media distancia ya no son un
// relieve sino un encaje regular que hierve con la cámara.
uniform float alcance_fino = 90.0;
// Curvatura de la Tierra: el agua lejana se hunde `d²/2R`. Es lo que hace que el disco de agua
// no se acabe en un canto visible —a 20 km cae 31 m, que desde la altura de un palo es
// exactamente donde está el horizonte— y lo que obliga a que todo lo que flote lejos se hunda
// igual, o flotaría por encima de su propia agua. Lo pone `mar.gd` desde el autoload
// `Horizonte`, que es quien lleva el número.
uniform float radio_tierra = 6371000.0;

// ── Recorte del casco ────────────────────────────────────────────────────────
// Quita (discard) el agua dentro de la silueta del barco, en SU espacio local
// (elipse: semieje x = manga, semieje z = eslora), para que el mar no se vea
// dentro del casco. Lo alimenta mar.gd cada frame con la pose del barco.
uniform bool recorte_activo = false;
uniform vec2 barco_pos = vec2(0.0);         // (x,z) del barco en el mundo
uniform vec2 barco_dir = vec2(0.0, 1.0);    // proa (x,z) normalizada
uniform vec2 barco_radio = vec2(1.1, 2.2);  // semiejes (manga, eslora)
// Forma del casco (vista superior): la proa se afila y la popa se redondea.
// Exponente menor = extremo más lleno/ancho ; mayor = más afilado/puntiagudo.
uniform float recorte_proa_exp = 0.8;   // proa (extremo +eslora): puntiaguda
uniform float recorte_popa_exp = 0.4;   // popa (extremo -eslora): redondeada

varying vec3 world_pos;
// Dónde estaba este punto ANTES de que la ola lo arrastrase. Hace falta guardarlo porque en
// Gerstner el punto se corre también en horizontal: la normal y la espuma se evalúan en el
// punto de reposo, no donde acabó.
varying vec2 reposo;
// Distancia horizontal a la cámara: es lo que decide cuánta ola se puede dibujar aquí.
varying float lejania;


// Relieve de la estela y rizado fino. Van aparte del oleaje porque no deforman la malla, solo
// la normal: el anillo de estela tiene 8 cm de amplitud y un período de 90 cm, y la celda de
// la malla junto al barco mide 75 — no hay con qué dibujarlo, pero en la normal sí se ve.
float relieve_fino(vec2 p, float atenua) {
	if (atenua <= 0.001) {
		return 0.0;
	}
	// Tres rizos en diagonal, con longitudes que no guardan relación (2,7 / 1,7 / 1,2 m).
	// Eran dos, uno en x y otro en z: dos senos perpendiculares son una REJILLA, y de cerca se
	// veía como tal —cuadrícula regular sobre el agua—, que es lo más reconocible que tenía el
	// mar. Ni perpendiculares ni conmensurables, y deja de leerse como patrón.
	float h = sin(dot(p, vec2(0.87, 0.49)) * 2.3 + ola_t * 1.1) * rizado;
	h += sin(dot(p, vec2(-0.36, 0.93)) * 3.7 - ola_t * 0.9) * rizado * 0.8;
	h += sin(dot(p, vec2(0.62, -0.78)) * 5.1 + ola_t * 1.6) * rizado * 0.6;
	for (int i = 0; i < MAX_ESTELA; i++) {
		if (estela[i].w < 0.01) {
			continue;
		}
		float edad = estela[i].z;
		float radio = edad * vel_expansion;
		float d = distance(p, estela[i].xy);
		float anillo = smoothstep(0.8, 0.0, abs(d - radio));
		float fade = clamp(1.0 - edad / vida_estela, 0.0, 1.0);
		h += sin((d - edad * 5.0) * 7.0) * amplitud_estela * anillo * fade * estela[i].w;
	}
	return h * atenua;
}


void vertex() {
	reposo = VERTEX.xz;
	lejania = distance(reposo, CAMERA_POSITION_WORLD.xz);
	VERTEX += oleaje_desplaz_lod(reposo, lejania);
	VERTEX.y -= lejania * lejania / (2.0 * radio_tierra);
	world_pos = VERTEX;
}


void fragment() {
	// Recorte del casco: si este punto del agua cae dentro de la silueta del barco,
	// no se dibuja → se ve el interior real de la lancha, nunca el mar dentro.
	if (recorte_activo) {
		vec2 rel = world_pos.xz - barco_pos;
		vec2 fwd = barco_dir;
		vec2 rgt = vec2(fwd.y, -fwd.x);
		vec2 loc = vec2(dot(rel, rgt), dot(rel, fwd)) / barco_radio;
		// Forma de casco: proa afilada (loc.y=+1) y popa redondeada (loc.y=-1).
		// El medio ancho permitido varía a lo largo de la eslora.
		float t = loc.y;
		if (t <= 1.0 && t >= -1.0) {
			float w = (t >= 0.0)
				? pow(1.0 - t, recorte_proa_exp)   // hacia la proa: se afila
				: pow(1.0 + t, recorte_popa_exp);  // hacia la popa: se redondea
			if (abs(loc.x) < w) {
				discard;
			}
		}
	}

	// Normal de la ola: analítica, no por diferencias finitas. El punto se desplaza también en
	// horizontal, así que restar dos alturas medidas en x y en x+e no da la pendiente que se ve.
	vec3 n_mundo = oleaje_normal_lod(reposo, lejania);
	// Encima, el relieve fino (estela y rizado), ese sí por diferencias finitas.
	float fino = 1.0 - smoothstep(alcance_fino * 0.5, alcance_fino, lejania);
	float h = relieve_fino(world_pos.xz, fino);
	float e = 0.08;
	float hx = relieve_fino(world_pos.xz + vec2(e, 0.0), fino);
	float hz = relieve_fino(world_pos.xz + vec2(0.0, e), fino);
	n_mundo = normalize(n_mundo + vec3(-(hx - h) / e, 0.0, -(hz - h) / e));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_mundo, 0.0)).xyz);

	vec3 col = color_agua.rgb;
	// Dos espumas: la de la cresta que rompe y la del rastro del barco.
	float espuma = smoothstep(0.45, 0.95, oleaje_pico(reposo, lejania)) * espuma_cresta;
	espuma = max(espuma, smoothstep(0.05, 0.09, abs(h)) * espuma_intensidad);
	col = mix(col, vec3(0.85, 0.92, 1.0), espuma);

	ALBEDO = col;
	ROUGHNESS = rugosidad;
	METALLIC = metalico;
	SPECULAR = especular;
}
