shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// ── Tela con viento, por color de vértice ─────────────────────────────────────
// Un solo modelo (casco + velas + bandera). Dos máscaras en el color de vértice:
//   · ROJO  (COLOR.r) = peso de movimiento: 0 = fijo (casco/amarre), 1 = borde libre.
//   · VERDE (COLOR.g) = es BANDERA (>0.5) -> comportamiento propio (ondea libre,
//     anclada por un solo lado). El resto de tela con rojo = VELA.
//
// VELA: reacciona al ÁNGULO entre viento y la cara (vela_normal). De cara se LLENA
//       (comba a sotavento) y queda tensa; de canto FLAMEA. Fluye a sotavento.
// BANDERA: ondea entera hacia sotavento desde su anclaje (bandera_ancla) y latiguea.
//
// tela.gd inyecta las texturas del modelo (Meshy) y todos los vectores en espacio LOCAL.

uniform sampler2D textura_albedo : source_color, hint_default_white;
uniform sampler2D textura_normal : hint_normal;
uniform sampler2D textura_emision : source_color, hint_default_black;
uniform bool usar_normal = false;
uniform bool usar_emision = false;
uniform float rugosidad : hint_range(0.0, 1.0) = 0.7;
uniform float metalico : hint_range(0.0, 1.0) = 0.0;
uniform float emision_fuerza : hint_range(0.0, 3.0) = 0.6;

// Viento y vela, TODO en el espacio LOCAL de la malla (lo garantiza tela.gd).
uniform vec3 viento_dir = vec3(1.0, 0.0, 0.0);   // dirección normalizada (mundo->local)
uniform float viento_fuerza = 1.0;               // intensidad (con ráfagas)
uniform vec3 vela_normal = vec3(1.0, 0.0, 0.0);  // normal de la cara de la vela (ajuste de plano)
uniform float vela_confianza = 1.0;              // 1 = una vela plana (normal fiable) ; ~0 = varias velas

// Ajuste del movimiento de la VELA
uniform float amplitud : hint_range(0.0, 0.6) = 0.06;    // escala global del desplazamiento
uniform float hinchado : hint_range(0.0, 2.0) = 0.9;     // cuánto se comba al llenarse (de cara)
uniform float frecuencia : hint_range(0.0, 20.0) = 4.0;  // nº de pliegues del flameo
uniform float velocidad : hint_range(0.0, 12.0) = 2.5;   // rapidez del flameo
uniform float flameo : hint_range(0.0, 2.0) = 0.65;      // amplitud del flameo al estar de canto
uniform float flameo_base : hint_range(0.0, 1.0) = 0.08; // aleteo residual del pujamen aun llena
uniform float flameo_max : hint_range(0.0, 1.0) = 0.55;  // tope del "de canto" (limita el pico de vibración)

// Cilindro del mástil, en el espacio LOCAL de la malla (mismo espacio que 'vela_normal').
uniform vec3 mastil_base = vec3(0.0);
uniform vec3 mastil_eje = vec3(0.0, 1.0, 0.0);
uniform float mastil_radio = 0.0;   // 0 = sin colisión
// Cabos que sostienen el mástil, como cápsulas (segmento + radio). 'cabos_n' = cuántos valen.
uniform vec3 cabos_a[4];
uniform vec3 cabos_b[4];
uniform float cabos_radio = 0.012;
uniform int cabos_n = 0;
// PERCHAS (verga y botavara) como cápsulas, en grupo aparte porque son mucho más gruesas
// que los cabos: 25-35 mm frente a 12. Sin ellas la vela recogida atraviesa la botavara.
uniform vec3 perchas_a[2];
uniform vec3 perchas_b[2];
uniform float perchas_radio = 0.028;
uniform int perchas_n = 0;
uniform float respuesta_rafaga : hint_range(0.0, 1.0) = 0.4; // cuánto pican las ráfagas en el aleteo

// Ajuste del movimiento de la BANDERA (canal verde)
uniform vec3 bandera_ancla = vec3(0.0);                     // punto de izada (espacio local)
uniform vec3 bandera_dir_reposo = vec3(1.0, 0.0, 0.0);      // dir. izada->vuelo en reposo (local)
uniform vec3 bandera_eje = vec3(0.0, 1.0, 0.0);            // eje del mástil (vertical) en local
uniform float bandera_giro = 0.0;                           // ángulo de yaw a sotavento (rad), lo pone tela.gd
uniform float bandera_largo = 0.3;                          // largo izada->vuelo en reposo (local)
uniform float bandera_desfase_mastil : hint_range(0.0, 1.0) = 0.15; // desplaza el eje de giro hacia el mástil (fracción del largo)
uniform float bandera_latigo : hint_range(0.0, 1.5) = 0.5;     // amplitud de los pliegues
uniform float bandera_frecuencia : hint_range(0.0, 30.0) = 12.0;
uniform float bandera_velocidad : hint_range(0.0, 20.0) = 7.0;


// Fuerza para las ONDAS con las ráfagas amortiguadas: comprime f hacia 1 según
// respuesta_rafaga (0 = aleteo constante, 1 = escala completa con la ráfaga).
float fuerza_oscilacion(float f) {
	return max(0.0, 1.0 + respuesta_rafaga * (f - 1.0));
}


// Colisión con el MÁSTIL: con el viento de proa la vela se comba hacia el palo y lo
// atravesaría. Como no hay física, se empuja el vértice fuera de un cilindro (eje del
// mástil) después de desplazarlo. 'mastil_radio' = 0 desactiva la comprobación.
// Empuja 'p' (el vértice ya desplazado) fuera de la cápsula a-b de radio r. 'v0' es el
// vértice EN REPOSO y marca de qué lado del obstáculo vive la tela.
//
// El vértice se APOYA en la superficie: se le pone un tope a lo que puede avanzar hacia el
// obstáculo, conservando el movimiento tangencial (así resbala en vez de clavarse). Nunca
// se le devuelve más allá: rebotarlo lo alejaría más de lo que estaba y la tela parecería
// inflarse CONTRA el viento, que es justo lo que no queremos.
vec3 fuera_de_capsula(vec3 v0, vec3 p, vec3 a, vec3 b, float r) {
	if (r <= 0.0) {
		return p;
	}
	vec3 ab = b - a;
	float len2 = max(dot(ab, ab), 0.000001);

	vec3 c0 = a + ab * clamp(dot(v0 - a, ab) / len2, 0.0, 1.0);
	vec3 rad0 = v0 - c0;
	float dist0 = length(rad0);
	if (dist0 < r) {
		return p;      // en reposo ya estaba dentro: no lo tocamos (no deformar el modelo)
	}
	vec3 dir = rad0 / dist0;

	vec3 c = a + ab * clamp(dot(p - a, ab) / len2, 0.0, 1.0);
	vec3 rad = p - c;
	float proy = dot(rad, dir);
	float avance = dist0 - proy;           // cuánto se ha acercado al obstáculo
	if (avance <= 0.0) {
		return p;                          // se aleja: nada que hacer
	}
	// Freno ASINTÓTICO: cada vértice gasta su propio margen hasta el obstáculo y nunca
	// llega a tocarlo. Un tope seco frenaba a unos vértices y a sus vecinos no, y la tela
	// se rasgaba; aquí la corrección es una función continua de la distancia de reposo,
	// que varía suave entre vecinos, así que la malla se comba en vez de abrirse.
	float margen = max(dist0 - r, 0.00001);
	float permitido = margen * (1.0 - exp(-avance / margen));
	return c + rad + dir * (avance - permitido);
}


// El mástil es una cápsula muy larga sobre su eje; los cabos, cápsulas cortas.
vec3 fuera_de_los_obstaculos(vec3 v0, vec3 p) {
	vec3 eje = normalize(mastil_eje) * 4.0;
	p = fuera_de_capsula(v0, p, mastil_base - eje, mastil_base + eje, mastil_radio);
	for (int i = 0; i < cabos_n; i++) {
		p = fuera_de_capsula(v0, p, cabos_a[i], cabos_b[i], cabos_radio);
	}
	for (int i = 0; i < perchas_n; i++) {
		p = fuera_de_capsula(v0, p, perchas_a[i], perchas_b[i], perchas_radio);
	}
	return p;
}


// Desplazamiento de la VELA (membrana amarrada por varios bordes).
vec3 desplazamiento_vela(vec3 v, float w) {
	vec3 n = normalize(vela_normal);
	float f = viento_fuerza;

	// Ángulo de ataque: cuánto del viento incide sobre la cara de la vela.
	float dwn = dot(viento_dir, n);
	float lleno = abs(dwn);               // 1 = de cara (llena/tensa), 0 = de canto
	float canteo = 1.0 - lleno;           // 1 = de canto (flamea)
	float lado = dwn >= 0.0 ? 1.0 : -1.0; // hacia sotavento
	vec3 n_lee = n * lado;

	// Si la normal es poco fiable (varias velas con orientaciones distintas en la MISMA
	// malla, p.ej. la goleta), el 'canteo' no es de fiar y dispara el flameo -> las puntas
	// vibran. Con baja CONFIANZA: (a) el flameo tiende a un valor bajo (vela casi tensa) y
	// (b) se ATENÚAN los términos que usan la normal (n_lee/lateral), que van mal orientados.
	// Tope al "de canto" (min con flameo_max): evita el PICO de flameo cuando la vela queda
	// de canto al viento -> es la vibración puntual que se veía poco natural.
	float canteo_eff = mix(0.12, min(canteo, flameo_max), vela_confianza);
	float amort = mix(0.35, 1.0, vela_confianza);

	// Marco local: 'inplane' avance de la onda ; 'lateral' 3er eje en el plano.
	vec3 inplane = viento_dir - n * dwn;
	float il = length(inplane);
	if (il > 0.001) {
		inplane /= il;
	} else {
		inplane = normalize(cross(n, vec3(0.0, 1.0, 0.0)));
	}
	vec3 lateral = normalize(cross(n, inplane));

	// Onda viajera a lo largo de la vela, en la dirección del viento.
	float fase = dot(v, inplane) * frecuencia - TIME * velocidad * (0.5 + f);
	float onda_n = sin(fase) + 0.4 * sin(fase * 2.3 + dot(v, n) * 3.0);
	float onda_l = sin(fase * 1.7 + 1.3);

	float aleteo = canteo_eff * flameo + flameo_base;
	float f_osc = fuerza_oscilacion(f);

	vec3 desp = vec3(0.0);
	// 1) ARRASTRE hacia sotavento (dirección del viento, fiable siempre).
	desp += viento_dir * hinchado * amplitud * (0.5 + 0.5 * lleno) * f * w;
	// 2) BARRIGA a sotavento (usa la normal -> se atenúa si es poco fiable).
	desp += n_lee * hinchado * 0.5 * amplitud * lleno * f * w * amort;
	// 3) RIZO 2D: la onda cruza la vela (usa la normal -> se atenúa si es poco fiable).
	desp += n_lee * onda_n * amplitud * aleteo * f_osc * w * amort;
	desp += lateral * onda_l * amplitud * aleteo * 0.6 * f_osc * w * amort;
	return desp;
}


// Desplazamiento de la BANDERA (anclada por un solo lado, ondea libre como tela).
// GIRA alrededor del mástil (yaw sobre 'bandera_eje') para orientarse a sotavento:
// una rotación CONSERVA la longitud (no estira) y puede girar del todo aunque el viento
// venga por detrás. El giro es progresivo a lo largo (0 en la izada -> máx. en el vuelo),
// así la izada queda pinchada al mástil y la bandera se curva hacia el viento. Encima,
// PLIEGUES viajeros del amarre al vuelo (envolvente creciente, octavas, diagonal).
vec3 desplazamiento_bandera(vec3 v, float w) {
	// SIN early return por w: el giro es RÍGIDO y tiene que alcanzar a toda la bandera,
	// incluido el gratil cosido al asta (rojo = 0). Si se excluye, esos vértices se quedan
	// clavados mientras el resto rota y aparece un trozo estático en el amarre. Los pliegues
	// sí dependen de w, y se anulan solos ahí porque su envolvente es u².
	float f = viento_fuerza;
	float f_osc = fuerza_oscilacion(f);

	vec3 r0 = normalize(bandera_dir_reposo);   // eje de la bandera en reposo (izada -> vuelo)
	vec3 m = normalize(bandera_eje);           // eje del mástil (vertical)

	// Ángulo de YAW a sotavento (lo calcula tela.gd). La bandera SIEMPRE apunta a sotavento;
	// la fuerza del viento afecta al ondeo, no a la dirección.
	float u = w;                               // 0 en la izada, 1 en el vuelo
	// Giro RÍGIDO y COMPLETO: toda la bandera gira el mismo ángulo (NO progresivo -> no se
	// enrolla) y siempre del todo (±180° coinciden -> el cruce por detrás no salta). La izada,
	// sobre el eje del mástil, apenas se mueve.
	float ang = bandera_giro;
	float ca = cos(ang);
	float sa = sin(ang);
	// Eje de giro desplazado desde el borde de amarre hacia el CENTRO del mástil: hacia
	// atrás de la izada (dirección opuesta al vuelo, horizontal), una fracción del largo.
	vec3 r0h = r0 - m * dot(r0, m);
	r0h = length(r0h) > 0.001 ? normalize(r0h) : r0;
	vec3 pivote = bandera_ancla - r0h * bandera_desfase_mastil * bandera_largo;
	vec3 rel = v - pivote;
	// Rodrigues alrededor de m (rotación pura -> sin estiramiento).
	vec3 rel_rot = rel * ca + cross(m, rel) * sa + m * dot(m, rel) * (1.0 - ca);
	vec3 desp = rel_rot - rel;

	// Eje de la bandera tras el giro, para orientar los pliegues.
	vec3 r_now = normalize(r0 * ca + cross(m, r0) * sa + m * dot(m, r0) * (1.0 - ca));
	vec3 lat = cross(r_now, m);
	lat = length(lat) > 0.001 ? normalize(lat) : normalize(cross(r_now, vec3(0.0, 0.0, 1.0)));
	vec3 vert = normalize(cross(lat, r_now));

	// PLIEGUES viajeros: envolvente creciente (u²), varias octavas + diagonal por altura.
	float env = u * u;
	float p = u;
	float h = dot(rel, vert) / max(bandera_largo, 0.001);
	float t = TIME;
	float wv = bandera_velocidad;
	float wf = bandera_frecuencia;
	float onda_h = sin(p * wf - t * wv + h * 1.5)
	             + 0.5 * sin(p * wf * 1.9 - t * wv * 1.3 + h * 2.3 + 1.1)
	             + 0.25 * sin(p * wf * 3.3 - t * wv * 0.7 + 2.7);
	float onda_v = sin(p * wf * 0.8 - t * wv * 0.9 + 2.0)
	             + 0.4 * sin(p * wf * 1.6 - t * wv * 1.1 + 0.5);
	desp += lat * onda_h * bandera_latigo * bandera_largo * env * f_osc;
	desp += vert * onda_v * bandera_latigo * 0.45 * bandera_largo * env * f_osc;

	return desp;
}


void vertex() {
	float w = COLOR.r;   // peso de movimiento
	// La BANDERA se decide por el verde, no por el peso: gira rígida y entera, así que el
	// gratil (rojo = 0) también tiene que pasar por aquí o se queda estático mientras el
	// resto rota. La VELA sí se filtra por peso: ahí un 0 significa cosido a la percha.
	if (COLOR.g > 0.5) {
		VERTEX += desplazamiento_bandera(VERTEX, w);
	} else if (w > 0.001) {
		VERTEX = fuera_de_los_obstaculos(VERTEX, VERTEX + desplazamiento_vela(VERTEX, w));
	}
}

void fragment() {
	ALBEDO = texture(textura_albedo, UV).rgb;
	ROUGHNESS = rugosidad;
	METALLIC = metalico;
	if (usar_normal) {
		NORMAL_MAP = texture(textura_normal, UV).rgb;
	}
	if (usar_emision) {
		EMISSION = texture(textura_emision, UV).rgb * emision_fuerza;
	}
}
