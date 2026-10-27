shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D skin_texture : source_color, filter_linear_mipmap;
uniform vec4 jersey_color : source_color = vec4(.66,.79,.39,1.0);
uniform float waist = .954;
uniform float neck_height = 1.5205;
uniform float sleeve = .342;
varying vec2 garment;
float band(float value, float low, float high, float aa) {
    return smoothstep(low-aa,low+aa,value)*(1.0-smoothstep(high-aa,high+aa,value));
}
void vertex() { garment=UV2; }
void fragment() {
    vec3 skin=texture(skin_texture,UV).rgb;
    float x=abs(garment.x), y=garment.y;
    float aa=max(fwidth(y),.0005);
    float collar=neck_height-.018+.070*smoothstep(.025,.11,x);
    float shirt=band(y,waist,collar,aa)*(1.0-smoothstep(sleeve-aa,sleeve+aa,x));
    float shorts=band(y,.665,waist+.035,aa);
    float socks=1.0-smoothstep(.178-aa,.178+aa,y);
    vec3 cloth=jersey_color.rgb;
    float trim=max(band(y,collar-.008,collar,aa),band(x,sleeve-.012,sleeve,aa));
    float side_panel=smoothstep(.143,.150,x)*(1.0-smoothstep(1.29,1.32,y));
    cloth=mix(cloth,cloth*.75,side_panel*.35);
    cloth=mix(cloth,vec3(.86,.89,.84),trim*.8);
    ALBEDO=mix(skin,cloth,shirt);
    vec3 pants=vec3(.024,.047,.065);
    float stripe=band(x,.170,.181,aa);
    pants=mix(pants,jersey_color.rgb,stripe*.75);
    ALBEDO=mix(ALBEDO,pants,shorts);
    ALBEDO=mix(ALBEDO,vec3(.82,.85,.82),socks);
    ROUGHNESS=.82;
}
