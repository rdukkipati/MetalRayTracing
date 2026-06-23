#include <Foundation/Foundation.h>
#include <Metal/Metal.h>
#include <limits.h>
#include <mach-o/dyld.h>

#include <simd/simd.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

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

global_variable i32 IMAGE_HEIGHT = 2234;
global_variable i32 IMAGE_WIDTH  = 3456;
global_variable i32 SAMPLES_PER_PIXEL = 100;

// Note: look at compiler and linker flags

struct camera
{
    int         ImageWidth;
    int         ImageHeight;
	int SamplesPerPixel;
	float PixelSamplesScale;
    simd_float3 Center;
	simd_float3 PixelDelta_U;
	simd_float3 PixelDelta_V;
    simd_float3 ViewportUpperLeft;
};

internal void
_Camera(camera *Camera)
{
    Camera->ImageHeight  = IMAGE_HEIGHT;
    Camera->ImageWidth   = IMAGE_WIDTH;
	
	Camera->SamplesPerPixel = SAMPLES_PER_PIXEL;
	Camera->PixelSamplesScale = 1.0f / Camera->SamplesPerPixel;

    float FocalLength    = 1.0f;
    float ViewportHeight = 2.0f;
    float ViewportWidth  = ViewportHeight * ((float)IMAGE_WIDTH / IMAGE_HEIGHT);

    Camera->Center       = simd_make_float3(0, 0, 0);

    simd_float3 Viewport_U   = simd_make_float3(ViewportWidth, 0, 0);
    simd_float3 Viewport_V   = simd_make_float3(0, -ViewportHeight, 0);

	Camera->PixelDelta_U = Viewport_U / Camera->ImageWidth;
	Camera->PixelDelta_V = Viewport_V / Camera->ImageHeight;

    Camera->ViewportUpperLeft = Camera->Center -
                                simd_make_float3(0, 0, FocalLength) -
                                (Viewport_U / 2) -
                                (Viewport_V / 2);
}

struct sphere
{
    simd_float1 Radius;
    simd_float3 Center;
};

internal sphere
_Sphere(simd_float1 Radius, simd_float3 Center)
{
    sphere Result;
    Result.Radius = Radius;
    Result.Center = Center;
    return Result;
}

struct state
{
    char  ExecutablePath[PATH_MAX];
    char *ExecutableDirectory;
};

internal void
GetExecutablePath(state *State)
{
    char *ExecutablePath      = State->ExecutablePath;
    char *ExecutableDirectory = State->ExecutableDirectory;
    u32   Size                = sizeof(State->ExecutablePath);

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
    char *ExecutablePath      = State->ExecutablePath;
    char *ExecutableDirectory = State->ExecutableDirectory;
    int   DirectoryLength     = ExecutableDirectory - ExecutablePath;
    for(int Index = 0; Index < DirectoryLength; ++Index)
    {
        *FullPath++ = *ExecutablePath++;
    }
    for(int Index = 0; Index < Size - 1; ++Index)
    {
        *FullPath++ = *Filename++;
    }
    *FullPath = 0;
}

i32
main(i32 argc, const char *argv[])
{

    @autoreleasepool
    {
        state State;
        GetExecutablePath(&State);

        NSString *NSExecutablePath       = [NSString
            stringWithUTF8String:State.ExecutablePath];
        NSString *NSExecutableDirectory  = [NSString
            stringWithUTF8String:State.ExecutableDirectory];

        char      MetalLibraryFilename[] = "shaders.metallib";
        char      MetalLibraryFullPath[PATH_MAX];

        BuildFullPath(&State, MetalLibraryFilename,
                      sizeof(MetalLibraryFilename), MetalLibraryFullPath);

        NSString      *NSString_MetalLibraryFullPath = [NSString
            stringWithUTF8String:MetalLibraryFullPath];
        NSURL         *NSURL_MetalLibraryFullPath    = [NSURL
            fileURLWithPath:NSString_MetalLibraryFullPath];

        id<MTLDevice>  Device       = MTLCreateSystemDefaultDevice();

        NSError       *Errors       = nil;
        id<MTLLibrary> MetalLibrary = [Device
            newLibraryWithURL:NSURL_MetalLibraryFullPath
                        error:&Errors];
        if(!MetalLibrary)
        {
            NSLog(@"Library load failed: %@", Errors);
            return 1;
        }
        id<MTLFunction>          VertexFunction    = [MetalLibrary
            newFunctionWithName:@"VertexFunction"];
        id<MTLFunction>          FragmentFunction  = [MetalLibrary
            newFunctionWithName:@"FragmentFunction"];

        // Note: for game rendering loop, will need to limit # of frames in
        // flight so that command queue does not overflow
        id<MTLCommandQueue>      CommandQueue      = [Device
            newCommandQueueWithMaxCommandBufferCount:64];

        MTLTextureDescriptor    *TextureDescriptor = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                         width:IMAGE_WIDTH
                                        height:IMAGE_HEIGHT
                                     mipmapped:NO];

        // Note: textures expensive to create
        id<MTLTexture>           Texture           = [Device
            newTextureWithDescriptor:TextureDescriptor];

        MTLRenderPassDescriptor *RenderPassDescriptor =
            [MTLRenderPassDescriptor renderPassDescriptor];

        RenderPassDescriptor.colorAttachments[0].texture = Texture;
        RenderPassDescriptor.colorAttachments[0].loadAction =
            MTLLoadActionDontCare;
        RenderPassDescriptor.colorAttachments[0].storeAction =
            MTLStoreActionStore;

        id<MTLCommandBuffer> CommandBuffer = [CommandQueue commandBuffer];

        id<MTLRenderCommandEncoder>  RenderCommandEncoder = [CommandBuffer
            renderCommandEncoderWithDescriptor:RenderPassDescriptor];

        MTLRenderPipelineDescriptor *RenderPipelineDescriptor =
            [[MTLRenderPipelineDescriptor alloc] init];

        RenderPipelineDescriptor.vertexFunction   = VertexFunction;
        RenderPipelineDescriptor.fragmentFunction = FragmentFunction;
        RenderPipelineDescriptor.colorAttachments[0].pixelFormat =
            MTLPixelFormatRGBA8Unorm;

        MTLVertexDescriptor *VertexDescriptor = [[MTLVertexDescriptor alloc]
            init];

        VertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
        VertexDescriptor.attributes[0].bufferIndex = 0;
        VertexDescriptor.attributes[0].offset      = 0;
        VertexDescriptor.attributes[1].format      = MTLVertexFormatFloat2;
        VertexDescriptor.attributes[1].bufferIndex = 0;
        VertexDescriptor.attributes[1].offset      = 2 * sizeof(float);
        VertexDescriptor.layouts[0].stride         = 4 * sizeof(float);
        VertexDescriptor.layouts[0].stepFunction =
            MTLVertexStepFunctionPerVertex;

        RenderPipelineDescriptor.vertexDescriptor      = VertexDescriptor;

        Errors                                         = nil;

        id<MTLRenderPipelineState> RenderPipelineState = [Device
            newRenderPipelineStateWithDescriptor:RenderPipelineDescriptor
                                           error:&Errors];

        [RenderCommandEncoder setRenderPipelineState:RenderPipelineState];

        float VerticesAndUVs[] = {
            -1.0f, -1.0f, 0.0f, 1.0f, -1.0f, 1.0f,  0.0f, 0.0f,
            1.0f,  -1.0f, 1.0f, 1.0f, 1.0f,  -1.0f, 1.0f, 1.0f,
            -1.0f, 1.0f,  0.0f, 0.0f, 1.0f,  1.0f,  1.0f, 0.0f,
        };

        // Note: Buffers expensive to create
        id<MTLBuffer> VertexBuffer = [Device
            newBufferWithBytes:VerticesAndUVs
                        length:sizeof(VerticesAndUVs)
                       options:0];

        [RenderCommandEncoder setVertexBuffer:VertexBuffer offset:0 atIndex:0];

        sphere Spheres[10];
        Spheres[0] = _Sphere(0.5f, simd_make_float3(0, 0, -1));
        Spheres[1] = _Sphere(100.0f, simd_make_float3(0, -100.5f, -1));

        // Note: Buffers expensive to create
        id<MTLBuffer> SphereBuffer = [Device newBufferWithBytes:Spheres
                                                         length:sizeof(Spheres)
                                                        options:0];

        [RenderCommandEncoder setFragmentBuffer:SphereBuffer
                                         offset:0
                                        atIndex:1];

        u32           SphereCount       = 2;

        // Note: Buffers expensive to create
        id<MTLBuffer> SphereCountBuffer = [Device
            newBufferWithBytes:&SphereCount
                        length:sizeof(SphereCount)
                       options:0];

        [RenderCommandEncoder setFragmentBuffer:SphereCountBuffer
                                         offset:0
                                        atIndex:2];

        camera Camera = {};
        _Camera(&Camera);
        id<MTLBuffer> CameraBuffer = [Device newBufferWithBytes:&Camera
                                                         length:sizeof(Camera)
                                                        options:0];
        [RenderCommandEncoder setFragmentBuffer:CameraBuffer
                                         offset:0
                                        atIndex:3];

        [RenderCommandEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                                 vertexStart:0
                                 vertexCount:6];

        [RenderCommandEncoder endEncoding];
        [CommandBuffer commit];

        [CommandBuffer waitUntilCompleted]; // IMAGE_WIDTH IMAGE_HEIGHT

        u8 *Pixels = (u8 *)malloc(IMAGE_HEIGHT * (IMAGE_WIDTH * 4));

        [Texture getBytes:Pixels
              bytesPerRow:IMAGE_WIDTH * 4
               fromRegion:MTLRegionMake2D(0, 0, IMAGE_WIDTH, IMAGE_HEIGHT)
              mipmapLevel:0];

        char OutputFilename[] = "output.ppm";
        char OutputFullPath[PATH_MAX];

        BuildFullPath(&State, OutputFilename, sizeof(OutputFilename),
                      OutputFullPath);

        FILE *File = fopen(OutputFullPath, "wb");
        fprintf(File, "P6\n%d %d\n255\n", IMAGE_WIDTH, IMAGE_HEIGHT);

        for(int Row = 0; Row < IMAGE_HEIGHT; ++Row)
        {
            for(int Col = 0; Col < IMAGE_WIDTH; ++Col)
            {
                u8 *Pixel = Pixels + (Row * IMAGE_WIDTH * 4) + (Col * 4);
                fwrite(Pixel, 1, 3, File);
            }
        }

        fclose(File);

        printf("ray tracing done\n");
    }
}