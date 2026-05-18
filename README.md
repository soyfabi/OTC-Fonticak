**🌟Client adapted for TFS 1.8 Downgrade🌟**

**Fork: OTClient - Redemption** is a highly optimized and customized version of **OTClient**, an open-source alternative client for Tibia. It is designed to offer maximum performance, modularity, and easy customization using C++ for the core engine and Lua for the GUI and gameplay mechanics.

---

## 🚀 Key Features

* **Dual Graphics Engine:** Full and optimized support for **DirectX (DX9/DX11)** and **OpenGL 2.0** with custom shaders.
* **High Performance:** Smooth and optimized rendering, ideal for high FPS rates and fluid gameplay.
* **Modular Interface (LUI/OTUI):** Fully customizable GUI using the `.otui` layout design language and `.lua` scripts.
* **Multiplatform:** Compatible with Windows, Linux (Ubuntu), Android, and experimental builds for Web browsers (WebAssembly).
* **Security & Encryption:** Built-in support for machine UUID, encrypted password storage, and secure protocols.

---

## 🛠️ Basic Customization

Here are a few quick configurations to personalize your client:

### 🏷️ Change Client Title
To change the title displayed on the top window bar:
* Open the file `modules/startup/startup.lua`.
* Find the line:
  ```lua
  g_window.setTitle(g_app.getName())
  ```
* You can change it to a static text, for example:
  ```lua
  g_window.setTitle("My Online Server")
  ```
---

## 💻 Compilation

### Prerequisites (Windows)
1. Install **Visual Studio 2022 or 2026** (with C++ support).
2. Install **CMake**.
3. **Vcpkg** dependency manager (the project's `vcpkg.json` automatically manages all required dependencies).

### Quick Steps to Build (CMake)
```bash
# 1. Clone the repository
git clone https://github.com/soyfabi/OTC-Fonticak.git
cd OTC-Fonticak

# 2. Configure the project
cmake --preset=default

# 3. Build
cmake --build --preset=default-release
```

---

## 🤝 Support & Community

* Join our official community on [Discord](https://discord.com/invite/GxTm7DyXVe) to get support, report bugs, or collaborate on development.
* For more guides about the API and module programming, check the `/docs` folder or the auto-generated `meta.lua` file.

