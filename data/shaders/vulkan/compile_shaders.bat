@echo off
rem ---------------------------------------------------------------------------
rem Kompilacja shaderow renderera Vulkan do SPIR-V.
rem
rem Uruchamiamy to RECZNIE, offline, a do repozytorium trafiaja gotowe pliki .spv.
rem Powod: klient NIE MA wkompilowanego kompilatora GLSL i miec go nie powinien -
rem shaderc/glslang to kilka MB kodu, ktory bylby potrzebny wylacznie na naszej maszynie.
rem W czasie dzialania wczytujemy juz tylko gotowy bajtkod.
rem
rem Kompilator: glslang.exe z oficjalnego wydania KhronosGroup/glslang
rem (https://github.com/KhronosGroup/glslang/releases, paczka
rem  glslang-main-windows-x86_64-release.zip). Na tej maszynie NIE MA Vulkan SDK,
rem wiec binarke trzyma sie poza repozytorium - wskaz ja zmienna GLSLANG albo
rem dodaj do PATH.
rem
rem --target-env vulkan1.1 daje SPIR-V 1.3, zgodne z VK_API_VERSION_1_1
rem deklarowanym w VkContext::createInstance.
rem ---------------------------------------------------------------------------

setlocal
if "%GLSLANG%"=="" set GLSLANG=glslang.exe

rem etap 2 - pojedynczy teksturowany prostokat
"%GLSLANG%" -V --target-env vulkan1.1 -S vert -o "%~dp0rect.vert.spv" "%~dp0rect.vert" || exit /b 1
"%GLSLANG%" -V --target-env vulkan1.1 -S frag -o "%~dp0rect.frag.spv" "%~dp0rect.frag" || exit /b 1

rem etap 3 - wsad kafli probkujacych atlas (tablica obrazow)
"%GLSLANG%" -V --target-env vulkan1.1 -S vert -o "%~dp0sprite.vert.spv" "%~dp0sprite.vert" || exit /b 1
"%GLSLANG%" -V --target-env vulkan1.1 -S frag -o "%~dp0sprite.frag.spv" "%~dp0sprite.frag" || exit /b 1

echo SPIR-V gotowe.
endlocal
