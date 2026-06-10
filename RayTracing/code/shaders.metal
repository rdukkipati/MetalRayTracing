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
VertexShader(vertex_in Vertex [[stage_in]])
{
	vertex_out Result;
	
	Result.Position = float4(Vertex.Position, 1.0f);
	Result.UV = Vertex.UV;

	return Result;
}

[[fragment]] fragment_out
FragmentShader(vertex_out Fragment [[stage_in]])
{
	fragment_out Result;

	Result.Color = Texture.sample(Sampler, Fragment.UV);

	return Result;
}