// Névoa de guerra (FogOfWar): a textura tem 1 pixel por casa; vermelho = casa
// nunca vista, verde = casa fora da visão agora. Com o filtro linear, os
// valores se misturam entre as casas; o smoothstep transforma a mistura numa
// borda suave e arredondada, que acompanha o contorno da área vista.
shader_type canvas_item;

// Escurecimento das casas já exploradas que não estão à vista agora.
uniform float fog_dim = 0.5;
uniform vec4 fog_color : source_color = vec4(0.03, 0.035, 0.05, 1.0);

void fragment() {
	vec4 f = texture(TEXTURE, UV);
	float unexplored = smoothstep(0.3, 0.7, f.r);
	float hidden = smoothstep(0.3, 0.7, f.g);
	COLOR = vec4(fog_color.rgb, max(unexplored, hidden * fog_dim));
}
