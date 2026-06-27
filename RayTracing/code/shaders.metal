// Note: recursion seems to be inlined by compiler because normally it 
//	   isn't allowed

#include <metal_stdlib>

using namespace metal;

#define internal static
#define PI       3.14159265359f

typedef float3 vec3;
typedef float3 point3;
typedef float3 color3;

typedef int8_t  i8;
typedef int16_t i16;
typedef int32_t i32;
typedef int64_t i64;

typedef uint8_t     u8;
typedef uint16_t    u16;
typedef uint32_t    u32;
typedef uint64_t    u64;

typedef float       f32;

internal f32
LengthSq_vec3(vec3 Vector)
{
	f32 Result = dot(Vector, Vector);
	return Result;
}

struct rng
{
	u64 State;
	u64 SequenceConstant;
};

internal u32
Random_u32(thread rng *RNG)
{
	u64 OldState = RNG->State;
	RNG->State = OldState * 6364136223846793005ULL + RNG->SequenceConstant;
	u32 Xorshifted = ((OldState >> 18u) ^ OldState) >> 27u;
	u32 Rot = OldState >> 59u;
	return (Xorshifted >> Rot) | (Xorshifted << ((-Rot) & 31));
}

internal void
InitializeRNG(thread rng *RNG, u64 InitialState, u64 StreamID)
{
	RNG->State = 0U;
	RNG->SequenceConstant = (StreamID << 1u) | 1u;
	Random_u32(RNG);
	RNG->State += InitialState;
	Random_u32(RNG);
}

internal f32
Random_f32(thread rng *RNG)
{
	u32 Value = Random_u32(RNG);
	u32 Bits = (Value >> 9) | 0x3f800000;
	f32 Result = as_type<f32>(Bits);
	return Result - 1.0f;
}

internal f32
Random_f32_InRange(f32 Min, f32 Max, thread rng *RNG)
{
	return Min + (Max - Min) * Random_f32(RNG);
}

internal vec3
Random_vec3(thread rng *RNG)
{
	return vec3(Random_f32(RNG), Random_f32(RNG), Random_f32(RNG));
}

internal vec3
Random_vec3_InRange(f32 Min, f32 Max, thread rng *RNG)
{
	return vec3(Random_f32_InRange(Min, Max, RNG), 
				Random_f32_InRange(Min, Max, RNG), 
				Random_f32_InRange(Min, Max, RNG));
}

internal vec3
RandomUnitVector(thread rng *RNG)
{
	while(true)
	{
		vec3 RandomVector = Random_vec3_InRange(-1, 1, RNG);
		f32 LengthSquared = LengthSq_vec3(RandomVector);
		if(1e-20f < LengthSquared && LengthSquared <= 1)
		{
			return RandomVector / sqrt(LengthSquared);
		}
	}
}

internal vec3
RandomVectorOnHemisphere(vec3 Normal, thread rng *RNG)
{
	vec3 OnUnitSphere = RandomUnitVector(RNG);
	if(dot(OnUnitSphere, Normal) > 0.0f)
	{
		return OnUnitSphere;
	}
	else
	{
		return -OnUnitSphere;
	}
}

internal bool
VectorNearZero(vec3 Vector)
{
	f32 NearZero_Epsilon = 1e-8f;
	bool NearZero = (fabs(Vector.x) < NearZero_Epsilon) && 
					(fabs(Vector.y) < NearZero_Epsilon) && 
					(fabs(Vector.z) < NearZero_Epsilon);
	return NearZero;
}

struct camera
{
    i32    ImageWidth;
    i32    ImageHeight;
	i32 SamplesPerPixel;
	f32 PixelSamplesScale;
	i32 MaxRayBounces;
    point3 Center;
    vec3   PixelDelta_U;
    vec3   PixelDelta_V;
    point3 ViewportUpperLeft;
};

internal f32
DegreesToRadians(f32 Degrees)
{
    return Degrees * PI / 180.0f;
}

struct interval
{
    f32 Min;
    f32 Max;
};

internal interval
_Interval(f32 Min, f32 Max)
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
IntervalContains(interval Interval, f32 Value)
{
    return Interval.Min <= Value && Value <= Interval.Max;
}

internal bool
IntervalSurrounds(interval Interval, f32 Value)
{
    return Interval.Min < Value && Value < Interval.Max;
}

internal f32
IntervalClamp(interval Interval, f32 Value)
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
RayAt(ray Ray, f32 Time)
{
    return Ray.Origin + (Time * Ray.Direction);
}

enum material_type : u32
{
	LAMBERTIAN,
	METAL,
};

struct material
{
	material_type Type;
	color3 Albedo;
	f32 Fuzz;
};

struct sphere
{
    f32  Radius;
    point3 Center;
	material Material;
};

struct world
{
    constant sphere *Spheres;
    u32             SphereCount;
};

struct hit
{
    point3 Point;
    vec3   Normal;
    f32  Time;
    bool   Outside;
	material Material;
};

internal bool
LambertianScatter(ray Ray, thread hit *Hit, thread color3 *Attenuation, 
				  thread ray *ScatteredRay, thread rng *RNG)
{
	vec3 ScatterDirection = Hit->Normal + RandomUnitVector(RNG);

	if(VectorNearZero(ScatterDirection))
	{
		ScatterDirection = Hit->Normal;
	}

	*ScatteredRay = _Ray(Hit->Point, ScatterDirection);
	*Attenuation = Hit->Material.Albedo;
	return true;
}

internal vec3
Reflect(vec3 IncomingVector, vec3 Normal)
{
	return IncomingVector - 2 * dot(IncomingVector, Normal) * Normal;
}

internal bool
MetalScatter(ray Ray, thread hit *Hit, thread color3 *Attenuation, 
			 thread ray *ScatteredRay, thread rng *RNG)
{
	vec3 Reflected = Reflect(Ray.Direction, Hit->Normal);
	Reflected = normalize(Reflected) + 
				(Hit->Material.Fuzz * RandomUnitVector(RNG));
	*ScatteredRay = _Ray(Hit->Point, Reflected);
	*Attenuation = Hit->Material.Albedo;
	return (dot(ScatteredRay->Direction, Hit->Normal) > 0);
}

internal vec3
Refract(vec3 IncomingVector, vec3 Normal, f32 RefractiveRatio)
{
	f32 CosTheta = min(dot(-IncomingVector, Normal), 1.0f);
	vec3 Perpendicular = RefractiveRatio * (IncomingVector + CosTheta * Normal);
	vec3 Parallel = -sqrt(fabs(1.0f - LengthSq_vec3(Perpendicular))) * Normal;
	return Perpendicular + Parallel;
}

internal f32
Reflectance(f32 Cosine, f32 RefractionIndex)
{
	f32 r0 = (1 - RefractionIndex) / (1 + RefractionIndex);
	r0 = r0 * r0;
	return r0 + (1 - r0) * pow((1 - Cosine), 5.0f);
}

internal bool
DielectricScatter(ray Ray, thread hit *Hit, thread color *Attenuation, 
				  thread ray *ScatteredRay, thread rng *RNG)
{
	*Attenuation = color3(1.0f, 1.0f, 1.0f);
	f32 RefractionIndex = Hit->Material.RefractionIndex;
}

internal bool
Scatter(ray Ray, thread hit *Hit, thread color3 *Attenuation, 
		thread ray *ScatteredRay, thread rng *RNG)
{
	bool Result = false;
	switch(Hit->Material.Type)
	{
		case LAMBERTIAN:
		{
			Result = LambertianScatter(Ray, Hit, Attenuation, ScatteredRay, RNG);
		}
		break;

		case METAL:
		{
			Result = MetalScatter(Ray, Hit, Attenuation, ScatteredRay, RNG);
		}
		break;
	}

	return Result;
}

internal void
SetFaceNormal(ray Ray, vec3 OutwardNormal, thread hit *Hit)
{
    Hit->Outside = dot(Ray.Direction, OutwardNormal) < 0;
    Hit->Normal  = Hit->Outside ? OutwardNormal : -OutwardNormal;
}

internal bool
HitSphere(sphere Sphere, ray Ray, interval Interval, thread hit *Hit)
{
    f32 Radius         = Sphere.Radius;
    vec3  OriginToCenter = Sphere.Center - Ray.Origin;
    f32 a              = dot(Ray.Direction, Ray.Direction);
    f32 h              = dot(Ray.Direction, OriginToCenter);
    f32 c            = dot(OriginToCenter, OriginToCenter) - Radius * Radius;
    f32 Discriminant = h * h - a * c;

    if(Discriminant < 0)
    {
        return false;
    }
    f32 Root = sqrt(Discriminant);
    f32 Time = (h - Root) / a;
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
	Hit->Material = Sphere.Material;

    return true;
}

internal bool
HitWorld(world World, ray Ray, interval Interval, thread hit *Hit)
{
    bool  HitAnything = false;
    f32 ClosestTime = Interval.Max;

    for(u32 Count = 0; Count < World.SphereCount; ++Count)
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
RayColor(ray Ray, i32 RayBouncesRemaining, world World, thread rng *RNG)
{
	if(RayBouncesRemaining <= 0)
	{
		return vec3(0, 0, 0);
	}
	color3 Color;
    hit Hit;
    if(HitWorld(World, Ray, _Interval(0.001f, INFINITY), &Hit))
    {
		ray ScatteredRay;
		color3 Attenuation;
		if(Scatter(Ray, &Hit, &Attenuation, &ScatteredRay, RNG))
		{
			Color = Attenuation * 
					RayColor(ScatteredRay, RayBouncesRemaining - 1, World, RNG);
		}
		else
		{
			Color = vec3(0, 0, 0);
		}
    }
	
	else
	{
		vec3 UnitDirection = normalize(Ray.Direction);
		f32 LerpFactor = 0.5f * (UnitDirection.y + 1.0f);
		Color = mix(color3(1.0, 1.0, 1.0), color3(0.5, 0.7, 1.0), LerpFactor);
	}

	return Color;

}

internal ray
GetRandomRay(i32 x, i32 y, constant camera *Camera, thread rng *RNG)
{
	vec3 Offset = vec3(Random_f32(RNG), Random_f32(RNG), 0);
	
	point3 PixelSample = Camera->ViewportUpperLeft + 
						 ((x + Offset.x) * Camera->PixelDelta_U) + 
						 ((y + Offset.y) * Camera->PixelDelta_V);

	point3 RayOrigin = Camera->Center;
	
	vec3 RayDirection = PixelSample - RayOrigin;

	return _Ray(RayOrigin, RayDirection);
	
}

internal f32
LinearToGamma(f32 LinearComponent)
{
	if(LinearComponent > 0)
	{
		return sqrt(LinearComponent);
	}
	return 0;
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
                 constant u32   *SphereCount [[buffer(2)]],
                 constant camera *Camera [[buffer(3)]])
{

	u32 x = (u32)Fragment.Position.x;
	u32 y = (u32)Fragment.Position.y;

	u64 RNGStream = y * Camera->ImageWidth + x;
	rng RNG = {};
	InitializeRNG(&RNG, 0, RNGStream);

    world        World = {Spheres, *SphereCount};

    fragment_out Result;

	color3 PixelColor = color3(0, 0, 0);

	for(i32 Sample = 0; Sample < Camera->SamplesPerPixel; ++Sample)
	{
		ray Ray = GetRandomRay(x, y, Camera, &RNG);
		PixelColor += RayColor(Ray, Camera->MaxRayBounces, World, &RNG);
	}

	PixelColor *= Camera->PixelSamplesScale;

    Result.Color              = half4(half3(PixelColor), 1.0);

    return Result;
}