#version 450

/*
 * Etap 2 renderera Vulkan: wierzcholek teksturowanego prostokata.
 *
 * Prostokat podajemy jako kwadrat jednostkowy [0,1]x[0,1], a o jego polozeniu i rozmiarze
 * na ekranie decyduje transformacja ze STALYCH PRZEKAZYWANYCH (push constants). Dzieki temu
 * bufor wierzcholkow jest wgrywany RAZ i nie trzeba go ruszac przy zmianie rozmiaru okna -
 * wystarczy inna wartosc scale/offset przy nagrywaniu bufora polecen.
 *
 * Push constants, a nie UBO, bo to zaledwie 16 bajtow: nie wymagaja bufora, pamieci,
 * deskryptora ani synchronizacji miedzy klatkami w locie.
 */

layout(location = 0) in vec2 inPos;  // rog kwadratu jednostkowego, [0,1]
layout(location = 1) in vec2 inUv;

layout(push_constant) uniform Transform {
    vec2 scale;   // rozmiar prostokata w NDC (0..2 to caly ekran)
    vec2 offset;  // lewy gorny rog prostokata w NDC
} pc;

layout(location = 0) out vec2 fragUv;

void main()
{
    // NDC Vulkana ma Y skierowany W DOL, tak samo jak wspolrzedne tekstury - wiec pozycja
    // i UV moga isc 1:1, bez odwracania osi Y znanego z OpenGL-a.
    gl_Position = vec4(inPos * pc.scale + pc.offset, 0.0, 1.0);
    fragUv = inUv;
}
