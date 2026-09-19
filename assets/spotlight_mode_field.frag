#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec4 fillColor;
    vec4 mainShape;
    float mainRadius;
    vec4 button0Shape;
    vec4 button1Shape;
    vec4 button2Shape;
    vec4 button3Shape;
    vec4 blends;
} ubuf;

// Shapes contain center.xy and size.zw. `corner` is the corner radius. The
// search field passes a squircle radius (rounded rectangle) while the mode
// lobes keep a full radius so they stay circular as they grow.
float shapeDistance(vec2 pixel, vec4 shape, float corner)
{
    if (min(shape.z, shape.w) <= 0.001)
        return 1e5;
    float radius = clamp(corner, 0.0, min(shape.z, shape.w) * 0.5);
    vec2 edge = abs(pixel - shape.xy) - shape.zw * 0.5 + vec2(radius);
    return min(max(edge.x, edge.y), 0.0) + length(max(edge, vec2(0.0))) - radius;
}

float smoothMinimum(float first, float second, float radius)
{
    if (radius <= 0.001)
        return min(first, second);
    float influence = max(radius - abs(first - second), 0.0) / radius;
    return min(first, second) - influence * influence * radius * 0.25;
}

void main()
{
    vec2 pixel = qt_TexCoord0 * ubuf.resolution;
    float surface = shapeDistance(pixel, ubuf.mainShape, ubuf.mainRadius);
    surface = smoothMinimum(surface, shapeDistance(pixel, ubuf.button0Shape,
                                                   min(ubuf.button0Shape.z, ubuf.button0Shape.w) * 0.5),
                            ubuf.blends.x);
    surface = smoothMinimum(surface, shapeDistance(pixel, ubuf.button1Shape,
                                                   min(ubuf.button1Shape.z, ubuf.button1Shape.w) * 0.5),
                            ubuf.blends.y);
    surface = smoothMinimum(surface, shapeDistance(pixel, ubuf.button2Shape,
                                                   min(ubuf.button2Shape.z, ubuf.button2Shape.w) * 0.5),
                            ubuf.blends.z);
    surface = smoothMinimum(surface, shapeDistance(pixel, ubuf.button3Shape,
                                                   min(ubuf.button3Shape.z, ubuf.button3Shape.w) * 0.5),
                            ubuf.blends.w);

    // Keep the natural lobes; the item already reserves effect bleed. Screen
    // derivatives keep the edge consistent under window/fractional scaling.
    float aa = max(fwidth(surface), 0.001);
    float alpha = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, surface);
    // Frosted body and a continuous rim, including during the liquid morph.
    float vertical = clamp((pixel.y - ubuf.mainShape.y) / ubuf.mainShape.w + 0.5, 0.0, 1.0);
    vec3 body = ubuf.fillColor.rgb + vec3(0.035 * (1.0 - vertical));
    float rim = 1.0 - smoothstep(0.3, 1.3, abs(surface + 0.7));
    body = mix(body, vec3(1.0), rim * mix(0.7, 0.25, vertical));
    fragColor = vec4(body, 1.0) * alpha * ubuf.qt_Opacity;
}
