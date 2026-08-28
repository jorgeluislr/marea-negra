shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Agua opaca reflectante (portada de game-2d). El reflejo lo aporta el SSR del
// WorldEnvironment. La estela (rastro de anillos) la rellena el script mar.gd con
// la posición del barco.
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

// Oleaje ambiente (olas grandes suaves de mar abierto).
uniform float ola_amplitud : hint_range(0.0, 0.2) = 0.03;
uniform float ola_escala : hint_range(0.1, 5.0) = 0.8;
uniform float ola_velocidad : hint_range(0.0, 3.0) = 0.6;

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

float altura(vec2 p) {
	// Oleaje ambiente de mar abierto.
	float h = sin(p.x * ola_escala + TIME * ola_velocidad) * ola_amplitud;
	h += cos(p.y * ola_escala * 1.3 - TIME * ola_velocidad * 0.9) * ola_amplitud;
	// Rizado fino.
	h += sin(p.x * 2.5 + TIME * 1.1) * 0.005;
	h += cos(p.y * 3.0 - TIME * 0.9) * 0.005;

	// Anillos de estela expandiéndose y desvaneciéndose.
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
	return h;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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

	// Normal por píxel a partir del campo de altura (nítida, no depende del mallado).
	float h = altura(world_pos.xz);
	float e = 0.08;
	float hx = altura(world_pos.xz + vec2(e, 0.0));
	float hz = altura(world_pos.xz + vec2(0.0, e));
	vec3 n_mundo = normalize(vec3(-(hx - h) / e, 1.0, -(hz - h) / e));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_mundo, 0.0)).xyz);

	vec3 col = color_agua.rgb;
	float espuma = smoothstep(0.05, 0.09, abs(h));
	col = mix(col, vec3(0.85, 0.92, 1.0), espuma * espuma_intensidad);

	ALBEDO = col;
	ROUGHNESS = rugosidad;
	METALLIC = metalico;
	SPECULAR = especular;
}
