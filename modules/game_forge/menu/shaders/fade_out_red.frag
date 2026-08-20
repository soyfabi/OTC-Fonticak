uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

const vec3 FORGE_RED = vec3(161.0 / 255.0, 17.0 / 255.0, 17.0 / 255.0); // #a11111

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.01)
        discard;

    float duration = 0.8;
    float t = clamp(u_Time / duration, 0.0, 1.0);
    float fade = 1.0 - t;

    // Premultiplied #a11111 fade out (same approach as fade_out_white.frag)
    float a = col.a * fade;
    gl_FragColor = vec4(FORGE_RED * a, a);
}
