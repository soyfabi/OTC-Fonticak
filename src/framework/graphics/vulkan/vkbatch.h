/*
 * Stage 3 of the Vulkan renderer: BATCHED sprite drawing (sprite batch).
 *
 * The second half of stage 3 - the atlas by itself gains nothing if every tile still goes in its
 * own draw call. This class assembles N tiles into ONE vertex buffer and submits them with ONE
 * vkCmdDrawIndexed, because they all sample the same array image (the layer number rides
 * in the vertex, not in the descriptor).
 *
 * The difference versus stage 2's VkRectRenderer is qualitative:
 *   stage 2: 1 rectangle = 1 pipeline + 1 bind + 1 draw, geometry fixed in card memory,
 *           position via push constants (so every additional rectangle = another draw);
 *   stage 3: N tiles = 1 pipeline + 1 bind + 1 draw, geometry built every frame
 *           in host-visible memory that is PERSISTENTLY mapped (no map/unmap per frame).
 *
 * The vertex buffer is REPLICATED per frame in flight. Without that the CPU would overwrite
 * vertices the card is just reading from the previous frame - a bug that shows up as flicker
 * and only on some drivers, making it very hard to find later.
 *
 * The object's lifetime is hooked into VkContext exactly like VkRectRenderer: init() receives
 * a ready device and render pass, record() appends commands ALREADY INSIDE the render pass,
 * and an init() failure is not a critical error (the context keeps running).
 */

#pragma once
 // The whole Vulkan renderer is Win32-only for now (window surface), and the vulkan-headers
 // dependency is windows-only in vcpkg.json. Outside Windows this file compiles to nothing,
 // so it can sit unconditionally on the source list in CMakeLists.
#ifdef WIN32


#include "vkatlas.h"
#include "vkloader.h"

#include <string>
#include <vector>

// One tile to draw this frame. Deliberately POD and deliberately pointer-free - the tile list
// is built and discarded every frame, so it must be cheap to copy and cache-friendly.
struct VkSpriteQuad
{
    float x{ 0.0f };          // top-left corner in screen PIXELS
    float y{ 0.0f };
    float w{ 0.0f };
    float h{ 0.0f };
    float uvMin[2]{ 0.0f, 0.0f };
    float uvMax[2]{ 0.0f, 0.0f };
    float layer{ 0.0f };
    uint8_t color[4]{ 255, 255, 255, 255 };
};

// Must match the sprite.vert inputs (locations 0..3) byte for byte. Public since stage 4:
// the feeder writes vertices directly, so it must know the layout.
struct VkSpriteVertex
{
    float pos[2];
    float uv[2];
    float layer;
    uint8_t color[4];
};

class VkSpriteBatch
{
public:
    // framesInFlight must equal MAX_FRAMES_IN_FLIGHT from VkContext - that many independent
    // vertex buffers will be created. atlasSize is the atlas layer side in pixels;
    // 0 = the stage 3 test size (512, forces the multi-layer path).
    bool init(VkPhysicalDevice physicalDevice, VkDevice device, VkRenderPass renderPass,
              VkQueue graphicsQueue, VkCommandPool commandPool, uint32_t framesInFlight,
              uint32_t atlasSize = 0);

    // Clears this frame's tile list. The vector's capacity stays, so after a few frames
    // building the list stops allocating at all.
    void begin();

    // Adds a tile. The slot comes from the atlas; color is RGBA (0xRRGGBBAA) multiplied in the shader.
    void drawSprite(float x, float y, float w, float h, const VkAtlasSlot& slot, uint32_t rgba = 0xFFFFFFFFu);

    // --- Stage 4: external feeding with raw geometry (from the real drawing queue) ---
    // beginExternal opens an externally-fed frame: it clears the vertices and segments and
    // sets a flag thanks to which record() will NOT build the test scene. The flag expires in
    // record(), so no feeding in the next frame = back to the test scene (you can see the feeder died).
    void beginExternal(const VkExtent2D& extent);

    // Sets the scissor for SUBSEQUENT vertices. Equal to the current one = no-op; different =
    // closes the current segment. One segment is one vkCmdDraw - the fewer scissor changes,
    // the fewer calls.
    void setScissor(const VkRect2D& scissor);

    // Sets the pipeline for SUBSEQUENT vertices: 0 = regular alpha blending (NORMAL),
    // 1 = MULTIPLY (tinting outfit layers). Works like setScissor - closes the segment.
    void setPipeline(uint8_t pipelineIndex);

    // Reserves count consecutive vertices (triangles: count % 3 == 0) and returns a pointer to
    // fill in. nullptr = the frame limit is exhausted, the primitive is lost (the caller logs it).
    // The pointer is valid ONLY until the next call (the vector may relocate).
    VkSpriteVertex* allocVertices(uint32_t count);

    // Access to the ALREADY written vertices of the current frame - the feeder retroactively
    // transforms the contents of temporary GL framebuffers with them (positions known only at "release").
    uint32_t externalVertexCount() const { return static_cast<uint32_t>(m_vertices.size()); }
    VkSpriteVertex* externalVertexData() { return m_vertices.data(); }

    // Cuts the rectangle [x0,y0)-(x1,y1) out of the geometry written since fromVertex (the
    // equivalent of GL's "punch a hole in the FBO": writing alpha=0 without blending). Triangles
    // fully inside disappear, intersecting ones are clipped; segments are recomputed.
    void punchRect(uint32_t fromVertex, float x0, float y0, float x1, float y1);

    // Abandons the external frame (e.g. the atlas failed to upload pixels) - record() falls back
    // to the test scene.
    void abortExternal();

    // Appends commands to an ALREADY STARTED render pass. frameIndex is the frame-in-flight number
    // (VkContext::m_currentFrame) - it selects a vertex buffer the card is no longer looking at.
    void record(VkCommandBuffer cmd, const VkExtent2D& extent, uint32_t frameIndex);

    void terminate();

    bool isReady() const { return m_ready; }
    const std::string& getError() const { return m_error; }

    VkTextureAtlas& getAtlas() { return m_atlas; }

private:
    bool fail(const std::string& reason);
    bool loadFunctions();

    bool createShaderModules();
    bool createIndexBuffer();
    bool createVertexBuffers(uint32_t framesInFlight);
    bool createDescriptors();
    bool createPipeline();

    // Writes the CURRENT atlas view into the descriptor. Called when the atlas changed generation
    // (growth by a layer recreates the view, and the old handle ceases to exist).
    bool syncDescriptor();

    // Stage 3 - visual test: loads a dozen-plus different PNGs into the atlas.
    // Since stage 4 this is a fallback - it only runs when nobody feeds the batch externally.
    bool loadTestImages();
    void buildTestScene(const VkExtent2D& extent);

    // Stage 4: records the frame from geometry delivered via beginExternal()/allocVertices().
    void recordExternal(VkCommandBuffer cmd, const VkExtent2D& extent, uint32_t frameIndex);

    bool createBuffer(VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags properties,
                      VkBuffer& buffer, VkDeviceMemory& memory);
    uint32_t findMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties) const;
    VkShaderModule loadShader(const std::string& path);

    // Capacity of one vertex buffer. 8192 tiles is 786 KB per frame in flight -
    // cheap considering it covers the whole visible map with headroom. Excess is TRUNCATED
    // (with a warning), not reallocated mid-frame.
    static constexpr uint32_t kMaxQuads = 8192;

    // External-mode vertex limit (stage 4): 262144 vertices = ~87.3k triangles
    // = ~43.6k rectangles - a dozen-plus times a busy game frame, so that truncating the tail
    // of the list (i.e. the UI, since the pools go from the map to the interface) practically
    // never happens. 262144 * 24 B = 6 MB per frame in flight. Excess is truncated, not reallocated.
    static constexpr uint32_t kMaxVertices = 262144;

    // External-mode segment: a contiguous range of vertices drawn with one scissor
    // and one pipeline.
    struct Segment
    {
        uint32_t first{ 0 };
        uint32_t count{ 0 };
        VkRect2D scissor{};
        uint8_t pipeline{ 0 };
    };

    // --- borrowed from VkContext (we do not destroy these) ---
    VkPhysicalDevice m_physicalDevice{ VK_NULL_HANDLE };
    VkDevice m_device{ VK_NULL_HANDLE };
    VkRenderPass m_renderPass{ VK_NULL_HANDLE };
    VkQueue m_graphicsQueue{ VK_NULL_HANDLE };
    VkCommandPool m_commandPool{ VK_NULL_HANDLE };

    // --- own resources ---
    VkTextureAtlas m_atlas;

    VkShaderModule m_vertShader{ VK_NULL_HANDLE };
    VkShaderModule m_fragShader{ VK_NULL_HANDLE };

    // One buffer per frame in flight; the mapping is PERSISTENT (HOST_COHERENT), so
    // the per-frame write is a plain memcpy, no map/unmap and no synchronization with the driver.
    std::vector<VkBuffer> m_vertexBuffers;
    std::vector<VkDeviceMemory> m_vertexMemories;
    std::vector<void*> m_vertexMapped;

    // The indices are CONSTANT (tile n always uses vertices 4n..4n+3), so the buffer is created
    // once and lives in card memory. 32-bit, because 16-bit would run out at 16383 tiles.
    VkBuffer m_indexBuffer{ VK_NULL_HANDLE };
    VkDeviceMemory m_indexMemory{ VK_NULL_HANDLE };

    VkDescriptorSetLayout m_descriptorLayout{ VK_NULL_HANDLE };
    VkDescriptorPool m_descriptorPool{ VK_NULL_HANDLE };
    VkDescriptorSet m_descriptorSet{ VK_NULL_HANDLE };
    uint32_t m_descriptorGeneration{ UINT32_MAX };  // UINT32_MAX = never written yet

    VkPipelineLayout m_pipelineLayout{ VK_NULL_HANDLE };
    VkPipeline m_pipeline{ VK_NULL_HANDLE };

    // The second pipeline: MULTIPLY blending (GL: glBlendFunc(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA)),
    // used by outfit layer tinting. Differs from m_pipeline ONLY in blend state.
    VkPipeline m_pipelineMultiply{ VK_NULL_HANDLE };

    std::vector<VkSpriteQuad> m_quads;
    std::vector<VkAtlasSlot> m_testSlots;

    // --- external mode (stage 4) ---
    std::vector<VkSpriteVertex> m_vertices;
    std::vector<Segment> m_segments;
    bool m_externallyFed{ false };
    uint64_t m_droppedVertices{ 0 };

    // --- diagnostics ---
    uint64_t m_frameCounter{ 0 };
    uint32_t m_drawCalls{ 0 };

    bool m_ready{ false };
    std::string m_error;

    // --- device functions (local, as in VkContext) ---
    PFN_vkCreateShaderModule m_vkCreateShaderModule{ nullptr };
    PFN_vkDestroyShaderModule m_vkDestroyShaderModule{ nullptr };

    PFN_vkCreateBuffer m_vkCreateBuffer{ nullptr };
    PFN_vkDestroyBuffer m_vkDestroyBuffer{ nullptr };
    PFN_vkGetBufferMemoryRequirements m_vkGetBufferMemoryRequirements{ nullptr };
    PFN_vkBindBufferMemory m_vkBindBufferMemory{ nullptr };

    PFN_vkAllocateMemory m_vkAllocateMemory{ nullptr };
    PFN_vkFreeMemory m_vkFreeMemory{ nullptr };
    PFN_vkMapMemory m_vkMapMemory{ nullptr };
    PFN_vkUnmapMemory m_vkUnmapMemory{ nullptr };

    PFN_vkCreateDescriptorSetLayout m_vkCreateDescriptorSetLayout{ nullptr };
    PFN_vkDestroyDescriptorSetLayout m_vkDestroyDescriptorSetLayout{ nullptr };
    PFN_vkCreateDescriptorPool m_vkCreateDescriptorPool{ nullptr };
    PFN_vkDestroyDescriptorPool m_vkDestroyDescriptorPool{ nullptr };
    PFN_vkAllocateDescriptorSets m_vkAllocateDescriptorSets{ nullptr };
    PFN_vkUpdateDescriptorSets m_vkUpdateDescriptorSets{ nullptr };

    PFN_vkCreatePipelineLayout m_vkCreatePipelineLayout{ nullptr };
    PFN_vkDestroyPipelineLayout m_vkDestroyPipelineLayout{ nullptr };
    PFN_vkCreateGraphicsPipelines m_vkCreateGraphicsPipelines{ nullptr };
    PFN_vkDestroyPipeline m_vkDestroyPipeline{ nullptr };

    PFN_vkCmdBindPipeline m_vkCmdBindPipeline{ nullptr };
    PFN_vkCmdBindVertexBuffers m_vkCmdBindVertexBuffers{ nullptr };
    PFN_vkCmdBindIndexBuffer m_vkCmdBindIndexBuffer{ nullptr };
    PFN_vkCmdBindDescriptorSets m_vkCmdBindDescriptorSets{ nullptr };
    PFN_vkCmdSetViewport m_vkCmdSetViewport{ nullptr };
    PFN_vkCmdSetScissor m_vkCmdSetScissor{ nullptr };
    PFN_vkCmdPushConstants m_vkCmdPushConstants{ nullptr };
    PFN_vkCmdDrawIndexed m_vkCmdDrawIndexed{ nullptr };
    PFN_vkCmdDraw m_vkCmdDraw{ nullptr };
};

#endif // WIN32
