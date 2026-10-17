// Estela de un barco. Los datos los empuja `Estela` (scripts/mundo/estela.gd), que explica de
// dónde sale cada parte. Necesita `oleaje.gdshaderinc` y `agua_detalle.gdshaderinc` incluidos
// antes (de este último, `ruido_d`).
//
// Lo que había eran anillos que se abrían a 1,6 m/s desde cada posición del barco, heredados de
// otro proyecto. Medido sobre un casco de 2,4 m de manga a 4,5 m/s: ninguna banda tras la popa,
// la ola más alta a 5,4° del rumbo y nada de espuma junto al costado.

const int ESTELA_N = 48;
const int ESTELA_PERFIL_N = 32;
// Semiángulo de Kelvin: atan(1/√8) = 19,47°, el mismo para cualquier barco en aguas profundas.
const float TAN_KELVIN = 0.35355;

uniform vec4 estela_traza[ESTELA_N];   // x, z de la popa; edad (s, <0 = vacía); velocidad (m/s)
uniform vec4 estela_pose = vec4(0.0, 0.0, 0.0, -1.0);   // centro x, z; proa x, z
uniform float estela_perfil[ESTELA_PERFIL_N];
uniform vec2 estela_perfil_z = vec2(0.0);   // z de la proa (lo) y de la popa (hi), ejes del barco
uniform float estela_vel = 0.0;
// Altura de las olas de Kelvin a la velocidad de referencia; crecen con el cuadrado de la
// velocidad, que es como crece la energía que el casco les da.
uniform float estela_ola = 0.12;
uniform float estela_vel_ref = 4.5;
// Cuánto dura la espuma de la banda de popa, y cuánto se abre la banda por segundo (en mangas).
uniform float estela_vida = 5.0;
uniform float estela_apertura = 0.12;


float _estela_medio_ancho(float z) {
	float lo = estela_perfil_z.x;
	float hi = estela_perfil_z.y;
	if (hi <= lo || z < lo || z > hi) {
		return 0.0;
	}
	float u = (z - lo) / (hi - lo) * float(ESTELA_PERFIL_N - 1);
	int a = int(floor(u));
	int b = min(a + 1, ESTELA_PERFIL_N - 1);
	return mix(estela_perfil[a], estela_perfil[b], u - float(a));
}


float _estela_semimanga() {
	float m = 0.0;
	for (int k = 0; k < ESTELA_PERFIL_N; k++) {
		m = max(m, estela_perfil[k]);
	}
	return m;
}


// Dónde cae el cero local en el mapa absoluto (autoload `Origen`, parámetro global). El ruido de la
// espuma de la estela va en ABSOLUTO: `p` es local y salta a cada recentrado del origen flotante, y
// con él saltaría el dibujo entero. Este ruido no rola con el viento, así que no necesita el marco
// del barco que usan el relieve fino y la espuma de las crestas (`_marco_viento`): con él, el dibujo
// dependía de dónde estuviera el barco de verdad, y `mundo` / "la estela es tan ancha como el casco"
// —que monta un rastro sintético— pasó de 0,794 a 0,635 según dónde hubiera navegado antes.
global uniform vec2 origen_mundo;


// Encaje de espuma: venas de ruido (`1 − |n|`), con huecos; `relleno` de 0 a 1 las cierra.
float _estela_encaje(vec2 p, float relleno) {
	vec2 m = p + origen_mundo;
	float v1 = 1.0 - 2.0 * abs(ruido_d(m * 0.9 + vec2(17.1, 3.3)).x);
	float v2 = 1.0 - 2.0 * abs(ruido_d(m * 2.3 + vec2(5.7, 61.9)).x);
	return smoothstep(mix(0.6, 0.15, relleno), 0.9, 0.6 * v1 + 0.4 * v2);
}


// x, y = gradiente del relieve de la estela; z = espuma (0-1); w = altura.
vec4 agua_estela(vec2 p) {
	float eslora = estela_perfil_z.y - estela_perfil_z.x;
	if (eslora <= 0.0 || estela_traza[0].z < 0.0) {
		return vec4(0.0);
	}
	vec2 centro = estela_pose.xy;
	vec2 proa_dir = estela_pose.zw;
	// Nada lejos del barco: la estela no pasa de unos 10 s de rastro.
	if (distance(p, centro) > 6.0 * eslora + 60.0) {
		return vec4(0.0);
	}
	float semimanga = _estela_semimanga();
	vec2 proa = centro - proa_dir * estela_perfil_z.x;

	// --- El punto del rastro más cercano. El primer tramo va de la PROA a la popa de ahora, para
	// que los brazos de Kelvin nazcan donde nacen; después, las muestras de la popa hacia atrás.
	float mejor = 1e9;
	float s_mejor = 0.0;     // distancia a lo largo del rastro, medida desde la proa
	float d_mejor = 0.0;     // distancia de lado, con signo
	float edad = 0.0;
	float vel = 0.0;
	vec2 tan_mejor = -proa_dir;
	bool delante = false;
	bool pasado = false;     // más allá de la muestra más vieja
	float edad_max = 0.0;
	float s_acum = 0.0;
	vec2 a = proa;
	float edad_a = 0.0;
	float vel_a = estela_traza[0].w;
	for (int i = 0; i < ESTELA_N; i++) {
		vec4 m = estela_traza[i];
		if (m.z < 0.0) {
			break;
		}
		vec2 b = m.xy;
		vec2 ab = b - a;
		float l = length(ab);
		if (l > 0.001) {
			vec2 t = ab / l;
			float u = dot(p - a, t);
			float uc = clamp(u, 0.0, l);
			vec2 q = a + t * uc;
			float dd = distance(p, q);
			if (dd < mejor) {
				mejor = dd;
				s_mejor = s_acum + uc;
				d_mejor = dot(p - q, vec2(-t.y, t.x));
				float f = uc / l;
				edad = mix(edad_a, m.z, f);
				vel = mix(vel_a, m.w, f);
				tan_mejor = t;
				delante = (i == 0 && u < 0.0);
				pasado = (u > l);
			}
			s_acum += l;
		}
		edad_max = m.z;
		a = b;
		edad_a = m.z;
		vel_a = m.w;
	}
	if (delante || mejor > 1e8) {
		// Por delante de la proa el agua todavía no sabe que viene un barco.
		vel = 0.0;
	}
	// Pasada la muestra más vieja tampoco: el barco no ha estado ahí, o ya no queda nada de su
	// paso. `pasado` se queda con el último tramo que lo ganó; si un tramo posterior está más
	// cerca, ese ya no lo es.
	if (pasado && edad >= edad_max - 0.001) {
		vel = 0.0;
	}
	vec2 normal = vec2(-tan_mejor.y, tan_mejor.x);
	// La distancia REAL al rastro, no la de lado: pasado el final de un tramo la de lado sigue
	// valiendo cero a lo largo de su prolongación, y la banda seguía en línea recta más allá de
	// donde el barco había pasado. Al envejecer la curva de un giro, lo que quedaba era esa recta.
	float y = mejor;
	float lado = sign(d_mejor);

	// --- Olas de Kelvin: dos brazos a 19,47° del rumbo desde la proa. Su longitud de onda es la
	// de la ola divergente en la cúspide, 2/3 de la de una ola que viajara a la velocidad del
	// barco (`2π·v²/g`), así que un barco rápido deja olas largas y uno lento, rizos.
	vec2 grad = vec2(0.0);
	float h = 0.0;
	float espuma = 0.0;
	if (vel > 0.3) {
		float rel = vel / estela_vel_ref;
		float lambda = 6.2831853 * vel * vel / 9.81 * 0.667;
		float k = 6.2831853 / lambda;
		float grosor = 0.6 + 0.06 * s_mejor;
		float brazo = y - TAN_KELVIN * s_mejor;
		float cresta = exp(-brazo * brazo / (grosor * grosor));
		float apaga = exp(-s_mejor / (5.0 * eslora)) * smoothstep(0.0, 1.5, s_mejor);
		float amp = estela_ola * rel * rel * apaga;
		float onda = cos(k * s_mejor);
		h = amp * cresta * onda;
		// Gradiente analítico: a lo largo del rastro cambia la fase y la posición del brazo; de
		// lado, solo la posición del brazo.
		float d_cresta_dy = cresta * (-2.0 * brazo / (grosor * grosor));
		float dh_ds = amp * (cresta * (-k * sin(k * s_mejor)) + onda * d_cresta_dy * (-TAN_KELVIN));
		float dh_dy = amp * onda * d_cresta_dy;
		grad = tan_mejor * dh_ds + normal * (lado * dh_dy);
		// La ola de proa rompe junto al casco: espuma sobre el brazo, solo en su cresta y solo
		// cerca del barco. Más allá el brazo es OLA, no espuma: con espuma hasta una eslora y media
		// por detrás, la V se veía como dos regueros blancos.
		float filo = exp(-brazo * brazo / (0.25 * grosor * grosor));
		float rompe = filo * exp(-s_mejor / (0.5 * eslora)) * smoothstep(1.0, 3.0, vel);
		espuma = max(espuma, rompe * 0.6 * _estela_encaje(p, 0.2));

		// --- La banda de agua revuelta: nace en el cuarto de POPA, pegada al casco y con su
		// forma, y detrás se abre despacio hacia la manga y más allá, apagándose con la edad.
		// Empezaba en la popa justa y se veía nacer detrás del timón. Recién batida es casi
		// blanca; después, encaje.
		if (s_mejor > 0.55 * eslora) {
			float casco = _estela_medio_ancho(estela_perfil_z.x + min(s_mejor, eslora - 0.05 * eslora));
			// Por fuera del forro: es agua que el casco ya ha apartado.
			float base = max(casco + 0.7, 0.35 * semimanga);
			float ancho = mix(base, semimanga, 1.0 - exp(-edad / 1.2)) * (1.0 + estela_apertura * edad);
			// El borde no es una regla: el agua revuelta se sale a bocanadas.
			// Dos escalas: bocanadas de unos 3 m y flecos de uno.
			float borde = 0.65 * ruido_d(vec2(s_mejor * 0.33, lado * 3.1 + ola_t * 0.15)).x
				+ 0.35 * ruido_d((p + origen_mundo) * 1.1 + vec2(ola_t * 0.2, 7.7)).x;
			ancho *= 1.0 + 0.6 * borde;
			// Un borde de anchura FIJA, no un porcentaje del ancho: en proporción, una banda
			// estrecha —la que sale pegada al casco— se quedaba sin núcleo, todo él dentro del forro.
			float banda = 1.0 - smoothstep(ancho - 1.0, ancho + 0.3, y);
			float vida = exp(-edad / estela_vida) * smoothstep(0.5, 2.5, vel)
				* (1.0 - smoothstep(0.7 * edad_max, edad_max, edad))
				* smoothstep(0.55 * eslora, 0.7 * eslora, s_mejor);
			float fresca = exp(-edad / 1.5);
			espuma = max(espuma, banda * vida * _estela_encaje(p, 0.4 + 0.6 * fresca));
		}
	}

	// --- Espuma pegada al costado, en ejes del barco: la proa aparta el agua y la deja blanca
	// contra el forro, más ancha cuanto más rápido va, y casi nada hacia la popa.
	vec2 rel_p = p - centro;
	float z_b = -dot(rel_p, proa_dir);
	float x_b = abs(dot(rel_p, vec2(-proa_dir.y, proa_dir.x)));
	float z_c = clamp(z_b, estela_perfil_z.x, estela_perfil_z.y);
	float hw = _estela_medio_ancho(z_c);
	float fuera = length(vec2(max(x_b - hw, 0.0), z_b - z_c));
	float a_proa = 1.0 - (z_c - estela_perfil_z.x) / eslora;
	float rapido = smoothstep(0.5, 2.5, estela_vel);
	float franja = (0.25 + 0.6 * a_proa) * (0.4 + 0.6 * rapido);
	float pegada = (1.0 - smoothstep(0.0, franja, fuera)) * rapido * (0.35 + 0.65 * a_proa);
	if (x_b > hw - 0.05 || z_b < estela_perfil_z.x || z_b > estela_perfil_z.y) {
		espuma = max(espuma, pegada * _estela_encaje(p, 0.7));
	}

	return vec4(grad, clamp(espuma, 0.0, 1.0), h);
}
