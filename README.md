<p align="center">
  <a href="https://postimg.cc/SJV6WBPv">
    <img src="https://i.postimg.cc/bwfmj89p/fonticak-banner-v2-redemption.png" alt="Fonticak Client" width="100%" />
  </a>
</p>

<div align="center">

# Fonticak Client

**OTClient - Redemption based client adapted for TFS 1.8 Downgrade, focused on performance, modular UI and the custom FontiBot toolkit.**

[![Repository size](https://img.shields.io/github/repo-size/soyfabi/OTC-Fonticak?style=flat-square)](https://github.com/soyfabi/OTC-Fonticak)
[![Issues](https://img.shields.io/github/issues/soyfabi/OTC-Fonticak?style=flat-square)](https://github.com/soyfabi/OTC-Fonticak/issues)
[![Pull Requests](https://img.shields.io/github/issues-pr/soyfabi/OTC-Fonticak?style=flat-square)](https://github.com/soyfabi/OTC-Fonticak/pulls)
[![Commits](https://img.shields.io/github/commit-activity/m/soyfabi/OTC-Fonticak?style=flat-square)](https://github.com/soyfabi/OTC-Fonticak/commits/main)

<br />

![Client](https://img.shields.io/badge/CLIENT-Fonticak-7c3aed?style=for-the-badge)
![Base](https://img.shields.io/badge/BASE-OTClient%20Redemption-2563eb?style=for-the-badge)
![Server](https://img.shields.io/badge/SERVER-TFS%201.8%20Downgrade-f97316?style=for-the-badge)
![Bot](https://img.shields.io/badge/BOT-FontiBot-8b5cf6?style=for-the-badge)
![C++](https://img.shields.io/badge/C++-Client-00599C?style=for-the-badge&logo=cplusplus&logoColor=white)
![Lua](https://img.shields.io/badge/Lua-Modules-2C2D72?style=for-the-badge&logo=lua&logoColor=white)

<br />
<br />

Originally forked from **OTClient - Redemption** and adapted by the Fonticak project.

[Repository](https://github.com/soyfabi/OTC-Fonticak) ·
[Issues](https://github.com/soyfabi/OTC-Fonticak/issues) ·
[Pull Requests](https://github.com/soyfabi/OTC-Fonticak/pulls) ·
[Discord](https://discord.com/invite/GxTm7DyXVe)

</div>

---

## About Fonticak Client

**Fonticak Client** is a custom OTClient project based on **OTClient - Redemption** and adapted for **TFS 1.8 Downgrade**.

The project focuses on:

- High-performance rendering.
- Modular Lua / OTUI interface systems.
- Multiple graphics backends.
- A fully custom **FontiBot** toolkit.
- Flexible window placement and persistent layouts.
- Multi-platform builds.
- Client-side security and configuration improvements.

> [!IMPORTANT]
> Fonticak Client is based on **OTClient - Redemption**.
>
> The project is adapted for **TFS 1.8 Downgrade** and extends the client with its own systems, interface changes and FontiBot modules.

---

## Highlights

| Area | Description |
|---|---|
| Base | **OTClient - Redemption** |
| Server Target | **TFS 1.8 Downgrade** |
| Graphics | DirectX 9, DirectX 11, OpenGL 2.0 and experimental Vulkan |
| Performance | Optimized rendering pipeline focused on smooth long-session performance |
| UI | Modular Lua + `.otui` interface |
| Bot | Custom **FontiBot** suite |
| Window System | Draggable mini-windows with persistent placement |
| Platforms | Windows, Linux, Android and experimental WebAssembly |
| Security | Machine UUID, encrypted password storage, hardened ZIP handling and hash-based config sharing |

---

## FontiBot Suite

Fonticak includes a custom **FontiBot** toolkit integrated directly into the client.

Available systems include:

- **CaveBot**
- **Healer**
- **Trainer**
- **Supplier**
- **Walker**
- Draggable **Bot Hub** tabs

The bot interface follows the same modular approach as the rest of the client, making it easier to extend or customize individual systems.

---

## Graphics Backends

Fonticak supports multiple rendering backends:

```text
DirectX 9
DirectX 11
OpenGL 2.0
Vulkan (experimental)
```

The graphics backend can be selected in `config.ini`.

Example:

```ini
[graphics]
renderBackend = gl
maxAtlasSize = 8192
```

Available backend values include:

```text
gl
vulkan
dx9
dx11
```

> [!NOTE]
> Vulkan support is experimental.

---

## Modular Interface

The interface is built around Lua modules and `.otui` layouts.

Each panel can be maintained independently, allowing themes and UI systems to be changed without tightly coupling them to the C++ core.

Main UI-related locations:

```text
modules/
data/
```

Fonticak also supports free placement of mini-windows. Window positions can persist between sessions.

---

## Fonts

The client can load TTF fonts directly with stroke support.

Format:

```text
path|size|stroke-width|stroke-color
```

Font configuration is available in:

```text
config.ini
```

---

## Customization

### Change Client Title

Edit:

```text
modules/startup/startup.lua
```

Default:

```lua
g_window.setTitle(g_app.getName())
```

You can replace it with a static title:

```lua
g_window.setTitle("My Online Server")
```

---

## Build

### Windows

### Requirements

Install:

1. **Visual Studio 2022 or 2026** with C++ support.
2. **CMake 3.16+**.
3. **vcpkg**.

The project includes a `vcpkg.json` manifest for dependency resolution.

### Clone

```bash
git clone https://github.com/soyfabi/OTC-Fonticak.git
cd OTC-Fonticak
```

### Configure

```bash
cmake --preset=default
```

### Build Release

```bash
cmake --build --preset=default-release
```

The resulting executable is generated as:

```text
otclient_dx_x64.exe
```

or the equivalent executable for the selected graphics backend.

---

## Multi-Platform

The project includes support for multiple platforms:

- **Windows**
- **Linux / Ubuntu**
- **Android / NDK**
- **WebAssembly** — experimental

Platform-specific files and build environments may require additional dependencies beyond the basic Windows setup.

---

## Project Layout

| Path | Purpose |
|---|---|
| `src/` | C++ core engine, renderer, network and graphics code |
| `modules/` | Lua gameplay and UI modules |
| `data/` | Sprites, fonts, OTUI themes, icons and other assets |
| `tools/` | Helper scripts and bot/config utilities |
| `vc18/` | Auxiliary build and runtime tools |
| `vcpkg_installed/` | Pre-resolved vcpkg dependencies |
| `docs/` | Internal API and module programming documentation |

---

## Security

Fonticak includes several client-side security and configuration features:

- Machine UUID support.
- Encrypted password storage.
- Hardened ZIP handling.
- Hash-based configuration sharing.

These systems are part of the project's custom client layer.

---

## Development

When modifying the project:

1. Keep C++ engine changes isolated from Lua/UI changes when possible.
2. Keep `.otui` layout changes inside the relevant module.
3. Test the selected graphics backend after renderer-related changes.
4. Verify that FontiBot changes do not break unrelated bot modules.
5. Test window layout persistence after UI changes.
6. Build the client in Release mode before submitting major changes.
7. Document new modules or APIs inside `docs/` when appropriate.

---

## Support & Community

For support, bug reports and collaboration:

**[Join the Fonticak Discord](https://discord.com/invite/GxTm7DyXVe)**

You can also use:

- [GitHub Issues](https://github.com/soyfabi/OTC-Fonticak/issues)
- [GitHub Pull Requests](https://github.com/soyfabi/OTC-Fonticak/pulls)
- Repository documentation inside [`docs/`](docs/)

---

## Credits

Fonticak Client builds on work from the OTClient ecosystem.

- **OTClient** — original engine by **edubart** and the OTClient community.
- **OTClient - Redemption** — upstream base used by Fonticak.
- **Fonticak contributors** — `@soyfabi`, `@otaviokta` and community contributors.

---

<div align="center">

## Fonticak Client

**OTClient - Redemption Base · TFS 1.8 Downgrade · FontiBot · Multi-Backend Rendering**

[Repository](https://github.com/soyfabi/OTC-Fonticak) ·
[Discord](https://discord.com/invite/GxTm7DyXVe)

</div>
