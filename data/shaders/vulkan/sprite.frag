#version 450

/*
 * Etap 3 renderera Vulkan: fragment kafla z atlasu.
 *
 * sampler2DArray, a nie sampler2D: atlas to JEDEN obraz z wieloma warstwami, wiec trzecia
 * wspolrzedna probkowania wybiera warstwe. To jedyny powod, dla ktorego 57 tys. faz animacji
 * moze dzielic jeden deskryptor - przy osobnym sampler2D na warstwe trzeba by albo przepinac
 * deskryptory miedzy wywolaniami rysowania, albo siegac po descriptor indexing
 * (VK_EXT_descriptor_indexing - poza rdzeniem Vulkan 1.1, ktory deklarujemy w VkContext).
 *
 * Mnozenie przez kolor wierzcholka jest tu z gory, bo klient i tak potrzebuje przyciemniania
 * (swiatlo, wyszarzenie, miganie) - a robienie tego pozniej wymagaloby zmiany formatu
 * wierzcholka, czyli przebudowy potoku.
 */

layout(binding = 0) uniform sampler2DArray atlasSampler;

layout(location = 0) in vec2 fragUv;
layout(location = 1) flat in float fragLayer;
layout(location = 2) in vec4 fragColor;

layout(location = 0) out vec4 outColor;

void main()
{
    // Atlas jest w formacie *_SRGB, wiec sprzet sam rozpakowuje sRGB -> liniowe przy probkowaniu,
    // a przy zapisie do zalacznika (rowniez *_SRGB) pakuje z powrotem. Zadnej recznej gammy.
    outColor = texture(atlasSampler, vec3(fragUv, fragLayer)) * fragColor;
}
