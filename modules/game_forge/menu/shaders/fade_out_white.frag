uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.01)
        discard;

    float duration = 0.8;
    float t = clamp(u_Time / duration, 0.0, 1.0);
    float fade = 1.0 - t;

    // FBO blit uses PREMULTIPLIED_ALPHA (GL_ONE, GL_ONE_MINUS_SRC_ALPHA).
    // Non-premultiplied (1,1,1,fade) keeps result clamped to white regardless
    // of fade. Premultiplied white: rgb = vec3(a) so blend = (a,a,a) + bg*(1-a).
    float a = col.a * fade;
    gl_FragColor = vec4(a, a, a, a);
}
