uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

const vec3 FORGE_RED = vec3(161.0 / 255.0, 17.0 / 255.0, 17.0 / 255.0); // #a11111

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.01)
        discard;

    col.rgb = FORGE_RED;
    gl_FragColor = col;
}
