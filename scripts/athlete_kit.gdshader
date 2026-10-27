shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D skin_texture : source_color, filter_linear_mipmap;
uniform vec4 jersey_color : source_color = vec4(.66,.79,.39,1.0);
uniform float waist = .954;
varying vec2 garment;
float band(float value, float low, float high, float aa) {
    return smoothstep(low-aa,low+aa,value)*(1.0-smoothstep(high-aa,high+aa,value));
}
void vertex() { garment=UV2; }
void fragment() {
    vec3 skin=texture(skin_texture,UV).rgb;
    float x=abs(garment.x), y=garment.y;
    float aa=max(fwidth(y),.0005);
    float shorts=band(y,.665,waist+.035,aa);
    float socks=1.0-smoothstep(.178-aa,.178+aa,y);
    // The T-shirt is a separate skinned garment. Exposed collar/arms stay skin.
    ALBEDO=skin;
    vec3 pants=vec3(.024,.047,.065);
    float stripe=band(x,.170,.181,aa);
    pants=mix(pants,jersey_color.rgb,stripe*.75);
    ALBEDO=mix(ALBEDO,pants,shorts);
    ALBEDO=mix(ALBEDO,vec3(.82,.85,.82),socks);
    ROUGHNESS=.82;
}
