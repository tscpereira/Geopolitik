// Textura das estradas e dos rios (camadas RoadLayer e RiverLayer do GameMap).
// Os desenhos chegam com cor lisa por vértice; este shader varia a cor pela
// posição no mapa (em casas):
//   - terra (estrada e a areia das margens dos rios): manchas maiores, granulado
//     e pedrinhas claras e escuras;
//   - água (azul): variação de profundidade e pequenos reflexos ondulados.
// Os detalhes finos somem aos poucos com o zoom afastado (fwidth), para não
// virar chuvisco. A transparência (bordas suaves, obras em andamento) não muda.
shader_type canvas_item;

uniform float tile_size = 80.0;
// Força das manchas, do granulado e das pedrinhas na terra.
uniform float dirt_blotch = 0.28;
uniform float dirt_grain = 0.14;
uniform float pebble_amount = 0.26;
// Força da variação e dos reflexos na água.
uniform float water_blotch = 0.18;
uniform float water_glints = 0.18;

varying vec2 map_position;

void vertex() {
	map_position = VERTEX / tile_size; // a camada fica na origem do mapa
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return value_noise(p) * 0.55 + value_noise(p * 2.03 + 17.0) * 0.3 + value_noise(p * 4.1 + 31.0) * 0.15;
}

void fragment() {
	vec4 color = COLOR;
	vec2 p = map_position;
	// 1 de perto; 0 quando uma casa fica com menos de ~20 pixels na tela
	float detail = 1.0 - smoothstep(0.03, 0.06, fwidth(p.x));
	bool water = color.b > color.r + 0.08;
	if (water) {
		color.rgb *= 1.0 - water_blotch * 0.5 + water_blotch * fbm(p * 3.0 + 9.0);
		// Reflexos e ondinhas sem direção (o rio corre para todos os lados):
		// ruído deformado, com pontos claros nos picos e escuros nos vales
		vec2 warp = vec2(value_noise(p * 5.0), value_noise(p * 5.0 + 3.7)) * 1.6;
		float wave = value_noise(p * 15.0 + warp);
		color.rgb += vec3(0.85, 0.92, 1.0) * water_glints * smoothstep(0.7, 0.86, wave) * detail;
		color.rgb *= 1.0 - water_glints * 0.45 * smoothstep(0.24, 0.1, wave) * detail;
	} else {
		color.rgb *= 1.0 - dirt_blotch * 0.5 + dirt_blotch * fbm(p * 2.5);
		color.rgb *= 1.0 + dirt_grain * (value_noise(p * 45.0) - 0.5) * 2.0 * detail;
		float dark = smoothstep(0.8, 0.88, value_noise(p * 24.0 + 7.0));
		float light = smoothstep(0.83, 0.9, value_noise(p * 29.0 + 41.0));
		color.rgb *= 1.0 - pebble_amount * dark * detail;
		color.rgb = mix(color.rgb, color.rgb * 1.35 + 0.04, pebble_amount * light * detail);
	}
	COLOR = color;
}
