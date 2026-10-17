// Terreno de las islas: arena, hierba y roca por altura y pendiente, en triplanar.
//
// Mismo enfoque que `AcabadoMadera`: unas pocas texturas TILEABLES compartidas por todas las
// islas, proyectadas en triplanar por coordenadas de mundo, en vez de un atlas horneado por isla.
// Una isla de 500 m con un atlas de 4096² daría un píxel cada 12 cm; la baldosa repetida da el
// detalle que se quiera en cualquier isla, y el reparto lo deciden la altura y la pendiente, que
// ya están en la malla.
//
// Se hunde con la curvatura del planeta igual que el agua (`agua.gdshader`) y que el barco
// (`Barco`): `d²/2R` con `d` la distancia HORIZONTAL a la cámara y `R` el de `Horizonte`, que lo
// pone `GestorTierra` cada frame. Si no, una isla lejana flota por encima de su propio mar.
shader_type spatial;
render_mode world_vertex_coords, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D arena : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D hierba : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roca : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Repeticiones por metro de cada baldosa.
uniform float rep_arena = 0.35;
uniform float rep_hierba = 0.18;
uniform float rep_roca = 0.12;
// Hasta qué cota sobre el agua llega la arena, en metros.
uniform float cota_arena = 1.8;
// Pendiente (1 − normal.y) a partir de la cual asoma la roca. 0,3 son ~46°.
uniform float pendiente_roca = 0.3;
// Lo que oscurece la arena mojada y el fondo.
uniform vec3 tinte_mojado = vec3(0.55, 0.5, 0.42);
// Nivel del agua en reposo, en Y de mundo. Lo pone `GestorTierra` desde `Oleaje.nivel`.
uniform float nivel_agua = 0.0;
uniform float radio_tierra = 6371000.0;

varying vec3 pos_mundo;
varying vec3 normal_mundo;
// Dónde cae el cero local en el mapa absoluto (autoload `Origen`). La textura va en absoluto o
// resbalaría sobre la isla a cada recentrado, y basta con el origen MÓDULO 100 m: las tres baldosas
// (2,86, 5,56 y 8,33 m) caben un número entero de veces en 100, y el origen va en metros enteros,
// así que `mod` es exacto en precisión simple. Si cambian las repeticiones, que 100 m siga siendo
// múltiplo de todas.
global uniform vec2 origen_mundo;


void vertex() {
	pos_mundo = VERTEX + vec3(mod(origen_mundo.x, 100.0), 0.0, mod(origen_mundo.y, 100.0));
	normal_mundo = NORMAL;
	float d = distance(VERTEX.xz, CAMERA_POSITION_WORLD.xz);
	VERTEX.y -= d * d / (2.0 * radio_tierra);
}


vec3 triplanar(sampler2D t, vec3 p, vec3 w, float rep) {
	return texture(t, p.zy * rep).rgb * w.x
		+ texture(t, p.xz * rep).rgb * w.y
		+ texture(t, p.xy * rep).rgb * w.z;
}


void fragment() {
	vec3 n = normalize(normal_mundo);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float alto = pos_mundo.y - nivel_agua;
	float pendiente = 1.0 - n.y;

	vec3 c_arena = triplanar(arena, pos_mundo, w, rep_arena);
	vec3 c_hierba = triplanar(hierba, pos_mundo, w, rep_hierba);
	vec3 c_roca = triplanar(roca, pos_mundo, w, rep_roca);

	// La linde de la arena se rompe con la propia hierba, para que no sea una curva de nivel.
	float quiebre = (c_hierba.g - 0.3) * 1.5;
	float m_arena = 1.0 - smoothstep(cota_arena - 0.4, cota_arena + 0.6, alto + quiebre);
	float m_roca = smoothstep(pendiente_roca - 0.08, pendiente_roca + 0.08, pendiente);
	vec3 c = mix(c_hierba, c_arena, m_arena);
	c = mix(c, c_roca, m_roca);
	// Mojado junto al agua y bajo ella.
	float mojado = 1.0 - smoothstep(-0.2, 0.5, alto);
	c *= mix(vec3(1.0), tinte_mojado, mojado);

	ALBEDO = c;
	ROUGHNESS = mix(mix(0.92, 0.85, m_roca), 0.45, mojado);
	SPECULAR = 0.35;
}
