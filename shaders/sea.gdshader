shader_type spatial;
render_mode cull_disabled, depth_draw_never;

// The sea at its best: see sea_waves.gdshaderinc.
#define SEA_HIGH
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

#include "sea_waves.gdshaderinc"
