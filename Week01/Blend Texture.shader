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
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_fog

            #pragma shader_feature_local _UnityFogEnable
            #pragma shader_feature_local _FlipNoise
            
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
            CBUFFER_END
            
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