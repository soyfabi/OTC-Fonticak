# Fonticak Client

OTCv8 based client adapted for **TFS 1.8 Downgrade**, focused on performance, modular UI and a fully custom **FontiBot** toolkit.

Originally forked from **OTClient - Redemption** (a high-performance OTClient customization by the community).

---

## ✨ Key Features

- 🎨 **Dual Graphics Engine:** Full support for **DirectX 9 / 11**, **OpenGL 2.0**, and an experimental **Vulkan** renderer.
- 🚀 **High Performance:** Optimized rendering pipeline tuned for smooth FPS even on long sessions.
- 🧩 **Modular Interface (OTUI):** Every UI panel is a Lua module + `.otui` layout, fully themable.
- 🤖 **FontiBot Suite:** Built-in **CaveBot**, **Healer**, **Trainer**, **Supplier**, **Walker** and draggable Bot Hub tabs.
- 🪟 **Free Window Placement:** Drag any mini-window anywhere; layout persists between sessions.
- 📦 **Multi-Platform:** Windows, Linux (Ubuntu), Android (NDK), and experimental WebAssembly builds.
- 🔐 **Security:** Machine UUID, encrypted password storage, hardened ZIP handling and hash-based config sharing.

---

## 🛠️ Customization

### 🏷️ Change Client Title
Edit `modules/startup/startup.lua` and replace:
```lua
g_window.setTitle(g_app.getName())
```
with a static title, for example:
```lua
g_window.setTitle("My Online Server")
```

### ⚙️ Graphics Backend
Switch render backend in `config.ini`:
```ini
[graphics]
renderBackend = gl     ; or "vulkan" / "dx9" / "dx11"
maxAtlasSize = 8192
```

### 🎨 Fonts
The client loads TTF fonts directly with stroke support. Format: `path|size|stroke-width|stroke-color`. See `config.ini` under `[font]`.

---

## 💻 Building (Windows)

### Prerequisites
1. **Visual Studio 2022 or 2026** with C++ support.
2. **CMake 3.16+**.
3. **[vcpkg](https://github.com/microsoft/vcpkg)** — the project's `vcpkg.json` resolves all required dependencies automatically.

### Quick Build
```bash
git clone https://github.com/soyfabi/OTC-Fonticak.git
cd OTC-Fonticak

cmake --preset=default
cmake --build --preset=default-release
```

The resulting binary will be placed at `otclient_dx_x64.exe` (or the equivalent for your chosen backend).

---

## 📂 Project Layout

| Folder | Purpose |
|--------|---------|
| `src/` | C++ core engine (renderer, network, graphics) |
| `modules/` | Lua gameplay + UI modules (one folder per feature) |
| `data/` | Assets (sprites, fonts, OTUI themes, icons) |
| `tools/` | Helper scripts (bot config API, etc.) |
| `vc18/` | Auxiliary build/runtime tools |
| `vcpkg_installed/` | Pre-resolved vcpkg dependencies |
| `docs/` | Internal API and module programming notes |

---

## 🤝 Support & Community

- 💬 Join the official community on [Discord](https://discord.com/invite/GxTm7DyXVe) for support, bug reports and collaboration.
- 📘 API reference and module programming guides: see `/docs` or the auto-generated `meta.lua`.
- 🐛 Found a bug? Open an issue on GitHub.

---

## 📜 Credits

- **OTClient** — Original engine by **edubart** and the OTClient community ([otclient.ovh](https://otclient.ovh)).
- **OTClient - Redemption** — Base customisation this fork builds upon.
- **Contributors:** @soyfabi, @otaviokta, and the community.
