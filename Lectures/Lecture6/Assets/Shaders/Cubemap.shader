Shader "0_Custom/Cubemap"
{
    Properties
    {
        _BaseColor ("Color", Color) = (0, 0, 0, 1)
        _Roughness ("Roughness", Range(0.03, 1)) = 1
        _Cube ("Cubemap", CUBE) = "" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"
            
            #define EPS 1e-7
            #define MONTECARLO_N 10000

            struct appdata
            {
                float4 vertex : POSITION;
                fixed3 normal : NORMAL;
            };

            struct v2f
            {
                float4 clip : SV_POSITION;
                float4 pos : TEXCOORD1;
                fixed3 normal : NORMAL;
            };

            float4 _BaseColor;
            float _Roughness;
            
            samplerCUBE _Cube;
            half4 _Cube_HDR;
            
            v2f vert (appdata v)
            {
                v2f o;
                o.clip = UnityObjectToClipPos(v.vertex);
                o.pos = mul(UNITY_MATRIX_M, v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                return o;
            }

            uint Hash(uint s)
            {
                s ^= 2747636419u;
                s *= 2654435769u;
                s ^= s >> 16;
                s *= 2654435769u;
                s ^= s >> 16;
                s *= 2654435769u;
                return s;
            }
            
            float Random(uint seed)
            {
                return float(Hash(seed)) / 4294967295.0; // 2^32-1
            }

            float Random(uint seed, float a, float b)
            {
                return Random(seed) * (b - a) + a;
            }
            
            float3 SampleColor(float3 direction)
            {   
                half4 tex = texCUBE(_Cube, direction);
                return DecodeHDR(tex, _Cube_HDR).rgb;
            }
            
            float Sqr(float x)
            {
                return x * x;
            }

            float CosToSin(float x)
            {
                return sqrt(1 - Sqr(x));
            }
            
            // Calculated according to NDF of Cook-Torrance
            float GetSpecularBRDF(float3 viewDir, float3 lightDir, float3 normalDir)
            {
                float3 halfwayVector = normalize(viewDir + lightDir);               
                
                float a = Sqr(_Roughness);
                float a2 = Sqr(a);
                float NDotH2 = Sqr(dot(normalDir, halfwayVector));
                
                return a2 / (UNITY_PI * Sqr(NDotH2 * (a2 - 1) + 1));
            }

            // Calculates matrix which transforms 
            // (0.0, 0.0, 1.0) into given normal vector
            float3x3 GetRotationMatrix(float3 normal)
            {
                float3 ez = float3(0.0, 0.0, 1.0);
                float3 crossV = normalize(cross(normal, ez));
                float cosRotate = dot(normal, ez) / length(normal);
                float sinRotate = CosToSin(cosRotate);

                // rotates around crossV at arccos(cosRotate) angle
                float3x3 rotateMatrix = float3x3(
                    cosRotate + (1 - cosRotate) * Sqr(crossV.x), 
                    (1 - cosRotate) * crossV.x * crossV.y - sinRotate * crossV.z, 
                    (1 - cosRotate) * crossV.x * crossV.z + sinRotate * crossV.y,

                    (1 - cosRotate) * crossV.y * crossV.x + sinRotate * crossV.z,
                    cosRotate + (1 - cosRotate) * Sqr(crossV.y),
                    (1 - cosRotate) * crossV.y * crossV.z - sinRotate * crossV.x,

                    (1 - cosRotate) * crossV.z * crossV.x - sinRotate * crossV.y,
                    (1 - cosRotate) * crossV.z * crossV.y + sinRotate * crossV.x,
                    cosRotate + (1 - cosRotate) * Sqr(crossV.z)
                );
                
                return transpose(rotateMatrix);
            }

            float3 GetRandomVector(uint i)
            {
                float cosBeta = Random(i, 0.0, 1.0);
                float aplha = Random(i + MONTECARLO_N, 0.0, 2 * UNITY_PI);
                float sinBeta = CosToSin(cosBeta);
                float3 w = float3(sinBeta * cos(aplha), sinBeta * sin(aplha), cosBeta);
                
                return w;
            }
            
            fixed4 frag (v2f i) : SV_Target
            {
                float3 normal = normalize(i.normal);
                
                float3 viewDirection = normalize(_WorldSpaceCameraPos - i.pos.xyz);
                
                float3x3 rotateMatrix = GetRotationMatrix(normal);
                float3 L0 = float3(0.0, 0.0, 0.0);
                float sum = 0.0;

                for (uint i = 0; i < MONTECARLO_N; i++)
                {
                    float3 w0 = GetRandomVector(i);
                    // transforming w from upper half-space 
                    // into half-space defined by normal
                    float3 w = mul(rotateMatrix, w0);
                    float cosTheta = dot(normal, w);
                    float fValue = GetSpecularBRDF(viewDirection, w, normal);

                    L0 += SampleColor(w) * fValue * cosTheta;
                    sum += fValue * cosTheta;
                }

                float3 specular = L0 / sum;
                
                return fixed4(specular, 1);
            }
            ENDCG
        }
    }
}
