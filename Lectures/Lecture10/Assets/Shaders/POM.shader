Shader "Custom/POM"
{
    Properties {
        // normal map texture on the material,
        // default to dummy "flat surface" normalmap
        [KeywordEnum(PLAIN, NORMAL, BUMP, POM, POM_SHADOWS)] MODE("Overlay mode", Float) = 0
        
        _NormalMap("Normal Map", 2D) = "bump" {}
        _MainTex("Texture", 2D) = "grey" {}
        _HeightMap("Height Map", 2D) = "white" {}
        _MaxHeight("Max Height", Range(0.0001, 0.02)) = 0.01
        _StepLength("Step Length", Float) = 0.000001
        _MaxStepCount("Max Step Count", Int) = 64
        
        _Reflectivity("Reflectivity", Range(1, 100)) = 0.5
    }
    
    CGINCLUDE
    #include "UnityCG.cginc"
    #include "UnityLightingCommon.cginc"
    
    inline float LinearEyeDepthToOutDepth(float z)
    {
        return (1 - _ZBufferParams.w * z) / (_ZBufferParams.z * z);
    }

    struct v2f {
        float3 worldPos : TEXCOORD0;
        half3 worldSurfaceNormal : TEXCOORD4;
        // texture coordinate for the normal map
        float2 uv : TEXCOORD5;
        float4 clip : SV_POSITION;
        
        half3x3 tangentToWorld : TEXCOORD6;
    };

    // Vertex shader now also gets a per-vertex tangent vector.
    // In Unity tangents are 4D vectors, with the .w component used to indicate direction of the bitangent vector.
    v2f vert (float4 vertex : POSITION, float3 normal : NORMAL, float4 tangent : TANGENT, float2 uv : TEXCOORD0)
    {
        v2f o;
        o.clip = UnityObjectToClipPos(vertex);
        o.worldPos = mul(unity_ObjectToWorld, vertex).xyz;
        half3 wNormal = UnityObjectToWorldNormal(normal);
        half3 wTangent = UnityObjectToWorldDir(tangent.xyz);
        
        o.uv = uv;
        o.worldSurfaceNormal = normal;
        
        // compute bitangent from cross product of normal and tangent and output it
        half tangentSign = tangent.w * unity_WorldTransformParams.w;
        half3 wBitangent = cross(wNormal, wTangent) * tangentSign;       
        o.tangentToWorld = half3x3(
            half3(wTangent.x, wBitangent.x, wNormal.x),
            half3(wTangent.y, wBitangent.y, wNormal.y),
            half3(wTangent.z, wBitangent.z, wNormal.z));
        
        return o;
    }

    // normal map texture from shader properties
    sampler2D _NormalMap;
    sampler2D _MainTex;
    sampler2D _HeightMap;
    
    // The maximum depth in which the ray can go.
    uniform float _MaxHeight;
    // Step size
    uniform float _StepLength;
    // Count of steps
    uniform int _MaxStepCount;
    
    float _Reflectivity;

    void frag (in v2f i, out half4 outColor : COLOR, out float outDepth : DEPTH)
    {
        float2 uv = i.uv;
        float3x3 worldToTangent = transpose(i.tangentToWorld);
        
        float3 worldViewDir = normalize(i.worldPos.xyz - _WorldSpaceCameraPos.xyz);
        float3 tangentWorldDir = mul(worldToTangent, worldViewDir);
#if MODE_BUMP
        // Change UV according to the Parallax Offset Mapping

        float height = (1.0 - tex2D(_HeightMap, uv).r) * _MaxHeight;
        float2 offset = height * tangentWorldDir.xy / tangentWorldDir.z;
        uv -= offset;        
#endif   
    
        float depthDif = 0;
#if MODE_POM | MODE_POM_SHADOWS    
        // Change UV according to Parallax Occclusion Mapping
        
        float2 stepUV = _StepLength * normalize(tangentWorldDir).xy;
        float stepH = _StepLength;
        float curHeight = _MaxHeight;
        float curTexHeight = (1.0 - tex2D(_HeightMap, uv).r) * _MaxHeight;
        
        for (int stepIdx = 0; stepIdx < _MaxStepCount; stepIdx++)
        {
            if (curHeight > curTexHeight)
            {
                uv -= stepUV;
                curHeight -= stepH;
                curTexHeight = (1.0 - tex2D(_HeightMap, uv).r) * _MaxHeight;
            }
        }

        float2 uvA = uv + stepUV;       
        float dA = (curHeight + stepH) - (1.0 - tex2D(_HeightMap, uvA).r) * _MaxHeight;
        float dB = curTexHeight - curHeight;
        float w = dA / (dA + dB);
        uv = lerp(uvA, uv, w);
        
        curTexHeight = (1.0 - tex2D(_HeightMap, uv).r) * _MaxHeight;
        //depthDif = _MaxHeight - curTexHeight;
        //depthDif = sqrt((_MaxHeight - curTexHeight) * (_MaxHeight - curTexHeight) + (i.uv - uv) * (i.uv - uv));

        float3 start = UnityWorldToClipPos(mul(i.tangentToWorld, float3(i.uv, _MaxHeight))).xyz;
        float3 end   = UnityWorldToClipPos(mul(i.tangentToWorld, float3(uv, curTexHeight))).xyz;
        depthDif = distance(end, start); // * _ZBufferParams.w;
#endif

        float3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);
        float shadow = 0;
#if MODE_POM_SHADOWS
        // Calculate soft shadows according to Parallax Occclusion Mapping, assign to shadow
#endif
        
        half3 normal = i.worldSurfaceNormal;
#if !MODE_PLAIN
        // Implement Normal Mapping
        
        half3 tnormal = UnpackNormal(tex2D(_NormalMap, uv));
        normal = mul(i.tangentToWorld, tnormal);       
#endif

        // Diffuse lightning
        half cosTheta = max(0, dot(normal, worldLightDir));
        half3 diffuseLight = max(0, cosTheta) * _LightColor0 * max(0, 1 - shadow);
        
        // Specular lighting (ad-hoc)
        half specularLight = pow(max(0, dot(worldViewDir, reflect(worldLightDir, normal))), _Reflectivity) * _LightColor0 * max(0, 1 - shadow); 

        // Ambient lighting
        half3 ambient = ShadeSH9(half4(UnityObjectToWorldNormal(normal), 1));

        // Return resulting color
        float3 texColor = tex2D(_MainTex, uv);
        outColor = half4((diffuseLight + specularLight + ambient) * texColor, 0);
        outDepth = LinearEyeDepthToOutDepth(LinearEyeDepth(i.clip.z) - depthDif);
    }
    ENDCG
    
    SubShader
    {    
        Pass
        {
            Name "MAIN"
            Tags { "LightMode" = "ForwardBase" }
        
            ZTest Less
            ZWrite On
            Cull Back
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile_local MODE_PLAIN MODE_NORMAL MODE_BUMP MODE_POM MODE_POM_SHADOWS
            ENDCG
            
        }
    }
}