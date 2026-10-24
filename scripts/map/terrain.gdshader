// Desenha o mapa inteiro com transições naturais e suaves entre os terrenos.
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
//   - fazendas (improvement_map): a imagem da fazenda vista de cima (lotes
//     em retalhos com cerca; em obra, terra lavrada), com borda suave.
// O miolo de cada casa (core_*) puxa os pesos para o terreno da própria casa:
// mesmo uma casa isolada (ilha de 1 casa) aparece com o terreno dela, e o
// desenho continua batendo com as regras.
// Visual suavizado (desde 23/10/2026): as texturas são filtradas (com
// mipmaps) e toda borda passa por uma rampa (edge_softness) mais o tamanho de
// um pixel da tela (fwidth): nada fica serrilhado, em qualquer zoom.
// view_origin/view_cells: desenha só um pedaço do mapa (janela da cidade).
shader_type canvas_item;

// Mapa de terrenos: 1 pixel por casa, tipo (Terrain.Type) no canal vermelho.
uniform sampler2D terrain_map : filter_nearest;
uniform vec2 map_size;
// Pedaço do mapa desenhado (em casas). view_cells = 0: o mapa inteiro.
uniform vec2 view_origin = vec2(0.0);
uniform vec2 view_cells = vec2(0.0);
uniform sampler2D water_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D forest_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D cerrado_tex : repeat_enable, filter_linear_mipmap;
uniform bool draw_grid = true;
uniform float grid_darken = 0.15;
// Largura das rampas nas bordas (em "peso"; 0 = borda dura).
uniform float edge_softness = 0.025;
// Quanto o ruído empurra as bordas (0 = bordas lisas; abaixo de 0,5 sempre).
uniform float coast_noise = 0.2;
uniform float forest_noise = 0.25;
// Miolo da casa: até que distância do centro (em casas) e com que força os
// pesos ficam com o terreno da própria casa.
uniform float core_radius = 0.42;
uniform float core_strength = 0.6;
uniform vec4 sand_color : source_color = vec4(0.76, 0.70, 0.50, 1.0);
uniform vec4 foam_color : source_color = vec4(0.76, 0.82, 0.82, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.36, 0.54, 0.56, 1.0);
// Melhorias por casa (GameMap.Improvement no canal vermelho): 0 nenhuma,
// 1 fazenda pronta, 2 fazenda em obra (só terra arada).
uniform sampler2D improvement_map : filter_nearest;
uniform bool draw_farms = true;
// Fazenda vista de cima (lotes em retalhos com cerca) e fazenda em obra
// (terra lavrada): uma imagem por casa (City.FARM_TEXTURE / FARM_NEW_TEXTURE).
uniform sampler2D farm_tex : filter_linear_mipmap;
uniform sampler2D farm_new_tex : filter_linear_mipmap;
// Borda suave da fazenda onde a casa vizinha não é fazenda (em casas).
uniform float farm_edge_soft = 0.04;

const int WATER = 0;
const int GRASSLAND = 1;
const int FOREST = 2;
const int CERRADO = 3;

// Número pseudoaleatório de 0 a 1 para um ponto da grade do ruído (hash12 de
// Dave Hoskins). Não usa sin() de números grandes: com as coordenadas do mapa,
// "fract(sin(x) * 43758)" ampliava diferenças mínimas de arredondamento da
// GPU, o mesmo canto da grade dava valores diferentes em casas vizinhas e o
// ruído saía em blocos (cortes retos na borda da floresta e da costa).
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

// Ruído em camadas, de 0 a 1.
float fbm(vec2 p) {
	return value_noise(p) * 0.55 + value_noise(p * 2.03 + 17.0) * 0.3 + value_noise(p * 4.1 + 31.0) * 0.15;
}

// Rampa suave em volta de [param edge]: largura edge_softness mais 1 pixel de tela.
float soft_step(float edge, float value) {
	float w = edge_softness + fwidth(value);
	return smoothstep(edge - w, edge + w, value);
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

// (água, pradaria, floresta, cerrado) com 1 no terreno [param t].
vec4 one_hot(int t) {
	return vec4(t == WATER ? 1.0 : 0.0, t == GRASSLAND ? 1.0 : 0.0, t == FOREST ? 1.0 : 0.0, t == CERRADO ? 1.0 : 0.0);
}

// Textura do terreno na posição p (em casas). A textura é contínua (sem
// emenda) e é lida girada e um pouco ampliada, cada terreno num ângulo: o
// padrão não se repete alinhado com a grade e não há cortes na borda das casas
// (espelhar casa a casa cortava as copas da floresta).
vec4 tile_color(sampler2D tex, vec2 p, float angle) {
	mat2 turn = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * 0.82;
	vec2 uv = turn * p;
	return textureGrad(tex, uv, dFdx(uv), dFdy(uv));
}

void fragment() {
	vec2 p = view_cells.x > 0.0 ? view_origin + UV * view_cells : UV * map_size;

	// Pesos de cada terreno (água, pradaria, floresta, cerrado) pela spline
	// quadrática das 3x3 casas ao redor da casa em que o ponto está
	ivec2 own_cell = ivec2(floor(p));
	vec2 t = fract(p) - 0.5; // -0,5..0,5 a partir do centro da casa
	vec3 wx = vec3(0.5 * (0.5 - t.x) * (0.5 - t.x), 0.75 - t.x * t.x, 0.5 * (0.5 + t.x) * (0.5 + t.x));
	vec3 wy = vec3(0.5 * (0.5 - t.y) * (0.5 - t.y), 0.75 - t.y * t.y, 0.5 * (0.5 + t.y) * (0.5 + t.y));
	vec4 weights = vec4(0.0);
	for (int j = 0; j < 3; j++) {
		for (int i = 0; i < 3; i++) {
			weights += wx[i] * wy[j] * one_hot(terrain_at(own_cell + ivec2(i - 1, j - 1)));
		}
	}
	// Miolo da casa: puxa para o terreno dela
	float core = (1.0 - smoothstep(core_radius * 0.5, core_radius, length(t))) * core_strength;
	weights = mix(weights, one_hot(terrain_at(own_cell)), core);
	int own_improvement = improvement_at(own_cell);
	float water = weights.x;
	float grass = weights.y;
	float forest = weights.z;
	float cerrado = weights.w;

	float n_coast = fbm(p * 1.8) - 0.5;
	float n_land = fbm(p * 2.4 + 50.0) - 0.5;
	float n_color = fbm(p * 0.35 + 90.0);

	// Terra: pradaria e cerrado se misturam devagar; a floresta tem borda
	// recortada, mas com uma rampa suave
	float land_total = max(grass + forest + cerrado, 0.0001);
	float forest_share = forest / land_total;
	float cerrado_share = cerrado / max(grass + cerrado, 0.0001);
	float c = smoothstep(0.15, 0.85, cerrado_share + n_land * 0.35);
	vec4 open_land = mix(tile_color(grass_tex, p, 0.31), tile_color(cerrado_tex, p, -0.47), c);
	float forest_edge = forest_share + n_land * forest_noise * 2.0;
	float trees = soft_step(0.5, forest_edge);
	// Sombra das árvores sobre a pradaria logo ao lado da floresta
	open_land.rgb *= 1.0 - 0.18 * smoothstep(0.2, 0.5, forest_edge);
	vec4 land_color = mix(open_land, tile_color(forest_tex, p, 0.58), trees);

	// Fazendas: a imagem da fazenda (pronta ou em obra) na casa inteira, com
	// borda suave só nos lados em que a casa vizinha não é fazenda (fazendas
	// vizinhas se juntam numa colcha de lotes)
	if (draw_farms) {
		vec2 f = fract(p);
		float w = farm_edge_soft + fwidth(p.x);
		float fade = (improvement_at(own_cell + ivec2(-1, 0)) > 0 ? 1.0 : smoothstep(0.0, w, f.x))
				* (improvement_at(own_cell + ivec2(1, 0)) > 0 ? 1.0 : smoothstep(0.0, w, 1.0 - f.x))
				* (improvement_at(own_cell + ivec2(0, -1)) > 0 ? 1.0 : smoothstep(0.0, w, f.y))
				* (improvement_at(own_cell + ivec2(0, 1)) > 0 ? 1.0 : smoothstep(0.0, w, 1.0 - f.y));
		vec3 planted = textureGrad(farm_tex, f, dFdx(p), dFdy(p)).rgb;
		vec3 tilled = textureGrad(farm_new_tex, f, dFdx(p), dFdy(p)).rgb;
		float in_farm = (own_improvement > 0 ? 1.0 : 0.0) * fade * (1.0 - trees);
		land_color.rgb = mix(land_color.rgb, own_improvement == 1 ? planted : tilled, in_farm);
	}
	land_color.rgb *= 0.94 + 0.12 * n_color;

	// Água: mais clara perto da costa
	float land = 1.0 - water + n_coast * coast_noise * 2.0;
	vec4 water_color = tile_color(water_tex, p, -0.22);
	water_color.rgb = mix(water_color.rgb, shallow_color.rgb, smoothstep(0.05, 0.5, land) * 0.45);
	water_color.rgb *= 0.9 + 0.18 * n_color; // manchas mais escuras e mais claras (profundidade)

	// Costa: espuma na beira da água, faixa de areia na beira da terra (a
	// floresta vai até a água sem areia), tudo em rampas suaves
	vec3 water_side = mix(water_color.rgb, foam_color.rgb, soft_step(0.46, land) * 0.85);
	vec3 land_side = mix(sand_color.rgb, land_color.rgb, max(soft_step(0.57, land), trees));
	vec3 color = mix(water_side, land_side, soft_step(0.5, land));

	// Linha de grade fina e suave na borda de cada casa. Some aos poucos com o
	// zoom bem afastado (casa com menos de ~25 pixels na tela), para não virar
	// uma trama
	if (draw_grid) {
		vec2 f = fract(p);
		float pixel = fwidth(p.x); // tamanho de 1 pixel da tela, em casas
		float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		float line = 1.0 - smoothstep(0.0, pixel * 1.2, edge);
		color *= 1.0 - grid_darken * line * (1.0 - smoothstep(0.04, 0.07, pixel));
	}
	COLOR = vec4(color, 1.0);
}
