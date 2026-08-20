uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.01)
        discard;

    // Premultiplied black: keep alpha shape, zero out RGB
    gl_FragColor = vec4(0.0, 0.0, 0.0, col.a);
}
