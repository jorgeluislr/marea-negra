// Olas de Gerstner (trocoidales): LA definición del oleaje del juego.
//
// La misma fórmula vive dos veces —aquí y en `scripts/mundo/oleaje.gd`— porque el shader
// deforma la malla y el barco necesita preguntar la altura desde GDScript, y no hay forma de
// compartir código entre los dos. Por eso los coeficientes se calculan UNA vez en GDScript y
// se envían ya masticados (k, amplitud, Q, omega): lo único que se duplica es la suma, y
// `tools/espejo_oleaje.tscn` la compara punto a punto contra el espejo de GDScript.
//
// Gerstner y no suma de senos: un seno da un rizo simétrico y las olas de verdad tienen la
// cresta afilada y el valle ancho, porque las partículas describen círculos. Cuesta lo mismo:
// además de subir y bajar, el punto se corre en horizontal hacia la cresta.

const int OLEAJE_N = 8;

uniform vec2 ola_dir[OLEAJE_N];    // hacia dónde viaja cada tren, unitaria
// GRUPOS: cada tren no sopla igual en todas partes, va y viene en trenes de olas. xy = vector
// de onda del grupo (rad/m), z = su velocidad angular, w = cuánto se hunde la amplitud (0 = el
// tren es uniforme, 1 = llega a callarse del todo).
//
// Es lo que quita el patrón. Sumar ondas planas —por muchas que sean y por muy dispares que
// tengan las longitudes— siempre deja un desplazamiento en el que todas vuelven a encajar a la
// vez: con ocho trenes el mar seguía siendo idéntico a sí mismo corrido 132 m (autocorrelación
// 0,963). Modulando cada tren con una envolvente lenta y propia, el encaje ya no puede darse
// porque la envolvente también tendría que encajar, y además es como se comporta el mar de
// verdad, donde las olas llegan en grupos.
uniform vec4 ola_grupo[OLEAJE_N];
uniform vec4 ola_coef[OLEAJE_N];   // x = k (rad/m), y = amplitud (m), z = Q, w = omega (rad/s)
// Fase añadida de cada tren: x = la de la ola, y = la de su grupo, en radianes y reducida a una
// vuelta. La lleva `Oleaje` en doble precisión, y es lo que hace que la ola siga en su sitio
// ABSOLUTO cuando el origen flotante recentra el mundo, y que el mar role alrededor del barco y no
// del cero (ver `Oleaje._girar_en_el_pivote()`). Sumar el origen aquí, en precisión simple, daría
// fases de decenas de miles de radianes con pasos de milésimas. Sin poner valen cero.
uniform vec2 ola_fase[OLEAJE_N];
// El ruido del relieve fino y de la espuma, con la misma idea: se dibuja relativo a `ruido_ref`
// (el barco, en coordenadas locales) más `ruido_acum`, el camino que ha hecho el barco en absoluto
// proyectado sobre el viento (x) y su perpendicular (y). Así no salta al recentrar ni barre al rolar
// el viento, por lejos del cero que se navegue.
uniform vec2 ruido_ref = vec2(0.0);
uniform vec2 ruido_acum = vec2(0.0);
uniform float ola_t = 0.0;         // reloj del oleaje: lo empuja `Oleaje`, no es TIME
// Entre qué distancias de la cámara se APAGA cada tren, en metros (x = empieza, y = acabada).
// Es el LOD del oleaje: una ola de 7 m sobre celdas de 3 no se dibuja, se convierte en un
// encaje de escamas que hierve (aliasing puro: el patrón que sale no tiene nada que ver con la
// ola). Apagarla donde la malla deja de resolverla es lo único que lo quita.
//
// Son DOS distancias y no una porque el apagado se nota: con un tramo corto el mar pasa de
// tener olas a estar liso de golpe y se ve la juntura. Cada tren empieza a perder amplitud
// donde la celda ya solo le da ocho puntos por ola y termina apagado donde le da tres, que es
// un degradado largo y atado a lo que la malla puede dibujar de verdad.
//
// **El LOD es solo para lo que se DIBUJA.** Lo que responde `Oleaje.altura_en()` —lo que usa
// el barco para flotar— nunca lo lleva, y a distancia cero la atenuación vale exactamente 1,
// así que junto a la cámara el mar que se ve y el que se calcula son el mismo.
// (Sin valor por defecto: GLSL no admite inicializar un array uniforme. Un alcance de cero se
// entiende como "sin LOD", así que un material al que nadie se lo fije enseña la ola entera en
// vez de quedarse en un mar plano.)
uniform vec2 ola_alcance[OLEAJE_N];


// Amplitud del tren `i` en el punto `p` y a `dist` metros de la cámara: la suya, hundida por su
// grupo y apagada por el LOD.
float oleaje_amp(int i, vec2 p, float dist) {
	float a = ola_coef[i].y;
	vec4 g = ola_grupo[i];
	if (g.w > 0.0) {
		a *= 1.0 - g.w * (0.5 + 0.5 * sin(dot(g.xy, p) + ola_fase[i].y - g.z * ola_t));
	}
	vec2 alc = ola_alcance[i];
	if (alc.y <= 0.0) {
		return a;
	}
	return a * (1.0 - smoothstep(alc.x, alc.y, dist));
}


// Dónde acaba el punto de superficie que en reposo estaba en `p` (horizontal, mundo).
// Devuelve el DESPLAZAMIENTO, no la posición: y = altura, xz = arrastre hacia la cresta.
vec3 oleaje_desplaz_lod(vec2 p, float dist) {
	vec3 d = vec3(0.0);
	for (int i = 0; i < OLEAJE_N; i++) {
		float k = ola_coef[i].x;
		float a = oleaje_amp(i, p, dist);
		if (k <= 0.0 || a <= 0.0) {
			continue;
		}
		float f = k * dot(ola_dir[i], p) + ola_fase[i].x - ola_coef[i].w * ola_t;
		d.y += a * sin(f);
		d.xz += ola_dir[i] * (ola_coef[i].z * a * cos(f));
	}
	return d;
}


// Sin LOD: la ola entera, que es la que hay que comparar contra el espejo de GDScript.
vec3 oleaje_desplaz(vec2 p) {
	return oleaje_desplaz_lod(p, 0.0);
}


// Normal analítica en el punto de reposo `p` (GPU Gems 1, cap. 1). Analítica y no por
// diferencias finitas porque el punto se desplaza también en horizontal: restar dos alturas
// medidas en x y en x+e no da la pendiente de la superficie, que es lo que se ve.
vec3 oleaje_normal_lod(vec2 p, float dist) {
	vec3 n = vec3(0.0, 1.0, 0.0);
	for (int i = 0; i < OLEAJE_N; i++) {
		float k = ola_coef[i].x;
		float a = oleaje_amp(i, p, dist);
		if (k <= 0.0 || a <= 0.0) {
			continue;
		}
		float f = k * dot(ola_dir[i], p) + ola_fase[i].x - ola_coef[i].w * ola_t;
		n.xz -= ola_dir[i] * (k * a * cos(f));
		n.y -= ola_coef[i].z * k * a * sin(f);
	}
	return normalize(n);
}


vec3 oleaje_normal(vec2 p) {
	return oleaje_normal_lod(p, 0.0);
}


// Cuánto se está PICANDO la cresta aquí: 0 en el valle, 1 donde la ola se afila hasta
// romper. Es el término que estrecha la cresta en Gerstner, y por eso vale de espuma sin
// inventarse nada — la espuma sale donde la ola rompe, no donde está alta.
float oleaje_pico(vec2 p, float dist) {
	float j = 0.0;
	for (int i = 0; i < OLEAJE_N; i++) {
		float k = ola_coef[i].x;
		float a = oleaje_amp(i, p, dist);
		if (k <= 0.0 || a <= 0.0) {
			continue;
		}
		float f = k * dot(ola_dir[i], p) + ola_fase[i].x - ola_coef[i].w * ola_t;
		j += ola_coef[i].z * k * a * sin(f);
	}
	return clamp(j, 0.0, 1.0);
}
