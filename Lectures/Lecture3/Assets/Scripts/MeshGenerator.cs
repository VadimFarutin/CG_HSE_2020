using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;

[RequireComponent(typeof(MeshFilter))]
public class MeshGenerator : MonoBehaviour
{
    public MetaBallField Field = new MetaBallField();
    
    private MeshFilter _filter;
    private Mesh _mesh;
    
    private List<Vector3> vertices = new List<Vector3>();
    private List<Vector3> normals = new List<Vector3>();
    private List<int> indices = new List<int>();

    private static readonly float SCENE_SIZE = 8.0F;
    private static readonly float CUBE_SIZE = 0.5F;
    private static readonly float DELTA = 0.01F;

    /// <summary>
    /// Executed by Unity upon object initialization. <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// </summary>
    private void Awake()
    {
        // Getting a component, responsible for storing the mesh
        _filter = GetComponent<MeshFilter>();
        
        // instantiating the mesh
        _mesh = _filter.mesh = new Mesh();
        
        // Just a little optimization, telling unity that the mesh is going to be updated frequently
        _mesh.MarkDynamic();
    }

    /// <summary>
    /// Executed by Unity on every frame <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// You can use it to animate something in runtime.
    /// </summary>
    private void Update()
    {
        vertices.Clear();
        indices.Clear();
        normals.Clear();

        //Uncomment for some animation:
        float speed = Mathf.Sin(Time.time) / 50.0F;
        Field.Balls[0].position += new Vector3(-speed, -speed, 0);
        Field.Balls[1].position += new Vector3(0, speed, 0);
        Field.Balls[2].position += new Vector3(speed, -speed, 0);

        Field.Update();
        // ----------------------------------------------------------------
        // Generate mesh here. Below is a sample code of a cube generation.
        // ----------------------------------------------------------------

        for (float x = -SCENE_SIZE / 2; x < SCENE_SIZE / 2; x += CUBE_SIZE)
        {
            for (float y = -SCENE_SIZE / 2; y < SCENE_SIZE / 2; y += CUBE_SIZE)
            {
                for (float z = -SCENE_SIZE / 2; z < SCENE_SIZE / 2; z += CUBE_SIZE)
                {
                    Vector3 baseCorner = new Vector3(x, y, z);
                    byte cubeCase = 0;
                    List<float> fValues = new List<float>();
                    List<Vector3> currentCubeVertices = new List<Vector3>();

                    for (int i = 0; i < MarchingCubes.Tables._cubeVertices.Length; i++)
                    {
                        Vector3 vertex = baseCorner + MarchingCubes.Tables._cubeVertices[i] * CUBE_SIZE;
                        float fValue = Field.F(vertex);
                        if (fValue > 0)
                        {
                            cubeCase |= (byte)(1 << i);
                        }
                        currentCubeVertices.Add(vertex);
                        fValues.Add(fValue);
                    }

                    byte trianglesCount = MarchingCubes.Tables.CaseToTrianglesCount[cubeCase];
                    int3[] triangles = MarchingCubes.Tables.CaseToVertices[cubeCase];

                    for (int i = 0; i < trianglesCount; i++)
                    {
                        int3 triangleEdges = triangles[i];

                        for (int j = 0; j < 3; j++)
                        {
                            Vector3 interpolatedPosition = CalculateInterpolatedPosition(
                                triangleEdges[j], currentCubeVertices, fValues);
                            Vector3 normal = CalculateNormal(interpolatedPosition);

                            indices.Add(vertices.Count);
                            vertices.Add(interpolatedPosition);
                            normals.Add(normal);
                        }
                    }
                }
            }
        }

        // Here unity automatically assumes that vertices are points and hence (x, y, z) will be represented as (x, y, z, 1) in homogenous coordinates
        _mesh.Clear();
        _mesh.SetVertices(vertices);
        _mesh.SetTriangles(indices, 0);
        _mesh.SetNormals(normals);

        // Upload mesh data to the GPU
        _mesh.UploadMeshData(false);
    }

    private Vector3 CalculateInterpolatedPosition(
        int edgeNumber, List<Vector3> currentCubeVertices, List<float> fValues)
    {
        int[] edge = MarchingCubes.Tables._cubeEdges[edgeNumber];
        Vector3 A = currentCubeVertices[edge[0]];
        Vector3 B = currentCubeVertices[edge[1]];
        float fA = fValues[edge[0]];
        float fB = fValues[edge[1]];
        if (fA > 0)
        {
            Swap(ref A, ref B);
            Swap(ref fA, ref fB);
        }

        Vector3 interpolatedPosition = Vector3.Lerp(A, B, -fA / (fB - fA));
        return interpolatedPosition;
    }

    private Vector3 CalculateNormal(Vector3 position)
    {
        Vector3 dx = new Vector3(DELTA, 0, 0);
        Vector3 dy = new Vector3(0, DELTA, 0);
        Vector3 dz = new Vector3(0, 0, DELTA);
        float normal_x = Field.F(position + dx) - Field.F(position - dx);
        float normal_y = Field.F(position + dy) - Field.F(position - dy);
        float normal_z = Field.F(position + dz) - Field.F(position - dz);

        Vector3 normal = new Vector3(normal_x, normal_y, normal_z);
        normal.Normalize();
        normal *= -1;

        return normal;
    }

    private static void Swap<T>(ref T lhs, ref T rhs)
    {
        T temp;
        temp = lhs;
        lhs = rhs;
        rhs = temp;
    }
}