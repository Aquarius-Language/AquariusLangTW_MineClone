@echo off
rem Build AquaCraft: portable .wasm, static website and (optionally) a Windows EXE.
rem Usage: tools\build.cmd [web] [exe]   (set AQ to the aqua.exe you want to use)
setlocal
cd /d "%~dp0.."
if "%AQ%"=="" set AQ=aqua
if not exist build mkdir build
"%AQ%" build main.aqua src\noise.aqua src\blocks.aqua src\worldgen.aqua src\world.aqua src\mesher.aqua src\player.aqua src\camera.aqua src\renderer.aqua src\ui.aqua src\audio.aqua src\items.aqua src\inventory.aqua src\crafting.aqua src\containers.aqua src\drops.aqua src\mobs.aqua src\invui.aqua src\lang.aqua src\glyphs.aqua src\debug.aqua --root . --assets shaders --assets assets --entry main.aqua -o build\aquacraft.wasm || exit /b 1
if /i "%1"=="web" "%AQ%" build build\aquacraft.wasm --target web --entry main.aqua -o build\web || exit /b 1
if /i "%2"=="exe" "%AQ%" build build\aquacraft.wasm --target windows --entry main.aqua -o build\AquaCraft.exe || exit /b 1
echo Build complete.
