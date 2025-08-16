shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    vec4 col = texture(SCREEN_TEXTURE, SCREEN_UV);
    float gray = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    COLOR = vec4(vec3(gray), col.a);
}
