#include <metal_stdlib>

using namespace metal;

#define internal static
#define PI       3.14159265359f

typedef float3            vec3;
typedef float3            point3;
typedef float3            color3;

constant constexpr int    Image_Height   = 2234;
constant constexpr int    Image_Width    = 3456;
constant constexpr float  FocalLength    = 1.0f;
constant constexpr float  ViewportHeight = 2.0f;
constant constexpr float  ViewportWidth  = ViewportHeight *
                                           ((float)Image_Width / Image_Height);
constant constexpr point3 CameraCenter   = point3(0, 0, 0);

constant constexpr vec3   Viewport_U     = vec3(ViewportWidth, 0, 0);
constant constexpr vec3   Viewport_V     = vec3(0, -ViewportHeight, 0);

constant constexpr point3 ViewportUpperLeft = CameraCenter -
                                              vec3(0, 0, FocalLength) -
                                              (Viewport_U / 2) -
                                              (Viewport_V / 2);

internal float
DegreesToRadians(float Degrees)
{
	return Degrees * PI / 180.0f;
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
	uint SphereCount;
};

struct hit
{
    point3 Point;
    vec3   Normal;
    float  Time;
	bool Outside;
};

internal void
SetFaceNormal(ray Ray, vec3 OutwardNormal, thread hit *Hit)
{
	Hit->Outside = dot(Ray.Direction, OutwardNormal) < 0;
	Hit->Normal = Hit->Outside ? OutwardNormal : -OutwardNormal;
}

internal bool
HitSphere(sphere Sphere, ray Ray, float Time_Min, float Time_Max, thread hit *Hit)
{
	float Radius = Sphere.Radius;
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
	if(Time <= Time_Min || Time >= Time_Max)
	{
		Time = (h + Root) / a;
		if(Time <= Time_Min || Time >= Time_Max)
		{
			return false;
		}
	}
	Hit->Time = Time;
	Hit->Point = RayAt(Ray, Time);
	vec3 OutwardNormal = (Hit->Point - Sphere.Center) / Sphere.Radius;
	SetFaceNormal(Ray, OutwardNormal, Hit);
	
	return true;
}

internal bool
HitWorld(world World, ray Ray, float Time_Min, float Time_Max, thread hit *Hit)
{
	bool HitAnything = false;
	float ClosestTime = Time_Max;

	for(uint Count = 0; Count < World.SphereCount; ++Count)
	{
		sphere Sphere = World.Spheres[Count];
		if(HitSphere(Sphere, Ray, Time_Min, ClosestTime, Hit))
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
	if(HitWorld(World, Ray, 0, INFINITY, &Hit))
    {
		return 0.5f * (Hit.Normal + color3(1, 1, 1));
    }

    vec3   UnitDirection = normalize(Ray.Direction);
    float  LerpFactor    = 0.5f * (UnitDirection.y + 1.0f);
    color3 SkyColor      = mix(float3(1.0, 1.0, 1.0), float3(0.5, 0.7, 1.0),
                               LerpFactor);
    return SkyColor;
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
                 constant uint   *SphereCount [[buffer(2)]])
{
	world World = { Spheres, *SphereCount };


    fragment_out Result;

    point3       PixelCenterInWorldSpace = ViewportUpperLeft +
                                           Fragment.UV.x * Viewport_U +
                                           Fragment.UV.y * Viewport_V;

    vec3         RayDirection = PixelCenterInWorldSpace - CameraCenter;
    ray          Ray          = _Ray(CameraCenter, RayDirection);

    color3       PixelColor   = RayColor(Ray, World);
    Result.Color              = half4(half3(PixelColor), 1.0);

    return Result;
}