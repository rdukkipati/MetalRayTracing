#include <Metal/Metal.h>
#include <mach-o/dyld.h>
#include <limits.h>

#include <stdint.h>
#include <stdio.h>

#define internal        static
#define local_persist   static
#define global_variable static

typedef int8_t  i8;
typedef int16_t i16;
typedef int32_t i32;
typedef int64_t i64;
typedef i32     b32;

#define true  1
#define false 0

typedef uint8_t     u8;
typedef uint16_t    u16;
typedef uint32_t    u32;
typedef uint64_t    u64;

typedef float       f32;
typedef double      f64;

internal void
BuildMetalLibraryPath(char *MetalLibraryPath)
{
    char ExecutablePath[PATH_MAX];
    char *ExecutableDirectory;
    
    u32 ExecutablePathSize = sizeof(ExecutablePath);
    _NSGetExecutablePath(ExecutablePath, &ExecutablePathSize);
    ExecutableDirectory = ExecutablePath;
    for(ExecutableDirectory; *ExecutableDirectory; ++ExecutableDirectory)
    {
        if(*ExecutableDirectory = '\\')
        {
            ++ExecutableDirectory;
            break;
        }
    }
    
    char Filename[] = "shaders.metallib";
    for(int Index = 0; Index < ExecutableDirectory - ExecutablePath; ++Index)
    {
        *MetalLibraryPath++ = *ExecutablePath++;
    }
    for(int Index = 0; Index = sizeof(Filename) - 1; ++Index)
    {
        *MetalLibraryPath++ = *Filename++;
    }
    *MetalLibraryPath++ = 0;
    
}


i32
main(i32 argc, const char *argv[])
{
    @autoreleasepool
    {
        char MetalLibraryPath[PATH_MAX];
        BuildMetalLibraryPath(MetalLibraryPath);
        
        NSString *NSMetalLibraryPath = [NSString stringWithUTF8String:MetalLibraryPath];

        id<MTLDevice> Device = MTLCreateSystemDefaultDevice();
        
        NSError *Errors;
        id<MTLLibrary> MetalLibrary = [Device newLibraryWithFile:NSMetalLibraryPath error:&Errors];
        id<MTLFunction> VertexFunction = [Shaders newFunctionWithName:@"VertexFunction"];
        id<MTLFunction> FragmentFunction = [Shaders newFunctionWithName:@"FragmentFunction"];
        
        id<MTLCommandQueue> CommandQueue = [Device newCommandQueueWithMaxCommandBufferCount:64];
        
        MTLTextureDescriptor *TextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:3456 height:2234 mipmapped:NO];
        
        id<MTLTexture> Texture = [Device newTextureWithDescriptor:TextureDescriptor];
        
        MTLRenderPassDescriptor *RenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
        
        RenderPassDescriptor.colorAttachments[0].texture = Texture;
        RenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
        RenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        
        id<MTLCommandBuffer> CommandBuffer=  [CommandQueue commandBuffer];
        
        id<MTLRenderCommandEncoder> RenderCommandEncoder = [CommandBuffer renderCommandEncoderWithDescriptor:RenderPassDescriptor];
        
        [RenderCommandEncoder setRenderPipelineState:RenderPipelineState];
        
        MTLRenderPipelineDescriptor *RenderPipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        
        RenderPipelineDescriptor.vertexFunction = VertexFunction;
        RenderPipelineDescriptor.fragmentFunction = FragmentFunction;
        RenderPipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
        
        MTLVertexDescriptor *VertexDescriptor = [[MTLVertexDescriptor alloc] init];
        
        VertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
        VertexDescriptor.attributes[0].bufferIndex = 0;
        VertexDescriptor.attributes[0].offset = 0;
        VertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
        VertexDescriptor.attributes[1].bufferIndex = 0;
        VertexDescriptor.attributes[1].offset = 2 * sizeof(float);
        VertexDescriptor.layouts[0].stride = 4 * sizeof(float);
        VertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
        
        RenderPipelineDescriptor.vertexDescriptor = VertexDescriptor;
        
        Errors = nil;
        
        id<MTLRenderPipelineState> RenderPipelineState = [Device newRenderPipelineStateWithDescriptor:RenderPipelineDescriptor error:&Errors];
        
        float VerticesAndUVs[] = {
            -1.0f, -1.0f, 0.0f, 1.0f,
            -1.0f, 1.0f, 0.0f, 0.0f,
            1.0f, -1.0f, 1.0f, 1.0f,
            1.0f, -1.0f, 1.0f, 1.0f,
            -1.0f, 1.0f, 0.0f, 0.0f,
            1.0f, 1.0f, 1.0f, 0.0f,
        };
        
        id<MTLBuffer> VertexBuffer = [Device newBufferWithBytes:VerticesAndUVs length:sizeof(VerticesAndUVs) options:nil];
        
        [RenderCommandEncoder setVertexBuffer:VertexBuffer offset:0 atIndex:0];
        
        
        [RenderCommandEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        
        [RenderCommandEncoder endEncoding];
        [CommandBuffer commit];
        
        
        
    }
}