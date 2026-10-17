// Detalle del agua más fino que la ola: lo que se dibuja en la normal y lo que, por no caber en
// el píxel, pasa a la rugosidad. Va en un include, y no dentro de `agua.gdshader`, para que el
// espejo de las pruebas (`tools/espejo_oleaje.gdshader`) lea exactamente la misma función.
//
// Necesita `oleaje.gdshaderinc` incluido antes.
//
// **La cuenta que manda es la de Cox y Munk (1954)**: midiendo desde avión el brillo del sol
// sobre el mar sacaron la pendiente cuadrática media de la superficie, `0,003 + 0,00512·U` con
// U en m/s. Casi toda está en olas de menos de un metro, que la malla no puede dibujar. Antes de
// esto el agua solo tenía la de los ocho trenes de Gerstner y tres rizos de 5 mm: medido, el
// **6 %** de lo que pide el viento junto a la cámara y el **0,7 %** a 600 m, sin nada en la
// rugosidad. Eso es lo que se veía como cristal.
//
// El reparto, de grande a pequeño:
// - los trenes de Gerstner dibujan lo suyo en la malla;
// - seis octavas de ruido (2,1 m a 10 cm) dibujan en la NORMAL la parte del resto que les toca
//   por la anchura de banda que cubren — en escala logarítmica, como el rango de saturación del
//   espectro, donde cada octava lleva la misma pendiente;
// - lo que queda por debajo de 10 cm, hasta el pico capilar de 1,7 cm, va siempre a la
//   rugosidad;
// - y lo que NO cabe en el píxel —una octava más corta que unos píxeles, o un tren de Gerstner
//   que el LOD ha apagado— no se pierde: pasa a la rugosidad. Si se perdiera, el mar lejano
//   volvería a ser un espejo justo donde más se nota.

// Pendiente cuadrática media que el viento pide a la superficie (Cox-Munk). La empuja `Oleaje`.
uniform float pendiente_viento = 0.0;
// Altura de la mar, pico a pico, para saber cuándo un punto está en la cresta. La empuja `Oleaje`.
uniform float ola_altura = 1.0;
// Cuánto aclara la cresta: el agua es fina allí y deja pasar la luz.
uniform float tono_cresta : hint_range(0.0, 1.0) = 0.45;

const int DETALLE_N = 6;
const float DETALLE_LARGO_MAX = 2.1;    // m
const float DETALLE_RAZON = 0.55;       // de una octava a la siguiente: no es 1/2, para no cuadrar
const float LARGO_CAPILAR = 0.017;      // m: el pico de las ondas capilares
// Pendiente cuadrática media de `ruido_d` en una celda de lado 1, MEDIDA con la batería
// (`mundo` / textura del mar), no calculada: depende del hash y del interpolante. Con 1,0 las
// seis octavas dibujaban 0,0357 donde se les pedían 0,0496.
const float RUIDO_PENDIENTE2 = 0.72;


// Coordenadas del ruido en el marco del viento (x a lo largo, y de través), relativas al barco y
// con su camino sumado: ver `ruido_ref` y `ruido_acum` en `oleaje.gdshaderinc`. Girar el viento
// gira el ruido alrededor del barco y no del cero del mundo.
//
// `ruido_acum` va en precisión simple y crece con lo navegado, y eso tiene un precio que conviene
// saber: la octava más fina mide 10 cm y tras 120 km su coordenada de ruido pasa del millón de
// celdas, donde un `float` solo distingue octavos de celda (1,2 cm). Tras 50 km son 3 mm. Se ve
// como nada; si algún día se ve, la salida es un ruido periódico con el camino reducido a su
// periodo.
vec2 _marco_viento(vec2 p, vec2 viento) {
	vec2 rel = p - ruido_ref;
	return vec2(dot(rel, viento), dot(rel, vec2(-viento.y, viento.x))) + ruido_acum;
}


uint _hash_u(uvec2 q) {
	q = q * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	n ^= n >> 16u;
	n *= 2246822519u;
	n ^= n >> 13u;
	return n;
}


vec2 _gradiente(ivec2 c) {
	uint h = _hash_u(uvec2(c));
	float a = float(h & 65535u) / 65535.0 * 6.2831853;
	return vec2(cos(a), sin(a));
}


// Ruido de gradiente con su derivada analítica (x = valor, yz = gradiente). Analítica para no
// evaluarlo tres veces por diferencias finitas.
vec3 ruido_d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	ivec2 c = ivec2(i);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	vec2 ga = _gradiente(c);
	vec2 gb = _gradiente(c + ivec2(1, 0));
	vec2 gc = _gradiente(c + ivec2(0, 1));
	vec2 gd = _gradiente(c + ivec2(1, 1));
	float va = dot(ga, f);
	float vb = dot(gb, f - vec2(1.0, 0.0));
	float vc = dot(gc, f - vec2(0.0, 1.0));
	float vd = dot(gd, f - vec2(1.0, 1.0));
	float k = va - vb - vc + vd;
	float v = va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * k;
	vec2 d = ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd)
		+ du * (u.yx * k + vec2(vb, vc) - va);
	return vec3(v, d);
}


// Pendiente cuadrática media que dan los trenes de Gerstner a amplitud plena: Σ ½(k·A)².
float _pendiente2_gerstner() {
	float s = 0.0;
	for (int i = 0; i < OLEAJE_N; i++) {
		float ka = ola_coef[i].x * ola_coef[i].y;
		s += 0.5 * ka * ka;
	}
	return s;
}


// Gradiente del relieve fino en `p` (xy) y las dos varianzas de pendiente (z = la que se
// dibuja, w = la que no cabe en el píxel y hay que llevar a la rugosidad).
//
// `huella` es lo que mide un píxel sobre el agua, en metros.
vec4 agua_detalle(vec2 p, float dist, float huella) {
	float resto = max(pendiente_viento - _pendiente2_gerstner(), 0.0);
	float largo_min = DETALLE_LARGO_MAX * pow(DETALLE_RAZON, float(DETALLE_N - 1));
	float banda = log(DETALLE_LARGO_MAX / largo_min) / log(DETALLE_LARGO_MAX / LARGO_CAPILAR);
	float por_octava = resto * banda / float(DETALLE_N);
	float oculta = resto * (1.0 - banda);
	float dibujada = 0.0;

	vec2 viento = ola_dir[0];
	vec2 g = vec2(0.0);
	float largo = DETALLE_LARGO_MAX;
	vec2 mv = _marco_viento(p, viento);
	for (int o = 0; o < DETALLE_N; o++) {
		// Cada octava va en su dirección, abierta en abanico alrededor del viento, y a la
		// velocidad de fase de agua profunda de su longitud: unas olas adelantan a otras.
		float ang = float(o) * 2.39996 - 0.6;   // ángulo áureo: no se repiten
		vec2 dir = normalize(viento * cos(ang * 0.45) + vec2(-viento.y, viento.x) * sin(ang * 0.45));
		vec2 lat = vec2(-dir.y, dir.x);
		float frec = 1.0 / largo;
		float vel = sqrt(9.81 * largo / 6.2831853);
		// El marco de la octava es el del viento girado `b`: se gira `mv` y no el punto.
		float b = ang * 0.45;
		vec2 mo = vec2(mv.x * cos(b) + mv.y * sin(b), mv.y * cos(b) - mv.x * sin(b));
		vec2 q = vec2(mo.x - vel * ola_t, mo.y) * frec + vec2(float(o) * 17.3, float(o) * 5.1);
		// Se ve entera si cubre seis píxeles, y nada por debajo de dos: lo que no cabe, a la
		// rugosidad.
		float w = smoothstep(2.0 * huella, 6.0 * huella, largo);
		// Pendiente pedida = (a·frec)²·RUIDO_PENDIENTE2 → a·frec = sqrt(por_octava / RUIDO).
		float af = sqrt(por_octava / RUIDO_PENDIENTE2);
		vec2 d = ruido_d(q).yz * af;
		g += (dir * d.x + lat * d.y) * w;
		dibujada += por_octava * w * w;
		oculta += por_octava * (1.0 - w * w);
		largo *= DETALLE_RAZON;
	}

	// Lo que el LOD ha quitado a los trenes de Gerstner tampoco se pierde.
	for (int i = 0; i < OLEAJE_N; i++) {
		float k = ola_coef[i].x;
		float a0 = oleaje_amp(i, p, 0.0);
		float a1 = oleaje_amp(i, p, dist);
		oculta += 0.5 * k * k * max(a0 * a0 - a1 * a1, 0.0);
	}
	return vec4(g, dibujada, oculta);
}


// Cuánto se aclara el agua por estar en la cresta (0 en el valle). `alto` es lo que la ola ha
// subido este punto sobre la lámina en reposo.
//
// Satura al 30 % de la altura nominal y no a la mitad, que sería la cresta de un tren solo: los
// ocho se cruzan y se cancelan, y en 80 m de mar con viento 1 la cresta más alta llega a 0,59 m
// de los 1,04 de media altura. Saturando ahí, la menos clara de las crestas sacaba 0,15.
float agua_tono_cresta(float alto) {
	return smoothstep(0.0, 0.3 * max(ola_altura, 0.01), alto) * tono_cresta;
}


// --- Espuma de las crestas -----------------------------------------------------------------
//
// Sale donde la ola se PICA (`oleaje_pico`, el término que estrecha la cresta en Gerstner), no
// donde está alta, y cubre la fracción del mar que dicen Monahan y O'Muircheartaigh (1980) para
// este viento: `3,84·10⁻⁶ · U^3,41`. El umbral lo calcula `Oleaje`, que sabe cuánto se pica
// esta mar; aquí solo se compara.
//
// Antes el umbral era fijo, 0,45-0,95, y medido cubría el 0 % del mar con viento 1 Y con 1,8:
// esta mar no se pica tanto nunca.
//
// El ruido rompe la espuma en manchas y jirones en vez de pintar la cresta entera de una pieza,
// que es lo que hace que una línea de espuma se lea como dibujada.
uniform float espuma_umbral = 10.0;
uniform float espuma_ancho = 0.01;
uniform float espuma_ruido = 0.0;


float agua_espuma(vec2 p, float dist) {
	float j = oleaje_pico(p, dist);
	if (j <= 0.0) {
		return 0.0;
	}
	vec2 viento = ola_dir[0];
	vec2 mv = _marco_viento(p, viento);
	// DÓNDE rompe viaja con la cresta: el ruido que deforma la mancha corre con la ola dominante.
	vec2 q = vec2(mv.x - 4.0 * ola_t, mv.y);
	float n = 0.6 * ruido_d(q * vec2(0.18, 0.32) + vec2(31.7, 7.3)).x
		+ ruido_d(q * vec2(0.55, 0.9) + vec2(3.1, 57.9)).x
		+ 0.6 * ruido_d(q * vec2(1.6, 2.4) + vec2(13.3, 91.1)).x;
	float jj = j + n * espuma_ruido;
	// Rastro: un encaje tenue donde la ola casi rompe, que es lo que queda detrás de cada
	// rotura. Sin él la espuma era todo o nada, con un borde de mancha.
	float rastro = smoothstep(espuma_umbral - 6.0 * espuma_ancho, espuma_umbral, jj);
	if (rastro <= 0.0) {
		return 0.0;
	}
	float mancha = smoothstep(espuma_umbral - espuma_ancho, espuma_umbral + espuma_ancho, jj);
	// El DIBUJO de la espuma, en cambio, va pegado al agua (`p` es el punto de reposo, que ya
	// viaja con la órbita) y solo deriva despacio a favor del viento. Corriendo con la cresta,
	// como iba, el encaje entero resbalaba sobre el mar y se leía como una mancha que se
	// desliza, no como espuma que nace y se deshace.
	vec2 r = vec2(mv.x - 0.3 * ola_t, mv.y);
	float v1 = 1.0 - 2.0 * abs(ruido_d(r * vec2(0.55, 0.85) + vec2(11.3, 4.7)).x);
	float v2 = 1.0 - 2.0 * abs(ruido_d(r * vec2(1.5, 2.1) + vec2(71.9, 23.5)).x);
	float v3 = ruido_d(r * vec2(3.1, 3.7) + vec2(5.9, 41.3)).x;
	float venas = 0.6 * v1 + 0.4 * v2;
	// Donde rompe más fuerte el encaje se CIERRA, pero nunca del todo: sigue teniendo huecos.
	float fuerza = smoothstep(espuma_umbral + espuma_ancho, espuma_umbral + 8.0 * espuma_ancho, jj);
	float encaje = smoothstep(mix(0.62, 0.38, fuerza), 0.92, venas);
	float tenue = smoothstep(0.75, 0.95, venas) * 0.35;
	// Y no es un blanco liso: la densidad del aire en el agua varía de un palmo a otro.
	float densidad = 0.6 + 0.4 * clamp(v3 * 2.0 + 0.5, 0.0, 1.0);
	return max(mancha * encaje, rastro * tenue) * densidad;
}
