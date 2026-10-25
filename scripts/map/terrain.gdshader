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
//   - colinas e montanhas: relevo visto de cima (como no Civilization do
//     SNES). Cada casa tem uma altura (montanha: pirâmides de pedra de faces
//     planas e bordas recortadas, com cristas até as montanhas vizinhas, que
//     formam uma cordilheira; colina: três morros arredondados) e a encosta
//     virada para a luz (em cima, à esquerda) fica clara, a outra escura;
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
uniform sampler2D hill_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D mountain_tex : repeat_enable, filter_linear_mipmap;
uniform bool draw_grid = true;
uniform float grid_darken = 0.15;
// Largura das rampas nas bordas (em "peso"; 0 = borda dura).
uniform float edge_softness = 0.025;
// Quanto o ruído empurra as bordas (0 = bordas lisas; abaixo de 0,5 sempre).
uniform float coast_noise = 0.2;
uniform float forest_noise = 0.25;
// Relevo: quanto a encosta escurece ou clareia com a inclinação (altura das
// montanhas e das colinas) e a direção da luz (x para a direita, y para baixo,
// z para cima).
uniform float mountain_relief = 1.1;
uniform float hill_relief = 0.75;
uniform vec3 light_dir = vec3(-0.55, -0.65, 0.75);
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
const int HILLS = 4;
const int MOUNTAINS = 5;

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

// (colinas, montanhas) com 1 no terreno [param t].
vec2 relief_hot(int t) {
	return vec2(t == HILLS ? 1.0 : 0.0, t == MOUNTAINS ? 1.0 : 0.0);
}

// Pesos dos terrenos no ponto p (em casas): spline quadrática das 3x3 casas ao
// redor, puxada para o terreno da própria casa no miolo. [param land] =
// (água, pradaria, floresta, cerrado), [param relief] = (colinas, montanhas).
void terrain_weights(vec2 p, out vec4 land, out vec2 relief) {
	ivec2 own_cell = ivec2(floor(p));
	vec2 t = fract(p) - 0.5; // -0,5..0,5 a partir do centro da casa
	vec3 wx = vec3(0.5 * (0.5 - t.x) * (0.5 - t.x), 0.75 - t.x * t.x, 0.5 * (0.5 + t.x) * (0.5 + t.x));
	vec3 wy = vec3(0.5 * (0.5 - t.y) * (0.5 - t.y), 0.75 - t.y * t.y, 0.5 * (0.5 + t.y) * (0.5 + t.y));
	land = vec4(0.0);
	relief = vec2(0.0);
	for (int j = 0; j < 3; j++) {
		for (int i = 0; i < 3; i++) {
			int type = terrain_at(own_cell + ivec2(i - 1, j - 1));
			land += wx[i] * wy[j] * one_hot(type);
			relief += wx[i] * wy[j] * relief_hot(type);
		}
	}
	// Miolo da casa: puxa para o terreno dela
	float core = (1.0 - smoothstep(core_radius * 0.5, core_radius, length(t))) * core_strength;
	int own = terrain_at(own_cell);
	land = mix(land, one_hot(own), core);
	relief = mix(relief, relief_hot(own), core);
}

// Pirâmide de faces planas (5 lados, girada por [param turn]) com o pico em
// [param center]: 1 no pico, 0 a [param radius] dele. O ruído recorta as
// arestas e a borda (rocha).
float pyramid(vec2 p, vec2 center, float radius, float turn) {
	vec2 d = p - center;
	float r = 0.0;
	for (int k = 0; k < 5; k++) {
		float a = turn + float(k) * 1.2566;
		r = max(r, dot(d, vec2(cos(a), sin(a))));
	}
	r /= 0.809; // cos(36 graus): o raio vai até os cantos
	r += (value_noise(p * 7.0 + center * 3.1) - 0.5) * 0.09;
	return 1.0 - r / radius;
}

// Centro do pico principal da casa de montanha [param cell] (um pouco fora do
// meio, sorteado pela casa).
vec2 peak_center(ivec2 cell) {
	vec2 seed = vec2(cell);
	return seed + 0.5 + (vec2(hash(seed + 3.1), hash(seed + 7.7)) - 0.5) * 0.2;
}

// Crista entre dois picos: 1 na linha de a até b, caindo em V (duas faces
// planas) até [param radius] dela, com a aresta recortada pelo ruído.
float ridge_line(vec2 p, vec2 a, vec2 b, float radius) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
	float d = length(p - a - ab * t) + (value_noise(p * 6.5 + a * 2.3) - 0.5) * 0.08;
	return 1.0 - d / radius;
}

// Altura das montanhas: em cada casa de montanha (das 3x3 ao redor), um pico
// principal e um menor ao lado, como pirâmides de pedra, e uma crista até o
// pico de cada casa de montanha vizinha: juntas, formam uma cordilheira.
float mountain_height(vec2 p) {
	ivec2 own = ivec2(floor(p));
	float h = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			ivec2 cell = own + ivec2(i, j);
			if (terrain_at(cell) != MOUNTAINS) {
				continue;
			}
			vec2 seed = vec2(cell);
			vec2 center = peak_center(cell);
			float turn = hash(seed + 1.9) * 6.283;
			for (int n = 0; n < 8; n++) {
				ivec2 dir = ivec2(n < 3 ? n - 1 : (n < 5 ? (n == 3 ? -1 : 1) : n - 6), n < 3 ? -1 : (n < 5 ? 0 : 1));
				if (terrain_at(cell + dir) == MOUNTAINS) {
					h = max(h, 0.62 * ridge_line(p, center, peak_center(cell + dir), 0.4));
				}
			}
			h = max(h, (0.85 + 0.3 * hash(seed + 5.3)) * pyramid(p, center, 0.7, turn));
			vec2 side = vec2(cos(turn * 1.7), sin(turn * 1.7)) * 0.3;
			h = max(h, 0.55 * pyramid(p, center + side, 0.42, turn + 0.6));
		}
	}
	return max(h, 0.0);
}

// Máximo suave: une dois morros sem vinco entre eles.
float smooth_max(float a, float b, float k) {
	float h = max(k - abs(a - b), 0.0) / k;
	return max(a, b) + h * h * k * 0.25;
}

// Altura das colinas: em cada casa de colina, um morro arredondado e dois
// menores encostados nele, unidos sem vinco.
float hill_height(vec2 p) {
	ivec2 own = ivec2(floor(p));
	float h = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			ivec2 cell = own + ivec2(i, j);
			if (terrain_at(cell) != HILLS) {
				continue;
			}
			vec2 seed = vec2(cell);
			float a = hash(seed + 2.3) * 6.283;
			vec2 center = seed + 0.5 + (vec2(hash(seed + 4.1), hash(seed + 6.7)) - 0.5) * 0.12;
			for (int k = 0; k < 3; k++) {
				float angle = a + float(k) * 2.4;
				vec2 c = center + (k == 0 ? vec2(0.0) : vec2(cos(angle), sin(angle)) * 0.27);
				float radius = k == 0 ? 0.5 : 0.36;
				float x = min(length(p - c) / radius, 1.0);
				h = smooth_max(h, (k == 0 ? 0.34 : 0.24) * (1.0 - x * x) * (1.0 - x * x), 0.08);
			}
		}
	}
	return h;
}

// Luz na encosta de inclinação [param slope] (derivadas da altura em x e y):
// 1 no plano, mais claro virado para a luz, mais escuro do outro lado.
float slope_light(vec2 slope) {
	vec3 normal = normalize(vec3(-slope, 1.0));
	vec3 light = normalize(light_dir);
	return max(dot(normal, light), 0.0) / light.z;
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

	// Pesos de cada terreno pela spline quadrática das 3x3 casas ao redor
	ivec2 own_cell = ivec2(floor(p));
	vec4 weights;
	vec2 relief;
	terrain_weights(p, weights, relief);
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
	float hills = relief.x;
	float mountains = relief.y;
	float land_total = max(grass + forest + cerrado + hills + mountains, 0.0001);
	float forest_share = forest / land_total;
	float cerrado_share = cerrado / max(grass + cerrado, 0.0001);
	float c = smoothstep(0.15, 0.85, cerrado_share + n_land * 0.35);
	vec4 open_land = mix(tile_color(grass_tex, p, 0.31), tile_color(cerrado_tex, p, -0.47), c);
	// Colinas: o chão verde delas, iluminado pela inclinação dos morrinhos
	// (diferença finita da altura, em casas)
	float eps = 0.02;
	float hill_area = smoothstep(0.25, 0.6, hills + n_land * 0.4);
	if (hill_area > 0.0) {
		float h0 = hill_height(p);
		vec2 hill_slope = vec2(hill_height(p + vec2(eps, 0.0)) - h0, hill_height(p + vec2(0.0, eps)) - h0) / eps;
		vec4 hill_color = tile_color(hill_tex, p, 0.12);
		hill_color.rgb *= mix(1.0, slope_light(hill_slope * hill_relief), 0.7) * 0.93;
		open_land = mix(open_land, hill_color, hill_area);
	}
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
	// Montanhas: rocha com as cristas iluminadas de um lado e na sombra do
	// outro; o chão em volta fica um pouco sombreado (pé da montanha)
	float rock = 0.0;
	if (mountains > 0.02) {
		float m0 = mountain_height(p);
		rock = smoothstep(0.0, 0.06, m0);
		land_color.rgb *= 1.0 - 0.2 * smoothstep(0.1, 0.45, mountains) * (1.0 - rock);
		if (rock > 0.0) {
			vec2 slope = vec2(mountain_height(p + vec2(eps, 0.0)) - m0, mountain_height(p + vec2(0.0, eps)) - m0) / eps;
			vec3 rock_color = tile_color(mountain_tex, p, 0.9).rgb;
			float light = slope_light(slope * mountain_relief);
			rock_color *= (0.42 + 0.66 * light) * (0.9 + 0.2 * m0);
			land_color.rgb = mix(land_color.rgb, rock_color, rock);
		}
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
	vec3 land_side = mix(sand_color.rgb, land_color.rgb, max(max(soft_step(0.57, land), trees), rock));
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
