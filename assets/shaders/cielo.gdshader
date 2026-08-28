shader_type sky;

// Cielo panorámico: usa la IMAGEN por encima del horizonte y COLOR DE MAR por
// debajo, con transición suave. Así el cielo se ve bonito y, cuando el recorte del
// agua deja ver "hacia abajo", muestra color de mar (se funde con el agua).

uniform sampler2D panorama : source_color, filter_linear;
uniform vec3 color_mar : source_color = vec3(0.04, 0.16, 0.24);
uniform float suavizado : hint_range(0.0, 0.5) = 0.06;   // difuminado en el horizonte


void sky() {
	vec3 dir = normalize(EYEDIR);
	// Coordenadas equirectangulares (2:1) a partir de la dirección de vista.
	float u = atan(dir.x, -dir.z) / (2.0 * PI) + 0.5;
	float v = acos(clamp(dir.y, -1.0, 1.0)) / PI;
	vec3 cielo = texture(panorama, vec2(u, v)).rgb;

	// Por debajo del horizonte (dir.y < 0) → color de mar; transición suave.
	float t = smoothstep(-suavizado, suavizado, dir.y);
	COLOR = mix(color_mar, cielo, t);
}
