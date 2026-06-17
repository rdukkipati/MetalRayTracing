#include <metal_common>
#include <metal_geometric>

using namespace metal;

#define internal static

typedef float3 vec3;
typedef float3 point3;
typedef float3 color3;

typedef int b32;

constant constexpr int Image_Height = 2234;
constant constexpr int Image_Width = 3456;
constant constexpr float FocalLength = 1.0f;
constant constexpr float ViewportHeight = 2.0f;
constant constexpr float ViewportWidth = ViewportHeight * ((float)Image_Width / Image_Height);
constant constexpr point3 CameraCenter = point3(0, 0, 0);

constant constexpr vec3 Viewport_U = vec3(ViewportWidth, 0, 0);
constant constexpr vec3 Viewport_V = vec3(0, -ViewportHeight, 0);

constant constexpr point3 ViewportUpperLeft = CameraCenter - vec3(0, 0, FocalLength) - (Viewport_U / 2) - (Viewport_V / 2);

struct ray
{
	point3 Origin;
	vec3 Direction;
};

internal ray
_Ray(point3 Origin, vec3 Direction)
{
	ray Result;
	Result.Origin = Origin;
	Result.Direction = Direction;
	return Result;
}

internal point3
RayAt(ray Ray, float Time)
{
	return Ray.Origin + (Time * Ray.Direction);
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

internal bool
HitSphere(point3 Center, float Radius, ray Ray)
{
	vec3 OriginToCenter = Center - Ray.Origin;
	float a = dot(Ray.Direction, Ray.Direction);
	float b = -2.0f * dot(Ray.Direction, OriginToCenter);
	float c = dot(OriginToCenter, OriginToCenter) - Radius*Radius;
	float Discriminant = b*b - 4*a*c;
	return Discriminant >= 0;
}

internal float3
RayColor(ray Ray)
{
	bool Hit = HitSphere(point3(0, 0, -1), 0.5f, Ray);
	
	vec3 UnitDirection = normalize(Ray.Direction);
	float LerpFactor = 0.5f * (UnitDirection.y + 1.0f);
	float3 SkyColor = mix(float3(1.0, 1.0, 1.0), 
						  float3(0.5, 0.7, 1.0), 
						  LerpFactor);

	return mix(SkyColor, float3(1.0, 0.0, 0.0), Hit);
}

[[vertex]] vertex_out
VertexFunction(vertex_in Vertex [[stage_in]])
{
	vertex_out Result;
	
	Result.Position = float4(Vertex.Position, 0.0f, 1.0f);
	Result.UV = Vertex.UV;

	return Result;
}

[[fragment]] fragment_out
FragmentFunction(vertex_out Fragment [[stage_in]])
{
	fragment_out Result;

	point3 PixelCenterInWorldSpace = ViewportUpperLeft + 
									 Fragment.UV.x * Viewport_U + 
									 Fragment.UV.y * Viewport_V;

	vec3 RayDirection = PixelCenterInWorldSpace - CameraCenter;
	ray Ray = _Ray(CameraCenter, RayDirection);
 
	float3 PixelColor = RayColor(Ray);
	Result.Color = half4(half3(PixelColor), 1.0);

	return Result;
}