#include <Foundation/Foundation.h>
#include <Metal/Metal.h>

#include <limits.h>
#include <mach-o/dyld.h>

#include <simd/simd.h>

#include <math.h>
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

typedef simd_float3 vec3;
typedef simd_float3 point3;
typedef simd_float3 color3;

#define PI 3.14159265359f

using simd::cross;
using simd::length;
using simd::length_squared;
using simd::normalize;

struct rng
{
    u64 State;
    u64 SequenceConstant;
};

internal u32
Random_u32(rng *RNG)
{
    u64 OldState   = RNG->State;
    RNG->State     = OldState * 6364136223846793005ULL + RNG->SequenceConstant;
    u32 Xorshifted = ((OldState >> 18u) ^ OldState) >> 27u;
    u32 Rot        = OldState >> 59u;
    return (Xorshifted >> Rot) | (Xorshifted << ((-Rot) & 31));
}

internal void
InitializeRNG(rng *RNG, u64 InitialState, u64 StreamID)
{
    RNG->State            = 0U;
    RNG->SequenceConstant = (StreamID << 1u) | 1u;
    Random_u32(RNG);
    RNG->State += InitialState;
    Random_u32(RNG);
}

internal f32
Random_f32(rng *RNG)
{
    u32 Value  = Random_u32(RNG);
    u32 Bits   = (Value >> 9) | 0x3f800000;
    f32 Result = *(f32 *)&Bits;
    return Result - 1.0f;
}

internal f32
Random_f32_InRange(f32 Min, f32 Max, rng *RNG)
{
    return Min + (Max - Min) * Random_f32(RNG);
}

internal color3
_Color3(f32 X, f32 Y, f32 Z)
{
    return simd_make_float3(X, Y, Z);
}

internal point3
_Point3(f32 X, f32 Y, f32 Z)
{
    return simd_make_float3(X, Y, Z);
}

internal vec3
_Vec3(f32 X, f32 Y, f32 Z)
{
    return simd_make_float3(X, Y, Z);
}

internal color3
RandomColor(rng *RNG)
{
    return _Color3(Random_f32(RNG), Random_f32(RNG), Random_f32(RNG));
}

internal color3
RandomColor_InRange(f32 Min, f32 Max, rng *RNG)
{
    return _Color3(Random_f32_InRange(Min, Max, RNG),
                   Random_f32_InRange(Min, Max, RNG),
                   Random_f32_InRange(Min, Max, RNG));
}

global_variable i32    IMAGE_HEIGHT           = 2234;
global_variable i32    IMAGE_WIDTH            = 3456;
global_variable i32    SAMPLES_PER_PIXEL      = 20;
global_variable i32    MAX_RAY_BOUNCES        = 10;
global_variable f32    VERTICAL_FIELD_OF_VIEW = 20.0f;
global_variable point3 LOOK_FROM              = _Point3(13, 2, 3);
global_variable point3 LOOK_AT                = _Point3(0, 0, 0);
global_variable vec3   WORLD_UP               = _Vec3(0, 1, 0);
global_variable f32    DEFOCUS_ANGLE          = 0.6f;
global_variable f32    FOCUS_DISTANCE         = 10.0f;
#define WORLD_SIZE 500

// Note: look at compiler and linker flags

internal f32
Tan_f32(f32 Radians)
{
    return tanf(Radians);
}

internal f32
DegreesToRadians(f32 Degrees)
{
    return Degrees * PI / 180.0f;
}

struct camera
{
    i32    ImageWidth;
    i32    ImageHeight;
    i32    SamplesPerPixel;
    f32    PixelSamplesScale;
    i32    MaxRayBounces;
    f32    DefocusAngle;
    point3 Center;
    vec3   PixelDelta_U;
    vec3   PixelDelta_V;
    point3 ViewportUpperLeft;
    vec3   DefocusDisk_U;
    vec3   DefocusDisk_V;
};

internal void
_Camera(camera *Camera)
{
    Camera->ImageHeight       = IMAGE_HEIGHT;
    Camera->ImageWidth        = IMAGE_WIDTH;
    
    Camera->SamplesPerPixel   = SAMPLES_PER_PIXEL;
    Camera->PixelSamplesScale = 1.0f / Camera->SamplesPerPixel;
    
    Camera->MaxRayBounces     = MAX_RAY_BOUNCES;
    
    f32 Theta                 = DegreesToRadians(VERTICAL_FIELD_OF_VIEW);
    f32 h                     = Tan_f32(Theta / 2);
    f32 ViewportHeight        = 2 * h * FOCUS_DISTANCE;
    f32 ViewportWidth    = ViewportHeight * ((f32)IMAGE_WIDTH / IMAGE_HEIGHT);
    
    Camera->Center       = LOOK_FROM;
    
    vec3 Back            = normalize(LOOK_FROM - LOOK_AT);
    vec3 Right           = normalize(cross(WORLD_UP, Back));
    vec3 Up              = cross(Back, Right);
    
    vec3 Viewport_U      = ViewportWidth * Right;
    vec3 Viewport_V      = -ViewportHeight * Up;
    
    Camera->PixelDelta_U = Viewport_U / Camera->ImageWidth;
    Camera->PixelDelta_V = Viewport_V / Camera->ImageHeight;
    
    Camera->ViewportUpperLeft = Camera->Center - (FOCUS_DISTANCE * Back) -
        (Viewport_U / 2) - (Viewport_V / 2);
    
    Camera->DefocusAngle      = DEFOCUS_ANGLE;
    
    f32 DefocusRadius         = FOCUS_DISTANCE *
        Tan_f32(DegreesToRadians(DEFOCUS_ANGLE / 2));
    Camera->DefocusDisk_U     = Right * DefocusRadius;
    Camera->DefocusDisk_V     = Up * DefocusRadius;
}

enum material_type : u32
{
    LAMBERTIAN,
    METAL,
    DIELECTRIC,
};

struct material
{
    material_type Type;
    color3        Albedo;
    f32           Fuzz;
    f32           RefractionIndex;
};

internal material
_Lambertian(color3 Albedo)
{
    material Result;
    Result.Type   = LAMBERTIAN;
    Result.Albedo = Albedo;
    return Result;
}

internal material
_Metal(color3 Albedo, f32 Fuzz)
{
    material Result;
    Result.Type   = METAL;
    Result.Albedo = Albedo;
    Result.Fuzz   = Fuzz;
    return Result;
}

internal material
_Dielectric(f32 RefractionIndex)
{
    material Result;
    Result.Type            = DIELECTRIC;
    Result.RefractionIndex = RefractionIndex;
    return Result;
}

struct sphere
{
    f32      Radius;
    point3   Center;
    material Material;
};

internal sphere
_Sphere(f32 Radius, point3 Center, material Material)
{
    sphere Result;
    Result.Radius   = Radius;
    Result.Center   = Center;
    Result.Material = Material;
    return Result;
}

struct world
{
    sphere Spheres[WORLD_SIZE];
    i32    Count;
};

internal void
WorldAdd(world *World, sphere Sphere)
{
    if(World->Count < WORLD_SIZE)
    {
        World->Spheres[World->Count++] = Sphere;
    }
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
                                                      texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB
                                                      width:IMAGE_WIDTH
                                                      height:IMAGE_HEIGHT
                                                      mipmapped:NO];
        
        // Note: textures expensive to create
        id<MTLTexture>           Texture           = [Device
                                                      newTextureWithDescriptor:TextureDescriptor];
        
        MTLRenderPassDescriptor *RenderPassDescriptor =
            [MTLRenderPassDescriptor renderPassDescriptor];
        
        RenderPassDescriptor.colorAttachments[0].texture    = Texture;
        RenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;
        RenderPassDescriptor.colorAttachments[0].storeAction =
            MTLStoreActionStore;
        
        MTLRenderPipelineDescriptor *RenderPipelineDescriptor =
            [[MTLRenderPipelineDescriptor alloc] init];
        
        RenderPipelineDescriptor.vertexFunction   = VertexFunction;
        RenderPipelineDescriptor.fragmentFunction = FragmentFunction;
        RenderPipelineDescriptor.colorAttachments[0].pixelFormat =
            MTLPixelFormatRGBA8Unorm_sRGB;
        
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
        
        float                      VerticesAndUVs[]    = {
            -1.0f, -1.0f, 0.0f, 1.0f, -1.0f, 1.0f,  0.0f, 0.0f,
            1.0f,  -1.0f, 1.0f, 1.0f, 1.0f,  -1.0f, 1.0f, 1.0f,
            -1.0f, 1.0f,  0.0f, 0.0f, 1.0f,  1.0f,  1.0f, 0.0f,
        };
        
        // Note: Buffers expensive to create
        id<MTLBuffer> VertexBuffer = [Device
                                      newBufferWithBytes:VerticesAndUVs
                                      length:sizeof(VerticesAndUVs)
                                      options:0];
        
        material      Ground       = _Lambertian(_Color3(0.5f, 0.5f, 0.5f));
        
        rng           RNG;
        InitializeRNG(&RNG, 1223, 832);
        world World = {};
        WorldAdd(&World, _Sphere(1000, _Point3(0, -1000, 0), Ground));
        for(i32 a = -11; a < 11; ++a)
        {
            for(i32 b = -11; b < 11; ++b)
            {
                f32    ChooseMaterial = Random_f32(&RNG);
                point3 Center = _Point3(a + 0.9f * Random_f32(&RNG), 0.2f,
                                        b + 0.9f * Random_f32(&RNG));
                if(length(Center - _Point3(4, 0.2f, 0)) > 0.9f)
                {
                    material Material;
                    if(ChooseMaterial < 0.8f)
                    {
                        color3 Albedo = RandomColor(&RNG) * RandomColor(&RNG);
                        Material      = _Lambertian(Albedo);
                        WorldAdd(&World, _Sphere(0.2f, Center, Material));
                    }
                    else if(ChooseMaterial < 0.95)
                    {
                        color3 Albedo = RandomColor_InRange(0.5f, 1, &RNG);
                        f32    Fuzz   = Random_f32_InRange(0, 0.5f, &RNG);
                        Material      = _Metal(Albedo, Fuzz);
                        WorldAdd(&World, _Sphere(0.2f, Center, Material));
                    }
                    else
                    {
                        Material = _Dielectric(1.5f);
                        WorldAdd(&World, _Sphere(0.2f, Center, Material));
                    }
                }
            }
        }
        material Material1 = _Dielectric(1.5f);
        WorldAdd(&World, _Sphere(1.0f, _Point3(0, 1, 0), Material1));
        
        material Material2 = _Lambertian(_Color3(0.4f, 0.2f, 0.1f));
        WorldAdd(&World, _Sphere(1.0f, _Point3(-4, 1, 0), Material2));
        
        material Material3 = _Metal(_Color3(0.7f, 0.6f, 0.5f), 0);
        WorldAdd(&World, _Sphere(1.0f, _Point3(4, 1, 0), Material3));
        
        // Note: Buffers expensive to create
        id<MTLBuffer> SphereBuffer      = [Device
                                           newBufferWithBytes:World.Spheres
                                           length:sizeof(World.Spheres)
                                           options:0];
        
        // Note: Buffers expensive to create
        id<MTLBuffer> SphereCountBuffer = [Device
                                           newBufferWithBytes:&World.Count
                                           length:sizeof(World.Count)
                                           options:0];
        
        camera        Camera            = {};
        _Camera(&Camera);
        id<MTLBuffer> CameraBuffer = [Device newBufferWithBytes:&Camera
                                      length:sizeof(Camera)
                                      options:0];
        id<MTLCommandBuffer> CommandBuffer = [CommandQueue commandBuffer];
        id<MTLRenderCommandEncoder> RenderCommandEncoder = [CommandBuffer
                                                            renderCommandEncoderWithDescriptor:RenderPassDescriptor];
        [RenderCommandEncoder setRenderPipelineState:RenderPipelineState];
        [RenderCommandEncoder setVertexBuffer:VertexBuffer offset:0 atIndex:0];
        
        [RenderCommandEncoder setFragmentBuffer:SphereBuffer
         offset:0
         atIndex:0];
        
        [RenderCommandEncoder setFragmentBuffer:SphereCountBuffer
         offset:0
         atIndex:1];
        
        [RenderCommandEncoder setFragmentBuffer:CameraBuffer
         offset:0
         atIndex:2];
        
        i32 GridSize   = 1;
        i32 TotalTiles = GridSize * GridSize;
        f64 TileWidth  = IMAGE_WIDTH / GridSize;
        f64 TileHeight = IMAGE_HEIGHT / GridSize;
        for(i32 Row = 0; Row < GridSize; ++Row)
        {
            for(i32 Col = 0; Col < GridSize; ++Col)
            {
                
                f64         OriginX = Col * TileWidth;
                f64         OriginY = Row * TileHeight;
                MTLViewport Viewport;
                Viewport.originX = OriginX;
                Viewport.originY = OriginY;
                Viewport.width   = TileWidth;
                Viewport.height  = TileHeight;
                Viewport.znear   = 0.0;
                Viewport.zfar    = 1.0;
                [RenderCommandEncoder setViewport:Viewport];
                [RenderCommandEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                 vertexStart:0
                 vertexCount:6];
            }
        }
        
        [RenderCommandEncoder endEncoding];
        [CommandBuffer commit];
        [CommandBuffer waitUntilCompleted];
        
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