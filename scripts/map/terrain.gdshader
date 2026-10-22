// Desenha o mapa inteiro com transições naturais entre os terrenos.
//
// terrain_map (também a textura do Sprite) é o mapa de terrenos: 1 pixel por
// casa, com o tipo (Terrain.Type) no canal vermelho. Cada pixel da tela olha as
// 3x3 casas ao redor e calcula o "peso" de cada terreno com uma spline
// quadrática (suaviza a "escadinha" das diagonais em linhas e curvas). Somando
// um ruído, as bordas ficam arredondadas e irregulares:
//   - costa: limite em 0,5 entre terra e água, com areia e espuma, e água
//     mais clara perto da praia;
//   - floresta: borda recortada em "moitas", com sombra na pradaria ao lado;
//   - pradaria <-> cerrado: mistura gradual;
//   - fazendas (improvement_map): campos com borda orgânica e cerca viva,
//     fileiras onduladas numa direção por casa; em obra, só terra arada.
// O miolo de cada casa (core_*) puxa os pesos para o terreno da própria casa:
// mesmo uma casa isolada (ilha de 1 casa) aparece com o terreno dela, e o
// desenho continua batendo com as regras.
// A posição é arredondada para os pixels do tile (tile_pixels por casa), para
// manter o visual de pixel art.
shader_type canvas_item;

// Mapa de terrenos: 1 pixel por casa, tipo (Terrain.Type) no canal vermelho.
uniform sampler2D terrain_map : filter_nearest;
uniform vec2 map_size;
uniform float tile_pixels = 40.0;
uniform sampler2D water_tex : repeat_enable, filter_nearest;
uniform sampler2D grass_tex : repeat_enable, filter_nearest;
uniform sampler2D forest_tex : repeat_enable, filter_nearest;
uniform sampler2D cerrado_tex : repeat_enable, filter_nearest;
uniform bool draw_grid = true;
uniform float grid_darken = 0.2;
// Quanto o ruído empurra as bordas (0 = bordas lisas; abaixo de 0,5 sempre).
uniform float coast_noise = 0.2;
uniform float forest_noise = 0.25;
// Miolo da casa: até que distância do centro (em casas) e com que força os
// pesos ficam com o terreno da própria casa.
uniform float core_radius = 0.42;
uniform float core_strength = 0.6;
uniform vec4 sand_color : source_color = vec4(0.86, 0.80, 0.56, 1.0);
uniform vec4 foam_color : source_color = vec4(0.82, 0.92, 0.97, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.30, 0.68, 0.82, 1.0);
// Melhorias por casa (GameMap.Improvement no canal vermelho): 0 nenhuma,
// 1 fazenda pronta, 2 fazenda em obra (só terra arada).
uniform sampler2D improvement_map : filter_nearest;
uniform float farm_noise = 0.22;
// Fileiras de plantação por casa.
uniform float farm_rows = 5.0;
uniform vec4 soil_color : source_color = vec4(0.50, 0.35, 0.19, 1.0);
uniform vec4 hedge_color : source_color = vec4(0.27, 0.42, 0.17, 1.0);
// Cores das plantações (cada fazenda sorteia uma): trigo, verde-claro, verde.
uniform vec4 crop_color_a : source_color = vec4(0.84, 0.72, 0.33, 1.0);
uniform vec4 crop_color_b : source_color = vec4(0.62, 0.74, 0.30, 1.0);
uniform vec4 crop_color_c : source_color = vec4(0.45, 0.62, 0.24, 1.0);

const int WATER = 0;
const int GRASSLAND = 1;
const int FOREST = 2;
const int CERRADO = 3;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Ruído em camadas, de 0 a 1.
float fbm(vec2 p) {
	return value_noise(p) * 0.55 + value_noise(p * 2.03 + 17.0) * 0.3 + value_noise(p * 4.1 + 31.0) * 0.15;
}

int terrain_at(ivec2 cell) {
	if (cell.x < 0 || cell.y < 0 || cell.x >= int(map_size.x) || cell.y >= int(map_size.y)) {
		return WATER; // fora do mapa é mar
	}
	return int(round(texelFetch(terrain_map, cell, 0).r * 255.0));
}

int improvement_at(ivec2 cell) {
	if (cell.x < 0 || cell.y < 0 || cell.x >= int(map_size.x) || cell.y >= int(map_size.y)) {
		return 0;
	}
	return int(round(texelFetch(improvement_map, cell, 0).r * 255.0));
}

// Fazenda: fileiras levemente onduladas, numa direção sorteada por casa
// (fazendas vizinhas viram uma "colcha de retalhos"). Pronta: plantação com
// sulcos de terra; em obra: só terra arada.
vec3 farm_color(vec2 pq, ivec2 cell, bool planted, float shade) {
	float seed = hash(vec2(cell) + 21.3);
	bool vertical = seed > 0.5;
	float u = vertical ? pq.x : pq.y;
	float v = vertical ? pq.y : pq.x;
	float row = fract(u * farm_rows + 0.15 * sin(v * 2.7 + seed * 6.28));
	bool furrow = row < 0.3;
	vec3 color;
	if (planted) {
		float pick = hash(vec2(cell) + 7.7);
		vec3 crop = pick < 0.5 ? crop_color_a.rgb : pick < 0.8 ? crop_color_b.rgb : crop_color_c.rgb;
		color = furrow ? mix(soil_color.rgb, crop, 0.3) : crop;
	} else {
		color = furrow ? soil_color.rgb * 0.8 : soil_color.rgb * 1.12;
	}
	return color * shade;
}

// (água, pradaria, floresta, cerrado) com 1 no terreno [param t].
vec4 one_hot(int t) {
	return vec4(t == WATER ? 1.0 : 0.0, t == GRASSLAND ? 1.0 : 0.0, t == FOREST ? 1.0 : 0.0, t == CERRADO ? 1.0 : 0.0);
}

// Textura do terreno na posição p (em casas). Cada casa espelha a textura de
// um jeito (sorteado pela posição) para o padrão não se repetir em grade.
vec4 tile_color(sampler2D tex, vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	if (hash(cell + 3.7) > 0.5) local.x = 1.0 - local.x;
	if (hash(cell + 9.1) > 0.5) local.y = 1.0 - local.y;
	return texture(tex, local);
}

void fragment() {
	vec2 p = UV * map_size;
	// Centro do pixel do tile em que este ponto cai (visual de pixel art)
	vec2 pq = (floor(p * tile_pixels) + 0.5) / tile_pixels;

	// Pesos de cada terreno (água, pradaria, floresta, cerrado) pela spline
	// quadrática das 3x3 casas ao redor da casa em que o ponto está
	ivec2 own_cell = ivec2(floor(pq));
	vec2 t = fract(pq) - 0.5; // -0,5..0,5 a partir do centro da casa
	vec3 wx = vec3(0.5 * (0.5 - t.x) * (0.5 - t.x), 0.75 - t.x * t.x, 0.5 * (0.5 + t.x) * (0.5 + t.x));
	vec3 wy = vec3(0.5 * (0.5 - t.y) * (0.5 - t.y), 0.75 - t.y * t.y, 0.5 * (0.5 + t.y) * (0.5 + t.y));
	vec4 weights = vec4(0.0);
	// Fazendas (x = qualquer fazenda, y = fazenda pronta), com os mesmos pesos
	vec2 farm_weights = vec2(0.0);
	for (int j = 0; j < 3; j++) {
		for (int i = 0; i < 3; i++) {
			ivec2 cell = own_cell + ivec2(i - 1, j - 1);
			float weight = wx[i] * wy[j];
			weights += weight * one_hot(terrain_at(cell));
			int improvement = improvement_at(cell);
			farm_weights += weight * vec2(improvement > 0 ? 1.0 : 0.0, improvement == 1 ? 1.0 : 0.0);
		}
	}
	// Miolo da casa: puxa para o terreno dela
	float core = (1.0 - smoothstep(core_radius * 0.5, core_radius, length(t))) * core_strength;
	weights = mix(weights, one_hot(terrain_at(own_cell)), core);
	int own_improvement = improvement_at(own_cell);
	farm_weights = mix(farm_weights, vec2(own_improvement > 0 ? 1.0 : 0.0, own_improvement == 1 ? 1.0 : 0.0), core);
	float water = weights.x;
	float grass = weights.y;
	float forest = weights.z;
	float cerrado = weights.w;

	float n_coast = fbm(pq * 1.8) - 0.5;
	float n_land = fbm(pq * 2.4 + 50.0) - 0.5;
	float n_color = fbm(pq * 0.35 + 90.0);

	// Terra: pradaria e cerrado se misturam devagar; a floresta tem borda firme
	float land_total = max(grass + forest + cerrado, 0.0001);
	float forest_share = forest / land_total;
	float cerrado_share = cerrado / max(grass + cerrado, 0.0001);
	float c = smoothstep(0.15, 0.85, cerrado_share + n_land * 0.35);
	vec4 open_land = mix(tile_color(grass_tex, pq), tile_color(cerrado_tex, pq), c);
	float forest_edge = forest_share + n_land * forest_noise * 2.0;
	float trees = step(0.5, forest_edge);
	// Sombra das árvores sobre a pradaria logo ao lado da floresta
	open_land.rgb *= 1.0 - 0.18 * smoothstep(0.2, 0.5, forest_edge);
	vec4 land_color = mix(open_land, tile_color(forest_tex, pq), trees);

	// Fazendas: campo com borda orgânica e uma cerca viva em volta
	float n_farm = fbm(pq * 2.1 + 130.0) - 0.5;
	float farm_edge = farm_weights.x + n_farm * farm_noise * 2.0;
	if (farm_edge >= 0.5 && trees < 0.5) {
		bool planted = farm_weights.y >= farm_weights.x * 0.5;
		land_color.rgb = farm_edge < 0.56 ? hedge_color.rgb
				: farm_color(pq, own_cell, planted, 0.95 + 0.1 * fbm(pq * 3.0 + 7.0));
	}
	land_color.rgb *= 0.94 + 0.12 * n_color;

	// Água: mais clara perto da costa
	float land = 1.0 - water + n_coast * coast_noise * 2.0;
	vec4 water_color = tile_color(water_tex, pq);
	water_color.rgb = mix(water_color.rgb, shallow_color.rgb, smoothstep(0.05, 0.5, land) * 0.45);
	water_color.rgb *= 0.9 + 0.18 * n_color; // manchas mais escuras e mais claras (profundidade)

	vec4 color;
	if (land >= 0.5) {
		color = land >= 0.56 || trees > 0.5 ? land_color : sand_color; // faixa de areia na costa
	} else {
		color = land >= 0.45 ? foam_color : water_color; // espuma na beira da água
	}

	// Linha de grade: última coluna e última linha de pixels de cada casa
	if (draw_grid) {
		vec2 pixel = floor(fract(p) * tile_pixels);
		if (pixel.x >= tile_pixels - 1.0 || pixel.y >= tile_pixels - 1.0) {
			color.rgb *= 1.0 - grid_darken;
		}
	}
	COLOR = vec4(color.rgb, 1.0);
}
