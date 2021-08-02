Shader "Workshop/Week01/Blend Texture"
{
    Properties
    {
        _MainTex ("Main Texture", 2D) = "white" {}
        _AltTex ("Alt Texture", 2D) = "black" {}
        _NoiseTex ("Noise", 2D) = "white" {}
        [Toggle(_FlipNoise)] _FlipNoise("_FlipNoise (default = off)", float) = 0
        [Space(10)]

        [Header(Edge)]
        [HDR]_EmissionColor("_EmissionColor (default = 1,1,1,1)", color) = (1,1,1,1)
        _Threshold("_Threshold", Range(0.0,1.0)) = 0

        [Header(Grow)]
        _GrowPower("_GrowPower", Range(0,10)) = 2
        _GrowRange("_GrowRange", Range(0.0,0.3)) = 0.1

        [Space(10)]
        [Header(Displacement)]
        [Toggle(_ToggleDisplacement)] _ToggleDisplacement("_ToggleDisplacement (default = off)", float) = 0
        _DStength("Displacement Stength", Range(0, 1)) = 0.1
        _DRange("Displacement Range", Range(0.0,1)) = 0.2
        
        [Space(10)]
        [Header(Tessellation)]
        [KeywordEnum(fractional_odd,fractional_even,pow2,integer)]
        _Partitioning("Partitioning (default = integer)", Float) = 3
        _Tess("Tessellation", Range(1, 32)) = 20
        _MinTessDistance("Min Tess Distance", Range(0.01, 32)) = 3
        _MaxTessDistance("Max Tess Distance", Range(0.01, 32)) = 20

        [Header(Unity Fog)]
        [Toggle(_UnityFogEnable)] _UnityFogEnable("_UnityFogEnable (default = on)", Float) = 1
    }

    SubShader
    {
        // https://docs.unity3d.com/Manual/SL-SubShaderTags.html
        Tags {
            "RenderType" = "Opaque"
            "Queue" = "Geometry" // Queue : { Background, Geometry, AlphaTest, Transparent, Overlay }
            "RenderPipeline" = "UniversalPipeline"
            // "DisableBatching" = "True"
        }
        LOD 100
		
        Pass
        {
            HLSLPROGRAM
            #if defined(SHADER_API_D3D11) || defined(SHADER_API_GLES3) || defined(SHADER_API_GLCORE) || defined(SHADER_API_VULKAN) || defined(SHADER_API_METAL) || defined(SHADER_API_PSSL)
            #define UNITY_CAN_COMPILE_TESSELLATION 1
            #   define UNITY_domain                 domain
            #   define UNITY_partitioning           partitioning
            #   define UNITY_outputtopology         outputtopology
            #   define UNITY_patchconstantfunc      patchconstantfunc
            #   define UNITY_outputcontrolpoints    outputcontrolpoints
            #endif
            // This line defines the name of the vertex shader. 
            #pragma vertex TessellationVertexProgram
            // This line defines the name of the fragment shader. 
            #pragma fragment frag
            // This line defines the name of the hull shader. 
            #pragma hull hull
            // This line defines the name of the domain shader. 
            #pragma domain domain

            #pragma multi_compile_fog

            #pragma shader_feature_local _UnityFogEnable
            #pragma shader_feature_local _FlipNoise
            #pragma shader_feature_local _ToggleDisplacement
            #pragma shader_feature_local _Partitioning
            #pragma multi_compile _PARTITIONING_FRACTIONAL_ODD _PARTITIONING_FRACTIONAL_EVEN _PARTITIONING_POW2 _PARTITIONING_INTEGER
            // The Core.hlsl file contains definitions of frequently used HLSL
            // macros and functions, and also contains #include references to other
            // HLSL files (for example, Common.hlsl, SpaceTransforms.hlsl, etc.).
            // https://github.com/Unity-Technologies/Graphics/blob/master/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            sampler2D _MainTex;
            sampler2D _AltTex;
            sampler2D _NoiseTex;
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _AltTex_ST;
                float4 _NoiseTex_ST;
                half4 _EmissionColor;
                float _Threshold;
                float _GrowRange;
                float _GrowPower;
                float _DStength;
                float _DRange;
                float _Tess;
                float _MinTessDistance;
                float _MaxTessDistance;
            CBUFFER_END
            
            // Pre Tessellation - Extra vertex struct
            struct ControlPoint
            {
                float4 vertex : INTERNALTESSPOS;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
                float3 normal : NORMAL;
            };
            // tessellation data
            struct TessellationFactors
            {
                float edge[3] : SV_TessFactor;
                float inside : SV_InsideTessFactor;
            };

            struct Attributes
            {
                // The positionOS variable contains the vertex positions in object
                // space.
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            struct Varyings
            {
                // The positions in this struct must have the SV_POSITION semantic.
                float4 positionCS : SV_POSITION;
                float4 color : COLOR;
                float3 normal : NORMAL;
                float3 uv_fog : TEXCOORD0; // uv = xy, fog = z
                float3 positionWS : TEXCOORD1;
            };

            // Step 1) prepare Vertices data to Hull program
            // Pre tesselation vertex program
            ControlPoint TessellationVertexProgram(Attributes v)
            {
                ControlPoint p;
                p.vertex = v.vertex;
                p.uv = v.uv;
                p.normal = v.normal;
                p.color = v.color;

                return p;
            }

            // Step 2) Triangle Indices
            // info so the GPU knows what to do (triangles) and how to set it up , clockwise, fractional division
            // hull takes the original vertices and outputs more
            [UNITY_domain("tri")]
            [UNITY_outputcontrolpoints(3)]
            [UNITY_outputtopology("triangle_cw")]
#if _PARTITIONING_FRACTIONAL_ODD 
            [UNITY_partitioning("fractional_odd")]
#endif
#if _PARTITIONING_FRACTIONAL_EVEN 
            [UNITY_partitioning("fractional_even")]
#endif
#if _PARTITIONING_POW2
            [UNITY_partitioning("pow2")]
#endif
#if _PARTITIONING_INTEGER
            [UNITY_partitioning("integer")]
#endif
            [UNITY_patchconstantfunc("patchConstantFunction")] // send data to here
            ControlPoint hull(InputPatch<ControlPoint, 3> patch, uint id : SV_OutputControlPointID)
            {
                return patch[id];
            }

            // Step 3.1) optimization,
            // fade tessellation at a distance
            float CalcDistanceTessFactor(float4 vertex, float minDist, float maxDist, float tess)
            {
                float3 worldPosition = TransformObjectToWorld(vertex.xyz);
                float dist = distance(worldPosition, _WorldSpaceCameraPos);
                // Calculate the factor we need to apply tessellation 0.01 ~ 1;
                float f = clamp(1.0 - ((dist - minDist) / (maxDist - minDist)), 0.01, 1.0) * tess;
                return f;
            }

            // Step 3)
            // Tessellation, receive info from Hull, and patching data.
            TessellationFactors patchConstantFunction(InputPatch<ControlPoint, 3> patch)
            {
                // values for distance fading the tessellation
                // since wrong order will calculate in flipped result.
                // ensure the min/max values.
                float minDist = min(_MinTessDistance, _MaxTessDistance);
                float maxDist = max(_MinTessDistance, _MaxTessDistance);

                TessellationFactors f;

                float edge0 = CalcDistanceTessFactor(patch[0].vertex, minDist, maxDist, _Tess);
                float edge1 = CalcDistanceTessFactor(patch[1].vertex, minDist, maxDist, _Tess);
                float edge2 = CalcDistanceTessFactor(patch[2].vertex, minDist, maxDist, _Tess);

                // make sure there are no gaps between different tessellated distances, by averaging the edges out.
                f.edge[0] = (edge1 + edge2) / 2;
                f.edge[1] = (edge2 + edge0) / 2;
                f.edge[2] = (edge0 + edge1) / 2;
                f.inside = (edge0 + edge1 + edge2) / 3;
                return f;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs vertexPositionInput = GetVertexPositionInputs(IN.vertex.xyz);
                
#if _ToggleDisplacement
                // for displacement.
                float4 uv = float4(TRANSFORM_TEX(IN.uv, _NoiseTex),0,0);
                float noise = clamp(tex2Dlod(_NoiseTex, uv).r, 0.001, 0.999);
#if _FlipNoise
                noise = 1 - noise;
#endif
                float f = smoothstep(noise - (_DRange * _Threshold), noise, _Threshold);
                f = clamp(f * step(f, 0.999), 0, 1);
                f = _DStength * pow(f,2) + f;
                float3 wpos = vertexPositionInput.positionWS + IN.normal * f * _DStength;
                OUT.positionCS = TransformWorldToHClip(wpos);
#else
                OUT.positionCS = vertexPositionInput.positionCS;
#endif
                OUT.color = IN.color;
                OUT.normal = IN.normal;
                OUT.positionWS = vertexPositionInput.positionWS;

                // regular unity fog
#if _UnityFogEnable
                OUT.uv_fog = float3(IN.uv, ComputeFogFactor(OUT.positionCS.z));
#else
                OUT.uv_fog = float3(IN.uv, 0);
#endif
                return OUT;
            }

            // Step 4)
            // prepare vertices & triangles data for Geomertry Program
            // In order work, send data to org vertex program.
            [UNITY_domain("tri")]
            Varyings domain(TessellationFactors factors, OutputPatch<ControlPoint, 3> patch, float3 barycentricCoordinates : SV_DomainLocation)
            {
                Attributes v;
                #define DomainPos(fieldName) v.fieldName = \
				patch[0].fieldName * barycentricCoordinates.x + \
				patch[1].fieldName * barycentricCoordinates.y + \
				patch[2].fieldName * barycentricCoordinates.z;

                DomainPos(vertex)
                DomainPos(uv)
                DomainPos(color)
                DomainPos(normal)

                return vert(v);
            }

            // The fragment shader definition.            
            float4 frag(Varyings IN) : SV_Target
            {
                // calculate UV
                float2 uv1 = TRANSFORM_TEX(IN.uv_fog.xy, _MainTex);
                float2 uv2 = TRANSFORM_TEX(IN.uv_fog.xy, _AltTex);
                float2 uv3 = TRANSFORM_TEX(IN.uv_fog.xy, _NoiseTex);

                // read color from texture.
                float4 col1 = tex2D(_MainTex, uv1);
                float4 col2 = tex2D(_AltTex, uv2);
                // Trim noise a bit smaller then 0 & 1
                float noise = clamp(tex2D(_NoiseTex, uv3).r, 0.001, 0.999);
#if _FlipNoise
                noise = 1 - noise;
#endif
                float t = _Threshold;
                float g = _GrowRange * t;
                float ng = _GrowRange * (1 - t);


                // Locate edge.
                // apply current threshold
                float edge = step(noise, t);
                // Blend between texture(s)
                // float4 col = lerp(col1, col2, edge);
                float4 col = col1 * (1 - edge) + col2 * edge;

                // Calculate smooth edge
                float lower = smoothstep(noise - g, noise, t); // main tex blend to edge
                float higher = 1 - smoothstep(noise, noise + ng, t); // edge blend to alt tex
                float f = clamp(higher + lower - 1, 0, 1);
                // equation : https://www.desmos.com/calculator/zukjgk9iry?lang=zh-TW
                float gf = (_GrowPower + 1) * pow(f,2) + f;
                // Emission
                float4 emis = lerp(float4(1, 1, 1, 0), _EmissionColor, gf);
                col.xyz *= emis.xyz;
                // col = float4(lower, higher, 0, 1);

#if _UnityFogEnable
                col.rgb = MixFog(col.rgb, IN.uv_fog.z);
#endif

                return col;
            }
            ENDHLSL
        }
    }
}