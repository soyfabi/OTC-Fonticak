#version 450

/*
 * Etap 3 renderera Vulkan: wierzcholek WSADU kafli (sprite batch).
 *
 * Roznica wobec rect.vert z etapu 2 jest fundamentalna, a nie kosmetyczna:
 *
 * 1. Etap 2 mial JEDEN prostokat opisany stalymi przekazywanymi (push constants) - kazdy kolejny
 *    prostokat wymagalby osobnego wywolania rysowania. Tutaj CALA geometria (pozycja, UV, warstwa,
 *    kolor) siedzi w buforze wierzcholkow, wiec N kafli idzie jednym vkCmdDrawIndexed.
 *
 * 2. Wspolrzedne podajemy w PIKSELACH ekranu, a nie w NDC. Reszta klienta mysli w pikselach,
 *    a przeliczenie to jedno mnozenie w shaderze; dzieki temu procesor nie musi znac rozmiaru
 *    okna, gdy sklada liste kafli.
 *
 * 3. Numer warstwy atlasu jedzie w wierzcholku. To jest sedno etapu 3: kafle z ROZNYCH warstw
 *    jednej tablicy obrazow probkuja ten sam deskryptor, wiec dolozenie warstwy nie dokłada
 *    ani wiazania, ani wywolania rysowania.
 */

layout(location = 0) in vec2 inPos;    // pozycja rogu kafla w PIKSELACH ekranu
layout(location = 1) in vec2 inUv;     // wspolrzedna w atlasie, znormalizowana [0,1]
layout(location = 2) in float inLayer; // warstwa tablicy obrazow (male liczby calkowite)
layout(location = 3) in vec4 inColor;  // R8G8B8A8_UNORM rozpakowany przez sprzet do [0,1]

layout(push_constant) uniform Screen {
    vec2 invHalfSize;  // (2/szerokosc, 2/wysokosc) - piksele -> NDC jednym mnozeniem
} pc;

layout(location = 0) out vec2 fragUv;
layout(location = 1) flat out float fragLayer;
layout(location = 2) out vec4 fragColor;

void main()
{
    // NDC Vulkana ma Y w dol i zakres [-1,1], a piksele licza sie od lewego gornego rogu -
    // wystarczy wiec skala i przesuniecie o -1, bez odwracania osi Y znanego z OpenGL-a.
    gl_Position = vec4(inPos * pc.invHalfSize - 1.0, 0.0, 1.0);

    fragUv = inUv;
    // flat, bo indeks warstwy MUSI dojsc do fragmentu bez interpolacji: wszystkie cztery
    // wierzcholki kafla maja ta sama wartosc, ale interpolacja barycentryczna nie gwarantuje
    // dokladnie tej samej liczby zmiennoprzecinkowej, a sampler2DArray zaokragla ja do warstwy.
    fragLayer = inLayer;
    fragColor = inColor;
}
