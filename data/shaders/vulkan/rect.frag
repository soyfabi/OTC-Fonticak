#version 450

/*
 * Etap 2 renderera Vulkan: fragment teksturowanego prostokata.
 *
 * Nic wiecej niz probkowanie tekstury - caly ciezar etapu 2 lezy po stronie C++ (potok,
 * deskryptory, wgranie tekstury przez bufor posredni). Shader ma byc najprostszy z mozliwych,
 * zeby ewentualny czarny prostokat na ekranie wskazywal na blad w wiazaniach, a nie w GLSL.
 *
 * Tekstura jest w formacie *_SRGB, wiec sprzet sam rozpakowuje sRGB -> liniowe przy probkowaniu,
 * a przy zapisie do zalacznika (rowniez *_SRGB) pakuje z powrotem. Nie ma tu wiec zadnej
 * recznej korekty gamma.
 */

layout(binding = 0) uniform sampler2D texSampler;

layout(location = 0) in vec2 fragUv;
layout(location = 0) out vec4 outColor;

void main()
{
    outColor = texture(texSampler, fragUv);
}
