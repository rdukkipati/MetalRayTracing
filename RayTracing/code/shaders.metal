#include <metal_stdlib>

using namespace metal;

#define internal static
#define PI       3.14159265359f

typedef float3 vec3;
typedef float3 point3;
typedef float3 color3;

struct rng
{
	uint64_t State;
	uint64_t SequenceConstant;
};

internal uint32_t
Random_u32(thread rng *RNG)
{
	uint64_t OldState = RNG->State;
	RNG->State = OldState * 6364136223846793005ULL + RNG->SequenceConstant;
	uint32_t Xorshifted = ((OldState >> 18u) ^ OldState) >> 27u;
	uint32_t Rot = OldState >> 59u;
	return (Xorshifted >> Rot) | (Xorshifted << ((-Rot) & 31));
}

internal void
InitializeRNG(thread rng *RNG, uint64_t InitialState, uint64_t StreamID)
{
	RNG->State = 0U;
	RNG->SequenceConstant = (StreamID << 1u) | 1u;
	Random_u32(RNG);
	RNG->State += InitialState;
	Random_u32(RNG);
}

internal float
Random_f32(thread rng *RNG)
{
	uint32_t Value = Random_u32(RNG);
	uint32_t Bits = (Value >> 9) | 0x3f800000;
	float Result = as_type<float>(Bits);
	return Result - 1.0f;
}

internal float
Random_f32_InRange(float Min, float Max, thread rng *RNG)
{
	return Min + (Max - Min) * Random_f32(RNG);
}

struct camera
{
    int    ImageWidth;
    int    ImageHeight;
	int SamplesPerPixel;
	float PixelSamplesScale;
    point3 Center;
    vec3   PixelDelta_U;
    vec3   PixelDelta_V;
    point3 ViewportUpperLeft;
};

internal float
DegreesToRadians(float Degrees)
{
    return Degrees * PI / 180.0f;
}

struct interval
{
    float Min;
    float Max;
};

internal interval
_Interval(float Min, float Max)
{
    interval Result;
    Result.Min = Min;
    Result.Max = Max;
    return Result;
}

internal float
IntervalSize(interval Interval)
{
    return Interval.Max - Interval.Min;
}

internal bool
IntervalContains(interval Interval, float Value)
{
    return Interval.Min <= Value && Value <= Interval.Max;
}

internal bool
IntervalSurrounds(interval Interval, float Value)
{
    return Interval.Min < Value && Value < Interval.Max;
}

internal float
IntervalClamp(interval Interval, float Value)
{
    if(Value < Interval.Min)
    {
        return Interval.Min;
    }
    if(Value > Interval.Max)
    {
        return Interval.Max;
    }
    return Value;
}

struct ray
{
    point3 Origin;
    vec3   Direction;
};

internal ray
_Ray(point3 Origin, vec3 Direction)
{
    ray Result;
    Result.Origin    = Origin;
    Result.Direction = Direction;
    return Result;
}

internal point3
RayAt(ray Ray, float Time)
{
    return Ray.Origin + (Time * Ray.Direction);
}

struct sphere
{
    float  Radius;
    point3 Center;
};

struct world
{
    constant sphere *Spheres;
    uint             SphereCount;
};

struct hit
{
    point3 Point;
    vec3   Normal;
    float  Time;
    bool   Outside;
};

internal void
SetFaceNormal(ray Ray, vec3 OutwardNormal, thread hit *Hit)
{
    Hit->Outside = dot(Ray.Direction, OutwardNormal) < 0;
    Hit->Normal  = Hit->Outside ? OutwardNormal : -OutwardNormal;
}

internal bool
HitSphere(sphere Sphere, ray Ray, interval Interval, thread hit *Hit)
{
    float Radius         = Sphere.Radius;
    vec3  OriginToCenter = Sphere.Center - Ray.Origin;
    float a              = dot(Ray.Direction, Ray.Direction);
    float h              = dot(Ray.Direction, OriginToCenter);
    float c            = dot(OriginToCenter, OriginToCenter) - Radius * Radius;
    float Discriminant = h * h - a * c;

    if(Discriminant < 0)
    {
        return false;
    }
    float Root = sqrt(Discriminant);
    float Time = (h - Root) / a;
    if(!IntervalSurrounds(Interval, Time))
    {
        Time = (h + Root) / a;
        if(!IntervalSurrounds(Interval, Time))
        {
            return false;
        }
    }
    Hit->Time          = Time;
    Hit->Point         = RayAt(Ray, Time);
    vec3 OutwardNormal = (Hit->Point - Sphere.Center) / Sphere.Radius;
    SetFaceNormal(Ray, OutwardNormal, Hit);

    return true;
}

internal bool
HitWorld(world World, ray Ray, interval Interval, thread hit *Hit)
{
    bool  HitAnything = false;
    float ClosestTime = Interval.Max;

    for(uint Count = 0; Count < World.SphereCount; ++Count)
    {
        sphere Sphere = World.Spheres[Count];
        Interval.Max  = ClosestTime;
        if(HitSphere(Sphere, Ray, Interval, Hit))
        {
            HitAnything = true;
            ClosestTime = Hit->Time;
        }
    }

    return HitAnything;
}

internal color3
RayColor(ray Ray, world World)
{
    hit Hit;
    if(HitWorld(World, Ray, _Interval(0, INFINITY), &Hit))
    {
        return 0.5f * (Hit.Normal + color3(1, 1, 1));
    }

    vec3   UnitDirection = normalize(Ray.Direction);
    float  LerpFactor    = 0.5f * (UnitDirection.y + 1.0f);
    color3 SkyColor      = mix(float3(1.0, 1.0, 1.0), float3(0.5, 0.7, 1.0),
                               LerpFactor);
    return SkyColor;
}

internal ray
GetRandomRay(int x, int y, constant camera *Camera, thread rng *RNG)
{
	vec3 Offset = vec3(Random_f32(RNG), Random_f32(RNG), 0);
	
	point3 PixelSample = Camera->ViewportUpperLeft + 
						 ((x + Offset.x) * Camera->PixelDelta_U) + 
						 ((y + Offset.y) * Camera->PixelDelta_V);

	point3 RayOrigin = Camera->Center;
	
	vec3 RayDirection = PixelSample - RayOrigin;

	return _Ray(RayOrigin, RayDirection);
	
}

struct vertex_in
{
    float2 Position [[attribute(0)]];
    float2 UV [[attribute(1)]];
};

struct vertex_out
{
    float4 Position [[position]];
    float2 UV;
};

struct fragment_out
{
    half4 Color;
};

[[vertex]] vertex_out
VertexFunction(vertex_in Vertex [[stage_in]])
{
    vertex_out Result;

    Result.Position = float4(Vertex.Position, 0.0f, 1.0f);
    Result.UV       = Vertex.UV;

    return Result;
}

[[fragment]] fragment_out
FragmentFunction(vertex_out       Fragment [[stage_in]],
                 constant sphere *Spheres [[buffer(1)]],
                 constant uint   *SphereCount [[buffer(2)]],
                 constant camera *Camera [[buffer(3)]])
{

	uint32_t x = (uint32_t)Fragment.Position.x;
	uint32_t y = (uint32_t)Fragment.Position.y;

	uint64_t RNGStream = y * Camera->ImageWidth + x;
	rng RNG = {};
	InitializeRNG(&RNG, 0, RNGStream);

    world        World = {Spheres, *SphereCount};

    fragment_out Result;

	color3 PixelColor = color3(0, 0, 0);

	for(int Sample = 0; Sample < Camera->SamplesPerPixel; ++Sample)
	{
		ray Ray = GetRandomRay(x, y, Camera, &RNG);
		PixelColor += RayColor(Ray, World);
	}

	PixelColor *= Camera->PixelSamplesScale;

    Result.Color              = half4(half3(PixelColor), 1.0);

    return Result;
}