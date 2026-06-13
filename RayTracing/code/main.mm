#include <Metal/Metal.h>
#include <Foundation/Foundation.h>
#include <limits.h>
#include <mach-o/dyld.h>

#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>

#define internal static
#define local_persist static
#define global_variable static

typedef int8_t i8;
typedef int16_t i16;
typedef int32_t i32;
typedef int64_t i64;
typedef i32 b32;

#define true 1
#define false 0

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;

typedef float f32;
typedef double f64;

struct state
{
    char ExecutablePath[PATH_MAX];
    char *ExecutableDirectory;
};

internal void
GetExecutablePath(state *State)
{
    char *ExecutablePath = State->ExecutablePath;
    char *ExecutableDirectory = State->ExecutableDirectory;
    u32 Size = sizeof(State->ExecutablePath);
    
    _NSGetExecutablePath(ExecutablePath, &Size);
    ExecutableDirectory = ExecutablePath;
    
    for(char *Scan = ExecutableDirectory; *Scan; ++Scan)
    {
        if(*Scan == '/')
        {
            ExecutableDirectory = Scan + 1;
        }
    }
    
    State->ExecutableDirectory = ExecutableDirectory;
    
}

internal void
BuildFullPath(state *State, char *Filename, size_t Size, char *FullPath)
{
    char *ExecutablePath = State->ExecutablePath;
    char *ExecutableDirectory = State->ExecutableDirectory;
    for(int Index = 0; Index < ExecutableDirectory - ExecutablePath; ++Index)
    {
        *FullPath++ = *ExecutablePath++;
    }
    for(int Index = 0; Index < Size - 1; ++Index)
    {
        *FullPath++ = *Filename++;
    }
    *FullPath = 0;
}

i32 main(i32 argc, const char *argv[]) {
    
    @autoreleasepool
    {
        state State;
        GetExecutablePath(&State);
        
        NSString *NSExecutablePath = [NSString stringWithUTF8String:State.ExecutablePath];
        NSString *NSExecutableDirectory = [NSString stringWithUTF8String:State.ExecutableDirectory];
        
        NSLog(@"%@\n", NSExecutablePath);
        NSLog(@"%@\n", NSExecutableDirectory);
                
        char MetalLibraryFilename[] = "shaders.metallib";
        char MetalLibraryFullPath[PATH_MAX];
        
        BuildFullPath(&State, MetalLibraryFilename, sizeof(MetalLibraryFilename), MetalLibraryFullPath);
        
        NSString *NSMetalLibraryFullPath = [NSString stringWithUTF8String:MetalLibraryFullPath];
        
        NSLog(@"%@\n", NSMetalLibraryFullPath);
        
        id<MTLDevice> Device = MTLCreateSystemDefaultDevice();
        
        NSError *Errors;
        id<MTLLibrary> MetalLibrary = [Device newLibraryWithFile:NSMetalLibraryFullPath error:&Errors];
        if(!MetalLibrary)
        {
            NSLog(@"Library load failed: %@", Errors);
            return 1;
        }
        id<MTLFunction> VertexFunction = [MetalLibrary newFunctionWithName:@"VertexFunction"];
        id<MTLFunction> FragmentFunction = [MetalLibrary newFunctionWithName:@"FragmentFunction"];
        
        id<MTLCommandQueue> CommandQueue = [Device newCommandQueueWithMaxCommandBufferCount:64];
        
        MTLTextureDescriptor *TextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:3456 height:2234 mipmapped:NO];
        
        id<MTLTexture> Texture = [Device newTextureWithDescriptor:TextureDescriptor];
        
        MTLRenderPassDescriptor *RenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
        
        RenderPassDescriptor.colorAttachments[0].texture = Texture;
        RenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
        RenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        
        id<MTLCommandBuffer> CommandBuffer = [CommandQueue commandBuffer];
        
        id<MTLRenderCommandEncoder> RenderCommandEncoder = [CommandBuffer renderCommandEncoderWithDescriptor:RenderPassDescriptor];
        
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
        
        [RenderCommandEncoder setRenderPipelineState:RenderPipelineState];
        
        float VerticesAndUVs[] = { 
            -1.0f, -1.0f, 0.0f, 1.0f, 
            -1.0f, 1.0f,  0.0f, 0.0f,
            1.0f,  -1.0f, 1.0f, 1.0f, 
            1.0f,  -1.0f, 1.0f, 1.0f,
            -1.0f, 1.0f,  0.0f, 0.0f, 
            1.0f,  1.0f,  1.0f, 0.0f,
        };
        
        id<MTLBuffer> VertexBuffer = [Device newBufferWithBytes:VerticesAndUVs length:sizeof(VerticesAndUVs) options:nil];
        
        [RenderCommandEncoder setVertexBuffer:VertexBuffer offset:0 atIndex:0];
        
        [RenderCommandEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        
        [RenderCommandEncoder endEncoding];
        [CommandBuffer commit];
        
        [CommandBuffer waitUntilCompleted]; //3456 2234
        
        u8 *Pixels = (u8 *)malloc(2234 * (3456 * 4));
        
        [Texture getBytes:Pixels bytesPerRow:3456*4 fromRegion:MTLRegionMake2D(0, 0, 3456, 2234) mipmapLevel:0];
        
        char OutputFilename[] = "output.ppm";
        char OutputFullPath[PATH_MAX];
        
        BuildFullPath(&State, OutputFilename, sizeof(OutputFilename), OutputFullPath);
        
        FILE *File = fopen(OutputFullPath, "wb");
        fprintf(File, "P6\n%d %d\n255\n", 3456, 2234);
        
        for(int Row = 0; Row < 2234; ++Row)
        {
            for(int Col = 0; Col < 3456; ++Col)
            {
                u8 *Pixel = Pixels + (Row * 3456 * 4) + (Col * 4);
                fwrite(Pixel, 1, 3, File);
            }
        }
        
        fclose(File);
        
        printf("ray tracing done\n");
        
    }
}