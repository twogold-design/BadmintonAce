shader_type spatial;
render_mode diffuse_burley;
uniform vec4 floor_color : source_color = vec4(.157,.451,.388,1.0);
varying vec3 local_position;
float noise_at(vec2 p) {
    vec2 cell=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    float a=fract(sin(dot(cell,vec2(127.1,311.7)))*43758.5453);
    float b=fract(sin(dot(cell+vec2(1,0),vec2(127.1,311.7)))*43758.5453);
    float c=fract(sin(dot(cell+vec2(0,1),vec2(127.1,311.7)))*43758.5453);
    float d=fract(sin(dot(cell+vec2(1,1),vec2(127.1,311.7)))*43758.5453);
    return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
void vertex() { local_position=VERTEX; }
void fragment() {
    float grain=noise_at(local_position.xz*95.0)*.004;
    float wear=noise_at(local_position.xz*2.2)*.006;
    ALBEDO=floor_color.rgb+grain+wear;
    ROUGHNESS=.96;
}
