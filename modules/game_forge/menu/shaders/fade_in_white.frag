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

    // Start: white silhouette only. End: real item/tier.
    col.rgb = mix(vec3(1.0), col.rgb, t);

    gl_FragColor = col;
}
