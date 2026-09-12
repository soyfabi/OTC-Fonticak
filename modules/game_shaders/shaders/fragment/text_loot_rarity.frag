// Fragment Shader (GLSL 1.20)
// Crisp loot rarity outline tinted to the item color (blue / purple)
uniform sampler2D u_Tex0;
uniform vec4 u_Color;
varying vec2 v_TexCoord;

void main() {
    vec4 glyph = texture2D(u_Tex0, v_TexCoord);
    vec2 texelSize = vec2(1.0 / 512.0, 1.0 / 512.0);

    if (glyph.a > 0.1) {
        vec3 core = min(glyph.rgb * u_Color.rgb * 1.06, vec3(1.0));
        gl_FragColor = vec4(core, glyph.a);
        return;
    }

    float outline = 0.0;
    float samples = 0.0;

    for (float angle = 0.0; angle < 6.28318; angle += 0.785398) {
        vec2 offset = vec2(cos(angle), sin(angle)) * 0.75;
        outline += texture2D(u_Tex0, v_TexCoord + offset * texelSize).a * 1.35;
        samples += 1.35;
        offset = vec2(cos(angle), sin(angle)) * 1.05;
        outline += texture2D(u_Tex0, v_TexCoord + offset * texelSize).a * 0.85;
        samples += 0.85;
    }

    outline = min(outline / samples, 1.0);

    if (outline > 0.06) {
        vec3 outlineColor = u_Color.rgb * 0.42;
        float alpha = smoothstep(0.06, 0.42, outline) * 0.9;
        gl_FragColor = vec4(outlineColor, alpha);
    } else {
        discard;
    }
}
