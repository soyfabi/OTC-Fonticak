# HD minimap animation assets

The client reads optional animation atlases from `data/minimap_hd/animation`.
Generate them from the same world, OTB, DAT and SPR used for the static HD pack.
Copy the actual DAT and SPR into the offline workspace. Matching header
signatures alone do not establish that two asset files have the same contents.

1. Prepare AstraClient's offline export workspace as in its
   `tools/minimap_hd/Export-Pack.ps1`. Use `export_animation.lua` as the
   workspace's `test.lua` and use a new profile name in its `init.lua`
   bootstrap so that `animation-source` does not already exist.
2. Run the AstraClient binary with `--test` in that workspace. Its
   `[HD ANIMATION] OUTPUT:` log line gives the source directory.
3. With Pillow and NumPy installed, generate the animation directory:

   ```text
   python tools/minimap_hd/build_animation.py <animation-source> <Tibia.spr> data/minimap_hd <new-output-directory>
   ```

4. Install the generated directory as `data/minimap_hd/animation`.

The exporter uses the extended 32-bit 8.60 SPR format with 32-pixel RGB sprites.
The generator leaves a chunk static if the pixels it would animate differ
between the reconstructed first frame and the existing HD pack.

## Full global maps

Large maps can be exported one floor at a time from OTBM shards built from
the same source world. The native base should contain `index.base.txt` and
the level 1 PNGs under `floor-0` through `floor-15`. Combine it with the
existing overview and export the animation source with the same assets:

```powershell
python tools/minimap_hd/merge_detail.py <overview> <native-base> <world.otbm> <items.otb> <new-hd-directory>
tools/minimap_hd/Export-AnimationSource.ps1 -AstraPath <AstraClient> -AssetsPath <matching-data-directory> -FloorMapsPath <floor-otbm-directory> -ItemsPath <items.otb> -OutputPath <new-animation-source>
python tools/minimap_hd/build_animation.py <animation-source> <Tibia.spr> <hd-directory> <hd-directory>/animation --jobs 3
```

Put the combined directory in the client's user data folder as
`data/minimap_hd`. Use a client build that supports the larger index.
The v1 animation download belongs to the v1 static map.

**Uninstall** moves a manually installed map or animation pack to a backup
folder under the client's user `data` directory. Uninstalling the manual HD
map also moves the animations inside it.

Windows players can install the static HD pack from **Options → Minimap →
Download Map HD**, then use **Download Animation Map** for the optional
animations. The client saves the verified ZIPs in its user data directory under
`data/minimap_hd/map_hd` and `data/minimap_hd/animations`, respectively, and reads them
directly. Manual installations also work.

When packaging the client, leave out `data/minimap_hd`. Players can download the
packs from Minimap options when they want to use them.

To publish a new pack, ZIP the contents of its directory with `index.txt` and
the PNGs at the archive root. Exclude the animation subdirectory from the static
ZIP. Publish under a new release tag and update the download path, byte count,
SHA-256 and, if needed, the compatible static index header in
`src/client/minimap.cpp`.
