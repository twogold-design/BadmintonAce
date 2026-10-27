shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 jersey_color : source_color = vec4(.66,.79,.39,1.0);
uniform float neck_height = 1.5205;
uniform float sleeve = .337;
varying vec2 garment;
void vertex() { garment = UV2; }
void fragment() {
    float x=abs(garment.x), y=garment.y;
    float collar=neck_height-.018+.070*smoothstep(.025,.110,x);
    float aa=max(fwidth(y),.0005);
    float neck_trim=smoothstep(collar-.007-aa,collar-.007+aa,y);
    float cuff_trim=smoothstep(sleeve-.008-aa,sleeve-.008+aa,x);
    ALBEDO=mix(jersey_color.rgb,vec3(.85,.88,.82),max(neck_trim,cuff_trim)*.8);
    ROUGHNESS=.9;
}
