shader_type spatial;
render_mode cull_back;

uniform sampler2D pose_texture : filter_nearest, repeat_disable;
uniform float crowd_time = 0.0;
uniform float excitement : hint_range(0.0, 1.0) = 0.0;
varying vec3 fan_color;
varying vec2 garment;

vec3 display_color(vec3 linear_color) {
 // Compatibility renders in sRGB; the offline samples are stored in linear RGB.
 if (OUTPUT_IS_SRGB) {
  return mix(12.92 * linear_color, 1.055 * pow(max(linear_color,vec3(0.0)),vec3(1.0/2.4))-0.055,step(vec3(0.0031308),linear_color));
 }
 return linear_color;
}

vec3 sample_pose(int frame, int lane, int vertex_id) {
 ivec2 size = textureSize(pose_texture, 0);
 int rows = size.y / 12;
 return texelFetch(pose_texture, ivec2(vertex_id % size.x, vertex_id / size.x + (frame * 2 + lane) * rows), 0).xyz;
}

void vertex() {
 float id = floor(INSTANCE_CUSTOM.a + 0.5);
 float phase = id * 2.39996;
 float variation = fract(id * 0.618034);
 int vertex_id = int(UV2.x + 0.5);
 // Most spectators watch quietly. Each score produces a staggered short reaction.
 float age = (1.0 - excitement) * 2.5;
 float delay = variation * 0.38;
 float reaction = smoothstep(delay, delay + 0.42, age) * (1.0 - smoothstep(1.65, 2.5, age));
 reaction *= step(0.12, fract(id * 0.754877 + 0.3));
 float stand = mod(id, 7.0) < 0.5 ? 1.0 : 0.0;
 // Keep shoulders, elbows, wrists and fingers in baked anatomical poses.
 float clap = 0.5 - 0.5 * cos(max(age - delay, 0.0) * (11.5 + variation * 2.0));
 float watch = 0.5 + 0.5 * sin(crowd_time * (0.55 + variation * 0.15) + phase);
 int open_frame = stand > 0.5 ? 4 : 2;
 for (int lane = 0; lane < 2; lane++) {
  vec3 resting = mix(sample_pose(0,lane,vertex_id),sample_pose(1,lane,vertex_id),watch);
  vec3 applause = mix(sample_pose(open_frame,lane,vertex_id),sample_pose(open_frame+1,lane,vertex_id),clap);
  vec3 result = mix(resting,applause,reaction);
  if (lane == 0) { VERTEX = result; } else { NORMAL = normalize(result); }
 }
 fan_color = mix(display_color(COLOR.rgb), INSTANCE_CUSTOM.rgb, UV2.y);
 garment = UV;
}

void fragment() {
 ALBEDO = fan_color;
 if (garment.y > 0.5) {
  float aa = max(fwidth(garment.x),0.001);
  float shorts = smoothstep(0.665-aa,0.665+aa,garment.x) * (1.0-smoothstep(1.015-aa,1.015+aa,garment.x));
  ALBEDO = mix(ALBEDO,vec3(0.10,0.13,0.16),shorts);
  ALBEDO = mix(ALBEDO,vec3(0.72,0.74,0.72),1.0-smoothstep(0.178-aa,0.178+aa,garment.x));
 }
 ROUGHNESS = 0.9;
}
