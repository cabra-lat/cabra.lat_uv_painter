// vertex_weights_shader.gdshader

shader_type spatial;
render_mode unshaded, depth_test_disabled;

uniform sampler2D weight_texture;
uniform int current_bone_index;

// Blender-style weight paint color ramp
vec3 weight_to_color(float w) {
    vec3 color;
    if (w < 0.25) {
        // Blue → Cyan
        color = mix(vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), w * 4.0);
    } else if (w < 0.5) {
        // Cyan → Green
        color = mix(vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), (w - 0.25) * 4.0);
    } else if (w < 0.75) {
        // Green → Yellow
        color = mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0), (w - 0.5) * 4.0);
    } else {
        // Yellow → Red
        color = mix(vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), (w - 0.75) * 4.0);
    }
    return color;
}

void fragment() {
    float weight = texture(weight_texture, UV).r;
    ALBEDO = weight_to_color(weight);
}
