# VIctory over Sunshine and Moonlight

This report covers a Linux VIctory host with Windows and Steam Deck Moonlight clients. The host ran one RTX 3060 12 GB for rendering and a second RTX 3060 12 GB for NVENC. The streaming display was X11 at 1280×800. The title package and all generated caches stayed on the host.

## Compatibility changes

- Added a Wine-compatible path for creating an empty Direct3D 12 pipeline library. The loader can reuse the persisted library after restart.
- Added an optional frame interval override. The launcher selects an uncapped interval and the loader verifies and applies three frame-rate and simulation-timer hooks in memory. A build whose expected bytes differ refuses to run with the override. The title files are mounted read-only.
- Added a setting to build host pipelines on demand while continuing to reuse the saved library. One warm restart queued more than 1,500 background builds, which delayed the world load.
- Enabled the fork's texture worker and its kernel-read fallback when the title is remapping memory. A missing page leaves its texture pending until a later refresh.
- Switched the host from UMU-Proton 11.0-2e to GE-Proton11-14 in a separate prefix. Kept the original title profile and a separate pipeline cache for the new Proton build.
- Selected the RTX 3060 attached to the X11 display by Vulkan device UUID. Sunshine used NVENC on the second card. VIctory creates one rendering device for the game.
- Configured an on-demand app in an existing boot-enabled Sunshine service. Verified keyboard input on Windows and virtual DualSense enumeration on Steam Deck.

## Build and launch on Linux

The [source patch](../contrib/moonlight/runtime.patch) was built against `93db653ada3ee0b94b2334243d7af81c3d12f27a` of [fxceless/victory-fork](https://github.com/fxceless/victory-fork), which is the source of the verified stream. It also applies to `52ac4ec0f8a03f103c146e60228e53612759d435`, a later candidate built in a separate checkout.

Install Rust, LLVM-MinGW, UMU and GE-Proton11-14. Use a dedicated prefix with a signed Microsoft `d3dcompiler_47.dll` available to Wine. The packaged Wine compiler in the tested prefix failed on VIctory's indirect-draw helper. Use your own supported Series X title package.

~~~bash
git clone https://github.com/fxceless/victory-fork.git victory-runtime
cd victory-runtime
git checkout 93db653ada3ee0b94b2334243d7af81c3d12f27a
git apply --check /path/to/VIctory/contrib/moonlight/runtime.patch
git apply /path/to/VIctory/contrib/moonlight/runtime.patch

rustup target add x86_64-pc-windows-gnullvm
export PATH="/path/to/llvm-mingw/bin:$PATH"
export CARGO_TARGET_X86_64_PC_WINDOWS_GNULLVM_RUSTFLAGS='-C target-feature=+crt-static -C link-arg=-Wl,--stack,16777216'
cargo build --locked --release -p victory --features diagnostics \
    --target x86_64-pc-windows-gnullvm
~~~

Run the [launcher](../contrib/moonlight/launch-proton.sh) from the same desktop session Sunshine captures. Set `DXVK_FILTER_DEVICE_UUID` to that display's adapter UUID on a multi-GPU NVIDIA host. Use the hex UUID without the `GPU-` prefix or hyphens. Add the command to Sunshine's Applications list under the same account. Pair each Moonlight client to that Sunshine instance.

~~~bash
export PROTONPATH=/path/to/GE-Proton11-14
export WINEPREFIX="$HOME/.local/share/victory/proton-ge"

bash /path/to/VIctory/contrib/moonlight/launch-proton.sh \
    /path/to/title.exe \
    "$PWD/target/x86_64-pc-windows-gnullvm/release/victory.exe" \
    --console series-x
~~~

To warm the translation cache, run `victory translate /path/to/shaders.rpf --warm all --jobs 12` using the same runtime, prefix, and shader settings. The host test found 25,985 programs and translated 25,669 new entries in about five minutes. Keep the shader and pipeline caches on local storage. A refresh of the Linux launcher keeps personal saves in their original profile.

The frame interval is in milliseconds. `0` removes the limit, `16.667` requests 60 FPS and `33.333` requests 30 FPS. `VICTORY_LIBRARY_EARLY=1` re-enables anticipatory pipeline builds for comparison.

## VItoriaBr on Proton

VItoriaBr offers a lower internal display mode and graphics-buffer optimizations. Its author reported 4–6 FPS on the standard Windows RTX 5060 Ti preset and 22 FPS on a separate experimental build. [VItoriaBr status and tuning notes](https://github.com/uiliannn/VItoriaBr/tree/1361e190b7f46df996f00ea1b540ecf66785127f)

To reproduce the Linux build, use the same toolchain and build command above. Use a separate VIctory cache because this checkout changes the shader translator.

~~~bash
git clone https://github.com/uiliannn/VItoriaBr.git vitoriabr-runtime
cd vitoriabr-runtime
git checkout 1361e190b7f46df996f00ea1b540ecf66785127f
git apply --exclude=crates/victory-gpu/src/pipeline/library.rs \
    /path/to/VIctory/contrib/moonlight/runtime.patch
git apply /path/to/VIctory/contrib/moonlight/vitoriabr-pipeline-library.patch
~~~

The local test used the same GE-Proton and X11 display. It enabled these options before calling the launcher from a copy of the title profile.

~~~bash
export VICTORY_DISPLAY_MODE=1920x1080
export VICTORY_TABLE_BUFFERS=1
export VICTORY_INDIRECT_GATHER=1
export VICTORY_CARD_BUFFERS_MB=1024
export VICTORY_TEXTURE_BUDGET_MB=8192
~~~

### Instance pool capacity

The Linux test reached the same pool exhaustion across both runtimes. The optional diagnostic patch gives three related pools more slots on the known retail build. It uses the title's normal allocator and checks the image before changing any call site. The patch adapts the sizing changes from the upstream diagnostic branch. [Pool exhaustion report](https://github.com/Marvisak/VIctory/issues/698) · [Source branch at the tested revision](https://github.com/lhnizdo/VIctory/tree/124fade01f50c4a2e587c760014479c8e474e0ba)

Apply the patch after the two VItoriaBr compatibility patches, rebuild with diagnostics, and set `VICTORY_POOL_SCALE=2` for a test with a separate profile.

~~~bash
git apply /path/to/VIctory/contrib/moonlight/vitoriabr-pool-scale.patch
export VICTORY_POOL_SCALE=2
~~~

The first boot with this setting applied 632 call-site changes. At initialization, the three affected allocations requested 45,000 slots instead of 22,500, 100,000 instead of 50,000, and 131,056 instead of 98,000. The last allocation reached the cap for 17-bit slot indices.

### Combined NVIDIA and VItoriaBr build

The [combined patch](../contrib/moonlight/combined-runtime.patch) applies to [`cd9355206de35baeab822ce9bb2bbac7e8354eb6`](https://github.com/fxceless/victory-fork/commit/cd9355206de35baeab822ce9bb2bbac7e8354eb6) of `fxceless/victory-fork`. That revision incorporates the NVIDIA rendering changes and the frame-rate override derived from the 7900 XTX fork. The patch carries the Wine pipeline-library fix and optional larger instance pools forward. It also integrates VItoriaBr's [placed 3D texture and alias fix](https://github.com/uiliannn/VItoriaBr/commit/b6e61ab6311a6eed6c4c138a5cf6fd88339acba7) and [cache/profile separation check](https://github.com/uiliannn/VItoriaBr/commit/30d9ba1a643e82da2a48fa4ce706eec9fcc6780a).

Apply this patch by itself on the specified revision and use the same Linux build command. Use a separate cache and a copy of the title profile for the first boot.

~~~bash
git checkout cd9355206de35baeab822ce9bb2bbac7e8354eb6
git apply --check /path/to/VIctory/contrib/moonlight/combined-runtime.patch
git apply /path/to/VIctory/contrib/moonlight/combined-runtime.patch

export VICTORY_POOL_SCALE=2 VICTORY_RENDER_1080P=1
export VICTORY_BVH_BUILDER=0 VICTORY_DLSS=0 VICTORY_FRAMEGEN=0
export VICTORY_DYNAMIC_WAIT=1 VICTORY_THIN=1 VICTORY_RELAY=2 VICTORY_RELAY_COPY=1
export VICTORY_SOFT_VIEWS=copies VICTORY_PRELUDE_UPLOADS=1 VICTORY_AMBIENT=0.8
export VICTORY_CARD_BUFFERS_MB=1024 VICTORY_TEXTURE_BUDGET_MB=8192
~~~

The title reported a 1920×1080 internal scene and 2560×1440 SDR output. The Sunshine capture display continued to run at 1280×800. The 16 `victory-core` tests passed. A focused `victory-gpu` test under Proton checked that a placed 3D unordered view uses a host texture and that a shader view reads the alias. The port still dropped draws and ran at single-digit frame rates in the intro.

### NVIDIA lighting follow-up

The first ray-tracing launch from the existing Moonlight tile stopped presenting during the first 3D load and then reported a null write at `+0x23cf683`. VIctory-NVIDIA identifies that exact location as the title's 30-second watchdog and traces its own reproduction to repeated searches for upload address space. The [follow-up patch](../contrib/moonlight/nvidia-lighting.patch) brings over the reservation and retry changes, along with a placed-view fix for unstable descriptor keys. [Watchdog and arena fix](https://github.com/trustno1-coder/VIctory-NVIDIA/pull/88) · [Early upload reservation](https://github.com/trustno1-coder/VIctory-NVIDIA/commit/e69e39c55b92f71a40ea3eadaa3439678df4e721) · [Placed-view fix](https://github.com/trustno1-coder/VIctory-NVIDIA/pull/58)

Apply the follow-up after `combined-runtime.patch` and rebuild with the same command. The trial uses its own profile and cache. To reproduce the ray-tracing path, set both switches before launching.

~~~bash
git apply --check /path/to/VIctory/contrib/moonlight/nvidia-lighting.patch
git apply /path/to/VIctory/contrib/moonlight/nvidia-lighting.patch
export VICTORY_BVH_BUILDER=1 VICTORY_WATER_LIGHT=1
~~~

The follow-up release build compiled for the Proton target. Proton tests passed for upload-space reservation, placed descriptor identity, unused view words and the 3D texture alias. The private 1080p boot activated all 53 ray-tracing structure-builder pipelines. It continued rendering for 3 minutes 41 seconds until stopped to compare render sizes. The earlier watchdog was absent in that run. A streamed visual comparison is pending.

### DLSS on the RTX 3060

The `upscaler-check --device` command completed three DLSS Super Resolution evaluations under GE-Proton on the rendering GPU using the signed NVIDIA Streamline 2.14.16 package. The SDK is supplied separately. The DLSS Quality game boot selected a 1706×960 internal scene at 2560×1440 SDR output, and the runtime logged DLSS replacing the game's FidelityFX dispatch. The test uses the existing instance-pool and Proton fixes, with ray tracing and frame generation off. [NVIDIA Streamline 2.14.16](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.14.16)

### Proton write-watch follow-up

The [write-watch patch](../contrib/moonlight/proton-write-watch.patch) applies after `nvidia-lighting.patch`. It adapts the upstream reservation-aware batching and worker-path changes. The Wine fallback for querying reserved pages is limited to the missing information-class error. The comparison used `VICTORY_AHEAD_GAP_KB=256`. Two focused Proton tests covered observing writes after an earlier copy and recognizing when an unmapped block is mapped again. [NVIDIA pull request #207](https://github.com/trustno1-coder/VIctory-NVIDIA/pull/207)

| Private DLSS Quality run | Intervals with at least 1,000 draws/frame | Median FPS | Median preparation | Median queries about memory holes |
| --- | ---: | ---: | ---: | ---: |
| Control | 35 | 2.4 | 263 ms | 7,563 |
| Write-watch patch | 25 | 2.7 | 124 ms | 78 |

The two starts used different cache warmth and progressed through different shots. The measured drop in memory queries is specific to these runs. Playable performance and the patched build's Deck stream remain unverified.

### GE-Proton memory views

The [wineserver patch](../contrib/moonlight/ge-proton-wineserver-views.patch) adds a red-black tree for memory-view lookups. It keeps the existing list for enumeration and preserves GE-Proton's host page alignment check. The patch adapts an upstream Wine change and a Proton backport. [Wine commit](https://github.com/wine-mirror/wine/commit/3217449b1f719c8f7a73a6de768df536495ddcbf) · [FiveNine's Proton patch](https://github.com/FiveNine/victory-proton/blob/030b1415980d6ebb986152626c4b1cb161ca35e3/linux/wineserver-views-rbtree.patch)

Use the GE-Proton11-14 release's Wine and Wine Staging pins with its Wine preparation steps in the release build script. The Valve Wine base alone generated server protocol 931 and the installed GE client rejected it. GE's release patch stack generated protocol 938. Apply this patch to the prepared Wine tree with `git apply`, then run `./autogen.sh`. The test configured a separate Debian 12 build directory with `--enable-win64 --without-mingw` and ran `make -j8 server/wineserver`. The resulting binary went into a copy of GE-Proton11-14 at `files/bin/wineserver`. The test used its own Wine prefix. [GE-Proton11-14 release](https://github.com/GloriousEggroll/proton-ge-custom/releases/tag/GE-Proton11-14) · [Release preparation script](https://github.com/GloriousEggroll/proton-ge-custom/blob/GE-Proton11-14/patches/protonprep-valve-staging.sh)

The original DLSS Quality renderer and Proton write-watch build were used in both runs. The updated wineserver passed the three-evaluation DLSS device check, and its process was confirmed during the title run. The benchmark ended by timer after 3 minutes 55 seconds. The host logged zero NVIDIA Xid errors during the run.

| Proton wineserver | Intervals with at least 1,000 draws/frame | Median FPS | Median frame time | Median preparation |
| --- | ---: | ---: | ---: | ---: |
| GE-Proton11-14 stock | 25 | 2.7 | 374 ms | 124 ms |
| GE-Proton11-14 with memory-view patch | 30 | 2.6 | 384 ms | 113 ms |

The intro shots and cache warmth varied across the runs. The measured median frame rates were within 0.1 FPS. Deck playback of this build is unverified.

### Launchers

[VILauncher](https://github.com/dazacode/vilauncher) builds and launches selected projects on Windows. [SixLauncher](https://github.com/SixLauncher/launcher) also supports Proton on Linux and accepts a locally built runtime. On the test host, its `v0.1.139` release generated a dry-run command for the combined executable and existing GE-Proton11-14. The boot results below use the UMU launcher with the rendering GPU selected explicitly.

## Boot and stream results

Measurements below use the host's frame counter. The video stream has its own frame rate.

| Test | Result |
| --- | --- |
| Initial Windows Moonlight test | A temporary Sunshine endpoint streamed the Linux title to Windows at 1280×800 and about 30 FPS over H.264. Keyboard input advanced the initial screen. |
| Existing pipeline cache, UMU-Proton 11.0-2e | Two startup runs stopped around frame 18 with the texture worker enabled and disabled. |
| UMU-Proton with NVIDIA raw access chains disabled | Wine recorded an access violation in NVIDIA's Vulkan shader compiler. The process still exited while making a compute pipeline. |
| Fresh host pipeline cache with warmed shaders | Reached world loading, then reproduced the compiler fault when the same compute pipeline became necessary. |
| Uncapped UMU-Proton and one pipeline skipped | Verified all three frame-rate hooks. Menus exceeded 60 FPS. The load reached a later pipeline and the compiler faulted again. |
| GE-Proton11-14 | Made both previously failing compute pipelines and reached the opening title card. Wine's bundled D3DCompiler rejected the indirect-draw helper. |
| GE-Proton with Microsoft D3DCompiler | The helper ran and the intro issued thousands of indirect draws. A restart doing anticipatory pipeline builds was especially slow. |
| GE-Proton with on-demand pipelines and texture worker | Reached the intro again with the shader cache and saved pipelines reused. |
| Steam Deck on the permanent Sunshine endpoint | Connected over HEVC at 1280×800 and enumerated a virtual DualSense. GPU monitoring confirmed separate rendering and encoding cards. The port later reported a title-side null write after about eight minutes in the intro. |
| Windows Moonlight 6.2.0 on the permanent endpoint, `93db653` | Paired, launched the same app, and streamed over HEVC. With the texture memory fallback enabled, parts of loading reached 55–90 FPS and the 3D intro became visible. The intro generally ran below 1 FPS with missing lighting and materials. After about 15 minutes the title hit breakpoint `0x80000003` and its crash report showed `INSTANCE_LIST` at 45,000/45,000. |
| Windows Moonlight cold-cache restart, `52ac4ec` | The Moonlight app list relaunched the same tile after the update. Sunshine connected over HEVC, the three frame hooks applied, and the host rebuilt its pipeline cache. Parts of loading exceeded 60 FPS. The intro still ran below 1 FPS. The title stopped after 17 minutes with the same breakpoint and `INSTANCE_LIST` at 45,000/45,000. |
| Local VItoriaBr Proton run, `1361e190` | The title accepted a reported display mode of 1920×1080 and reached the 3D intro. The intro remained below 1 FPS. A concurrent workload occupied about 8.6 GB on the rendering GPU for much of this run. After it released that memory, the game still stopped at `0x80000003` with the same 45,000/45,000 instance pool. |
| VItoriaBr with twice the instance-pool capacity | Reached the intro and ran for 12 minutes before a deliberate stop. The earlier breakpoint was absent in that run. Median intro performance was 0.3 FPS over 54 intervals with at least 1,000 draws per frame. |
| VItoriaBr with larger pools and the submission preset | Ran through the 15-minute test without the earlier breakpoint. Median performance was 0.4 FPS over 92 intervals with at least 1,000 draws per frame. |
| Newer NVIDIA base with the Proton and pool changes | Booted from a fresh runtime cache and reached the 3D intro. The run was stopped after about four minutes to test the VItoriaBr texture changes. The median was 1.6 FPS over 26 intervals with at least 1,000 draws per frame. |
| Combined build with VItoriaBr texture changes | Reused a copy of the previous run's shader and pipeline cache and reached the 3D intro. The median at the first checkpoint was 2.0 FPS over 22 intervals with at least 1,000 draws per frame. The warm cache and scene timing can both affect this comparison. |
| Windows laptop and Steam Deck streaming the combined build | Both clients connected to the same Sunshine display over HEVC at 1280×800. Sunshine created a virtual DualSense for the Deck, and the tester confirmed that the Deck accepted input. The rendering card was near its 12 GB VRAM limit, the second card encoded both streams, and recent 3D intervals were around 2–3 FPS. The user reported poor image quality. During those intervals the renderer intentionally skipped about 624 indirect operations per frame for ray tracing with the structure builder disabled. |
| Windows laptop ray-tracing test through the Moonlight tile | Connected over HEVC with ray tracing and the water-light pass enabled. Presentation stopped during the first 3D load. About 35 seconds after the last frame report, the title logged `0xc0000005` at `+0x23cf683`. The previous launcher was restored for new starts. |
| NVIDIA upload-memory fix, 1080p with ray tracing | Passed the earlier watchdog point and continued drawing until a deliberate stop after 3 minutes 41 seconds. Median was 0.8 FPS across 23 intervals with at least 1,000 draws per frame. |
| NVIDIA upload-memory fix, 720p with FidelityFX | The title accepted a 1280×720 internal scene and 2560×1440 output. It then reported integer divide-by-zero `0xc0000094` at `+0x28f03e8` before sustained 3D rendering. |
| NVIDIA fork DLSS Quality with selected copy settings | The runtime took over the game's upscaling. Early 3D scenes ran in the low single digits. The test recorded thousands of queries about unmapped or reserved memory per frame. |

The combined host run passed the earlier instance-pool breakpoint time. After ten minutes of the test, the existing experimental Sunshine entry was pointed at the combined build for the next new launch. The ongoing clients were watching the private test on the same capture display.

For log intervals with at least 200 draws per frame, the median frame time was 3,551 ms on `93db653` (91 intervals) and 2,905 ms on `52ac4ec` (93 intervals). The shots and draw counts varied between runs. Copy preparation and read-back remained the largest measured costs.

The newer Proton build cleared the observed shader compiler failure. The `93db653` stream reached rendered scenes, with copying and read-back still taking most of each frame. The later instance-pool failure matches the breakpoint and exhausted pool in another report. Playable frame rate, stable gameplay and a native Windows host run remain unverified. [VIctory issue #698](https://github.com/Marvisak/VIctory/issues/698)

## Sources

VIctory's [NVIDIA compiler crash report](https://github.com/Marvisak/VIctory/issues/144) documents the same family of world-load failures. The empty-library handling follows [VIctory PR #1722](https://github.com/Marvisak/VIctory/pull/1722). The frame override adapts the [frame interval change](https://github.com/avatarmanz/VIctory-7900XTX/commit/49cb83b41bbab3212c82f7cd9f0e3102c9fc3492) and [simulation timing follow-up](https://github.com/avatarmanz/VIctory-7900XTX/commit/08b88b8266c2d0294d483d29b15534872ebc7da9) from the GPL-3.0 VIctory-7900XTX fork.
