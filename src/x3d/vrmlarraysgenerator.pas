{
  Copyright 2002-2011 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Generating TGeometryArrays for VRML/X3D shapes (TVRMLArraysGenerator). }
unit VRMLArraysGenerator;

interface

uses Shape, VRMLNodes, VRMLFields, CastleUtils, GeometryArrays, VectorMath;

type
  TRadianceTransferFunction = function (Node: TAbstractGeometryNode;
    RadianceTransfer: PVector3Single;
    const RadianceTransferCount: Cardinal): TVector3Single of object;

  { Callback used by TVRMLRenderingAttributes.OnVertexColor.
    Passed here VertexPosition is in local coordinates (that is,
    local of this object, multiply by State.Transform to get scene coords).
    VertexIndex is the direct index to Node.Coordinates. }
  TVertexColorFunction = procedure (var Color: TVector3Single;
    Shape: TShape; const VertexPosition: TVector3Single;
    VertexIndex: Integer) of object;

  { Generate TGeometryArrays for a VRML/X3D shape. This is the basis
    of our renderer: generate a TGeometryArrays for a shape,
    then TVRMLGLRenderer will pass TGeometryArrays to OpenGL.

    Geometry must be based on coordinates when using this,
    that is TAbstractGeometryNode.Coord must return @true. }
  TVRMLArraysGenerator = class
  private
    FShape: TShape;
    FState: TVRMLGraphTraverseState;
    FGeometry: TAbstractGeometryNode;

    FCurrentRangeNumber: Cardinal;
    FCoord: TMFVec3f;
    FCoordIndex: TMFLong;

    { How Geometry and State are generated from Shape.
      We have to record it, to use with Shape.Normals* later. }
    OverTriangulate: boolean;
  protected
    { Indexes, only when Arrays.Indexes = nil but original node was indexed. }
    IndexesFromCoordIndex: TLongIntList;

    { Index to Arrays. Suitable always to index Arrays.Position / Color / Normal
      and other Arrays attribute arrays. Calculated in
      each TAbstractCoordinateGenerator.GenerateVertex,
      always call "inherited" first fro GenerateVertex overrides.

      There are three cases:

      1. When CoordIndex <> nil (so we have indexed node) and
         Arrays.Indexes <> nil (so we can render it by indexes,
         because AllowIndexed = true) then it's an index to
         node coordinates. It's equivalent to CoordIndex[IndexNum],
         and it can be used to index node's Coord as well as Arrays.Position
         (since they are ordered the same in this case).

      2. When CoordIndex <> nil (so we have indexed node) and
         Arrays.Indexes = nil (so we cannot render it by indexes,
         because AllowIndexed = false) then it's a number of vertex,
         that is it's incremented in each TAbstractCoordinateGenerator.GenerateVertex
         call.

         In this case IndexesFromCoordIndex <> nil,
         and Arrays attributes have the same count as IndexesFromCoordIndex.Count.
         GenerateVertex must be called in exactly the same order
         as IndexesFromCoordIndex were generated for this.

      3. When CoordIndex = nil (so we don't have an indexed node,
         also Arrays.Indexes = IndexesFromCoordIndex = nil always in this case)
         then it's an index to attributes. This is the trivial case,
         as Arrays attributes are then ordered just like node's Coord.
         It's equal to IndexNum then.
    }
    ArrayIndexNum: Integer;

    { Generated TGeometryArrays instance, available inside GenerateCoordinate*. }
    Arrays: TGeometryArrays;

    { Current shape properties, constant for the whole
      lifetime of the generator, set in constructor.
      @groupBegin }
    property Shape: TShape read FShape;
    property State: TVRMLGraphTraverseState read FState;
    property Geometry: TAbstractGeometryNode read FGeometry;
    { @groupEnd }

    procedure WarningShadingProblems(
      const ColorPerVertex, NormalPerVertex: boolean);

    { Coordinates, taken from Geometry.Coord.
      Usually coming from (coord as Coordinate).points field.
      If @nil then nothing will be rendered.

      In our constructor we initialize Coord and CoordIndex
      from Geometry, using TAbstractGeometryNode.Coord and
      TAbstractGeometryNode.CoordIndex values. }
    property Coord: TMFVec3f read FCoord;

    { Coordinate index, taken from Geometry.CoordIndex.

      If @nil, then GenerateVertex (and all other
      routines taking some index) will just directly index Coord
      (this is useful for non-indexed geometry, like TriangleSet
      instead of IndexedTriangleSet). }
    property CoordIndex: TMFLong read FCoordIndex;

    { Generate arrays content for given vertex.
      Given IndexNum indexes Coord, or (if CoordIndex is assigned)
      indexes CoordIndex (and CoordIndex then indexes actual Coord). }
    procedure GenerateVertex(IndexNum: Integer); virtual;

    { Get vertex coordinate. Returned vertex is in local coordinate space
      (use State.Transform if you want to get global coordinates). }
    function GetVertex(IndexNum: integer): TVector3Single;

    { Count of indexes. You can pass index between 0 and CoordCount - 1
      to various methods taking an index, like GenerateVertex. }
    function CoordCount: Integer;

    { Generate contents of Arrays.
      These are all called only when Coord is assigned.

      GenerateCoordinate can be overridden only by the class
      that actually knows how to deconstruct (triangulate etc.) this node.
      It must call GenerateVertex (or call GenerateCoordsRange,
      that has to be then overridden to call GenerateVertex after inherited).

      GenerateCoordinateBegin, GenerateCoordinateEnd will be called
      before / after GenerateCoordinate. It's useful to override them for
      intermediate classes in this file, that cannot triangulate,
      but still want to add something before / after GenerateCoordinate.
      When overriding GenerateCoordinateBegin, always call inherited
      at the begin. When overriding GenerateCoordinateEnd, always call inherited
      at the end.
      @groupBegin }
    procedure GenerateCoordinate; virtual; abstract;
    procedure GenerateCoordinateBegin; virtual;
    procedure GenerateCoordinateEnd; virtual;
    { @groupEnd }

    { Generate arrays content for one coordinate range (like a face).
      This is not called, not used, anywhere in this base
      TAbstractCoordinateGenerator class.
      In descendants, it may be useful to use this, like
      Geometry.MakeCoordRanges(State, @@GenerateCoordsRange).

      GenerateCoordsRange is supposed to generate the parts of the mesh
      between BeginIndex and EndIndex - 1 vertices.
      BeginIndex and EndIndex are indexes to CoordIndex array,
      if CoordIndex is assigned, or just indexes to Coord. }
    procedure GenerateCoordsRange(
      const RangeNumber: Cardinal;
      BeginIndex, EndIndex: Integer); virtual;

    { The number of current range (like a face), equal to RangeNumber passed to
      GenerateCoordsRange. Read this only while in GenerateCoordsRange.
      In fact, this is just set by GenerateCoordsRange in this class
      (so call @code(inherited) first when overriding it).

      It's comfortable e.g. when you need RangeNumber inside GenerateVertex,
      and you know that GenerateVertex will be called only from
      GenerateCoordsRange. }
    property CurrentRangeNumber: Cardinal read FCurrentRangeNumber;

    { If CoordIndex assigned (this VRML/X3D node is IndexedXxx)
      then calculate and set IndexesFromCoordIndex here.
      This is also the place to set Arrays.Primitive and Arrays.Counts. }
    procedure PrepareIndexesPrimitives; virtual; abstract;

    { Called when constructing Arrays, before the Arrays.Count is set.
      Descendants can override this to do stuff like Arrays.AddColor or
      Arrays.AddAttribute('foo'). Descendants can also set AllowIndexed
      to @false, if we can't use indexed rendering (because e.g. we have
      colors per-face, which means that the same vertex position may have
      different colors,  which means it has to be duplicated in arrays anyway,
      so there's no point in indexing). }
    procedure PrepareAttributes(var AllowIndexed: boolean); virtual;
  public
    { Assign these before calling GenerateArrays.
      @groupBegin }
    TexCoordsNeeded: Cardinal;
    MaterialOpacity: Single;
    FogVolumetric: boolean;
    FogVolumetricDirection: TVector3Single;
    FogVolumetricVisibilityStart: Single;
    ShapeBumpMappingUsed: boolean;
    OnRadianceTransfer: TRadianceTransferFunction;
    OnVertexColor: TVertexColorFunction;
    { Do we need TGeometryArrays.Faces }
    FacesNeeded: boolean;
    { @groupEnd }

    constructor Create(AShape: TShape; AOverTriangulate: boolean); virtual;

    { Create and generate Arrays contents. }
    function GenerateArrays: TGeometryArrays;

    class function BumpMappingAllowed: boolean; virtual;
  end;

  TVRMLArraysGeneratorClass = class of TVRMLArraysGenerator;

{ TVRMLArraysGenerator class suitable for given geometry.
  Returns @nil if not suitable generator for this node,
  which means that this node cannot be rendered through TGeometryArrays. }
function ArraysGenerator(AGeometry: TAbstractGeometryNode): TVRMLArraysGeneratorClass;

implementation

uses SysUtils, CastleLog, FGL {$ifdef VER2_2}, FGLObjectList22 {$endif},
  Boxes3D, Triangulator, CastleStringUtils, FaceIndex, CastleWarnings;

{ Copying to interleaved memory utilities ------------------------------------ }

type
  EAssignInterleavedRangeError = class(Exception);

{ Copy Source contents to given Target memory. Each item in Target
  is separated by the Stride bytes.

  We copy CopyCount items (you usually want to pass the count of Target
  data here). Source.Count must be >= CopyCount,
  we check it and eventually raise EAssignInterleavedRangeError.

  Warning: this is safely usable only for arrays of types that don't
  require initialization / finalization. Otherwise target memory data
  will be properly referenced.

  @raises EAssignInterleavedRangeError When Count < CopyCount. }
procedure AssignToInterleaved(Source: TFPSList; Target: Pointer;
  const Stride, CopyCount: Cardinal); forward;

{ Copy Source contents to given Target memory. Each item in Target
  is separated by the Stride bytes.

  We copy CopyCount items (you usually want to pass the count of Target
  data here). Indexes.Count must be >= CopyCount,
  we check it and eventually raise EAssignInterleavedRangeError.

  Item number I is taken from Items[Indexes[I]].
  All values on Indexes list must be valid (that is >= 0 and < Source.Count),
  or we raise EAssignInterleavedRangeError.

  Warning: this is safely usable only for arrays of types that don't
  require initialization / finalization. Otherwise target memory data
  will be properly referenced.

  @raises(EAssignInterleavedRangeError When Indexes.Count < CopyCount,
    or some index points outside of array.) }
procedure AssignToInterleavedIndexed(Source: TFPSList; Target: Pointer;
  const Stride, CopyCount: Cardinal; Indexes: TLongIntList); forward;

procedure AssignToInterleaved(Source: TFPSList; Target: Pointer;
  const Stride, CopyCount: Cardinal);
var
  I: Integer;
  SourcePtr: Pointer;
begin
  if Source.Count < CopyCount then
    raise EAssignInterleavedRangeError.CreateFmt('Not enough items: %d, but at least %d required',
      [Source.Count, CopyCount]);

  SourcePtr := Source.List;
  for I := 0 to CopyCount - 1 do
  begin
    Move(SourcePtr^, Target^, Source.ItemSize);
    PtrUInt(SourcePtr) += Source.ItemSize;
    PtrUInt(Target) += Stride;
  end;
end;

procedure AssignToInterleavedIndexed(Source: TFPSList; Target: Pointer;
  const Stride, CopyCount: Cardinal; Indexes: TLongIntList);
var
  I: Integer;
  Index: LongInt;
begin
  if Indexes.Count < CopyCount then
    raise EAssignInterleavedRangeError.CreateFmt('Not enough items: %d, but at least %d required',
      [Indexes.Count, CopyCount]);

  for I := 0 to CopyCount - 1 do
  begin
    Index := Indexes.L[I];
    if (Index < 0) or
       (Index >= Source.Count) then
      raise EAssignInterleavedRangeError.CreateFmt('Invalid index: %d, but we have %d items',
        [Index, Source.Count]);

    { Beware to not make multiplication below (* ItemSize) using 64-bit ints.
      This would cause noticeable slowdown when using AssignToInterleavedIndexed
      for VRMLArraysGenerator, that in turn affects dynamic scenes
      and especially dynamic shading like radiance_transfer. }
    Move(Pointer(PtrUInt(Source.List) + PtrUInt(Index) * PtrUInt(Source.ItemSize))^,
      Target^, Source.ItemSize);
    PtrUInt(Target) += Stride;
  end;
end;

{ classes -------------------------------------------------------------------- }

type
  TTextureCoordsImplementation = (
    { Texture coords not generated, because not needed by Renderer. }
    tcNotGenerated,
    { All texture coords (on all texture units, for multi-texturing)
      are automatically generated.

      Actually we could use some other value
      like tcTexIndexed (anything else than tcNotGenerated) to indicate
      this, since for everything <> tcNotGenerated we actually check
      TexCoordGen to know if coords should be explicit or automatic.
      But using special tcAllGenerated feels cleaner. }
    tcAllGenerated,
    { IndexNum is an index to TexCoordIndex, as this indexes TexCoordGen/Array[TextureUnit]. }
    tcTexIndexed,
    { IndexNum is an index to CoordIndex, as this indexes TexCoordGen/Array[TextureUnit]. }
    tcCoordIndexed,
    { IndexNum is a direct index to TexCoordGen/Array[TextureUnit]. }
    tcNonIndexed);

  { Handle texture coordinates.

    Usage:

    - TexCoord is already set from TAbstractGeometryNode.TexCoord,
      so just be sure it's overriden for your Geometry node class.

      Don't worry, we will automatically check TexCoord class,
      and do something useful with it only if we can.
      When TexCoord = @nil,
      then we'll generate default texture coordinates,
      following VRML 2.0 / X3D IndexedFaceSet default texture coord algorithm.

      (X3D spec doesn't say what happens for nodes like
      IndexedTriangleSet when texture is specified (in Appearance.texture)
      but texture coords are not present.
      For now, we just generate texture coords for them just like for
      IndexedFaceSet.)

    - Set TexCoordIndex, if available. This works just like CoordIndex:

      If @nil, then GenerateVertex (and all other
      routines taking some index) will just directly index TexCoord
      (this is useful for non-indexed geometry, like TriangleSet
      instead of IndexedTriangleSet). Otherwise, they will index TexCoordIndex,
      and then TexCoordIndex provides index to TexCoord.

      As a special case, if TexCoordIndex is assigned but empty
      (actually, just checked as "shorter than CoordIndex")
      then IndexNum indexed CoordIndex. So CoordIndex acts as
      TexCoordIndex in this case. This case is specially for
      for IndexedFaceSet in VRML >= 2.0.

      Always when TexCoordIndex is non-nil, also make sure that CoordIndex
      is non-nil. When TexCoordIndex is nil, make sure that CoordIndex is nil.
      (This restriction may be removed in the future,
      but for now nothing needs it.)

    This class takes care to generate tex coords, or use supplied
    TexCoord and TexCoordIndex. At least for texture units in
    TexCoordsNeeded (although we may pass some more, will be unused).
    So you do not have to generate any texture coordinates
    in descendants. Everything related to textures is already
    handled in this class. }
  TAbstractTextureCoordinateGenerator = class(TVRMLArraysGenerator)
  private
    TexImplementation: TTextureCoordsImplementation;

    { Source of explicit texture coordinates, for each texture unit
      that has Arrays.TexCoord[I].Generation = tgExplicit.
      The value of Arrays.TexCoord[I].Dimensions determines
      which of these is actually used.

      These arrays have always exactly the same length,
      equal to Arrays.TexCoords.Count. }
    TexCoordArray2d: array of TMFVec2f;
    TexCoordArray3d: array of TMFVec3f;
    TexCoordArray4d: array of TMFVec4f;

    TexCoord: TX3DNode;
  protected
    TexCoordIndex: TMFLong;

    { Return texture coordinate for given vertex, identified by IndexNum.
      IndexNum indexes TexCoordGen/Array[TextureUnit], or TexCoordIndex
      (if TexCoordIndex assigned),
      or CoordIndex (if TexCoordIndex assigned but empty, for IndexedFaceSet).

      Returns @false if no texture coords are available, for given
      TextureUnit.

      Works in all cases when we actually render some texture.

      Overloaded version with only TVector2Single just ignores the 3rd and
      4th texture coordinate, working only when texture coord is
      normal 2D coord. }
    function GetTextureCoord(IndexNum: integer;
      const TextureUnit: Cardinal; out Tex: TVector4Single): boolean;
    function GetTextureCoord(IndexNum: integer;
      const TextureUnit: Cardinal; out Tex: TVector2Single): boolean;

    procedure PrepareAttributes(var AllowIndexed: boolean); override;

    procedure GenerateVertex(IndexNum: Integer); override;

    procedure GenerateCoordinateBegin; override;
  public
    constructor Create(AShape: TShape; AOverTriangulate: boolean); override;
  end;

  TMaterials1Implementation = (miOverall,
    miPerVertexCoordIndexed,
    miPerVertexMatIndexed,
    miPerFace,
    miPerFaceMatIndexed);

  { Handle per-face or per-vertex VRML 1.0 materials.

    Usage:
    - Just set MaterialIndex and MaterialBinding using your node's fields.
      Call UpdateMat1Implementation afterwards.
    - For VRML >= 2.0 nodes, you don't have to do anything.
      You can just leave MaterialBinding as default BIND_DEFAULT,
      but it really doesn't matter: the only effect of this class
      are calls to Render_BindMaterial_1. And Render_BindMaterial_1
      simply does nothing for VRML >= 2.0 geometry nodes.

    Since this must have a notion of what "face" is, it assumes that
    your GenerateCoordsRange constitutes rendering of a single face.
    If this isn't true, then "per face" materials will not work
    correctly.

    Note that "per vertex" materials require smooth shading,
    so you should set this in your Render. There's no way to implement
    them with flat shading.

    Everything related to VRML 1.0 materials is already handled in this class. }
  TAbstractMaterial1Generator = class(TAbstractTextureCoordinateGenerator)
  private
    { Must be set in constructor. MaterialsBegin (may someday) depend on this.

      For this reason, call UpdateMat1Implementation inside descendant
      constructor after changing this. }
    Mat1Implementation: TMaterials1Implementation;
    FaceMaterial1Color: TVector4Single;
    function GetMaterial1Color(const MaterialIndex: Integer): TVector4Single;
  protected
    { You can leave MaterialIndex as nil if you are sure that
      MaterialBinding will not be any _INDEXED value.

      Be sure to change these only inside constructor,
      and call UpdateMat1Implementation afterwards. We want Mat1Implementation
      ready after constructor. }
    MaterialIndex: TMFLong;
    MaterialBinding: Integer;
    procedure UpdateMat1Implementation;

    procedure PrepareAttributes(var AllowIndexed: boolean); override;
    procedure GenerateVertex(IndexNum: Integer); override;
    procedure GenerateCoordsRange(const RangeNumber: Cardinal;
      BeginIndex, EndIndex: integer); override;
  public
    constructor Create(AShape: TShape; AOverTriangulate: boolean); override;
  end;

  { Handle per-face or per-vertex VRML >= 2.0 colors.

    - Usage: set Color or ColorRGBA (at most one of them), ColorPerVertex,
      ColorIndex.

      If Color and ColorRGBA = @nil, this class will not do anything.
      Otherwise, colors will be used.

      ColorPerVertex specifies per-vertex or per-face.
      Just like for VRML 1.0, the same restrictions apply:
      - if you want per-face to work, then GenerateCoordsRange must
        correspond to a single face.
      - if you want per-vertex to work, you must use smooth shading.

      ColorIndex: if set and non-empty, then vertex IndexNum or face number will
      index ColorIndex, and then ColorIndex indexes Color items.
      Otherwise, for vertex we use CoordIndex (if assigned, otherwise it directly
      accesses colors)
      and for face we'll use just face number.

    - We also handle RadianceTransfer for all X3DComposedGeometryNode
      descendants. If set, and non-empty,
      and OnRadianceTransfer is defined, we will use it.

      We will then ignore Color, ColorRGBA, ColorPerVertex, ColorIndex
      settings --- only the colors returned by OnRadianceTransfer
      will be used.

    - Attributes.OnVertexColor, if assigned,
      will be automatically used here to calculate color for each vertex.
      If this will be assigned, then the above things
      (Color, ColorRGBA, ColorPerVertex, ColorIndex, RadianceTransfer)
      will be ignored -- only the colors returned by OnVertexColor will
      be used.

    Everything related to setting VRML 2.0
    material should be set in Render_MaterialsBegin, and everything
    related to VRML 2.0 colors is handled in this class.
    So in summary, this class takes care of everything related to
    materials / colors. }
  TAbstractColorGenerator = class(TAbstractMaterial1Generator)
  private
    RadianceTransferVertexSize: Cardinal;
    RadianceTransfer: TVector3SingleList;
    FaceColor: TVector4Single;
  protected
    Color: TMFVec3f;
    ColorRGBA: TMFColorRGBA;
    ColorPerVertex: boolean;
    ColorIndex: TMFLong;

    procedure PrepareAttributes(var AllowIndexed: boolean); override;
    procedure GenerateVertex(IndexNum: integer); override;
    procedure GenerateCoordsRange(const RangeNumber: Cardinal;
      BeginIndex, EndIndex: Integer); override;
  end;

  TNormalsImplementation = (
    { Do nothing about normals (in TAbstractNormalGenerator)
      class. Passing normals to OpenGL is left for descendants. }
    niNone,
    { The first item of Normals specifies the one and only normal
      for the whole geometry. }
    niOverall,
    { Each vertex has it's normal vector, IndexNum specifies direct index
      to Normals. }
    niPerVertexNonIndexed,
    { Each vertex has it's normal vector, IndexNum specifies index to
      CoordIndex and this is an index to Normals. }
    niPerVertexCoordIndexed,
    { Each vertex has it's normal vector, IndexNum specifies index to
      NormalIndex and this is an index to Normals. }
    niPerVertexNormalIndexed,
    { Face number is the index to Normals. }
    niPerFace,
    { Face number is the index to NormalIndex, and this indexes Normals. }
    niPerFaceNormalIndexed);

  { Handle normals, both taken from user data (that is, stored in VRML file)
    and generated.

    Usage:

    - You have to set NorImplementation in descendant.
      Default value, NorImplementation = niNone, simply means that
      this class does nothing and it's your responsibility to generate
      and use normal vectors. See TNormalsImplementation for other meanings,
      and which properties from
        Normals
        NormalsCcw (should always be set when setting Normals)
        NormalIndex
      you also have to assign to make them work.

      For VRML 1.0, you most definitely want to set both Normals
      and NormalIndex and then call NorImplementation :=
      NorImplementationFromVRML1Binding. This should take care of
      VRML 1.0 needs completely.

    - If and only if NorImplementation = niNone (either you left it as
      default, or NorImplementationFromVRML1Binding returned this,
      or you set this...)
      you have to make appropriate glNormal calls yourself.

      Normals should always point from CCW (you *do not* check here FrontFaceCcw
      field, as we *do not* call glFrontFace anywhere).

      If NorImplementation <> niNone then we handle everything
      related to normals in this class.

    Note that PerVertexXxx normals require smooth shading to work Ok. }
  TAbstractNormalGenerator = class(TAbstractColorGenerator)
  private
    { Will be set to Normals or it's inverted version, to keep
      pointing from CCW. }
    CcwNormals: TVector3SingleList;
    FaceNormal: TVector3Single;
    function CcwNormalsSafe(const Index: Integer): TVector3Single;
  protected
    NormalIndex: TMFLong;
    Normals: TVector3SingleList;
    NormalsCcw: boolean;

    { This is calculated in constructor. Unlike similar TexImplementation
      (which is calculated only in GenerateCoordinateBegin).
      Reasons:
      - Descendants may want to change NorImplementation. In other words,
        full automatic detection only in TAbstractNormalGenerator
        is not done, it's possible in descendants to explicitly change this.
      - NodeLit uses this, so it must be available after creation and
        before rendering. }
    NorImplementation: TNormalsImplementation;

    function NorImplementationFromVRML1Binding(
      NormalBinding: Integer): TNormalsImplementation;

    { Returns normal vector for given vertex, identified by IndexNum
      (IndexNum has the same meaning as for GenerateVertex) and FaceNumber
      (since normals may be available per-face, we need to know face number
      as well as vertex number).

      Returns normal always from
      CCW (just like we pass to OpenGL always CCW normals, since we always
      assume front face = CCW).

      Override this in descendants only to handle
      NorImplementation = niNone case. }
    procedure GetNormal(IndexNum: Integer; RangeNumber: Integer;
      out N: TVector3Single); virtual;

    { If @true, then it's guaranteed that normals for the same face will
      be equal. This may be useful for various optimization purposes.

      Override this in descendants only to handle
      NorImplementation = niNone case. The implementation in this class
      just derives it from NorImplementation, and for niNone answers @false
      (safer answer). }
    function NormalsFlat: boolean; virtual;

    procedure GenerateCoordinateBegin; override;
    procedure GenerateCoordinateEnd; override;
    procedure GenerateCoordsRange(const RangeNumber: Cardinal;
      BeginIndex, EndIndex: Integer); override;

    procedure PrepareAttributes(var AllowIndexed: boolean); override;

    procedure GenerateVertex(IndexNum: Integer); override;
  end;

  { Handle fog coordinate.
    Descendants don't have to do anything, this just works
    (using TAbstractGeometryNode.FogCoord). }
  TAbstractFogGenerator = class(TAbstractNormalGenerator)
  private
    FogCoord: TSingleList;
  protected
    procedure PrepareAttributes(var AllowIndexed: boolean); override;
    procedure GenerateVertex(IndexNum: Integer); override;
  public
    constructor Create(AShape: TShape; AOverTriangulate: boolean); override;
  end;

  TX3DVertexAttributeNodes = specialize TFPGObjectList<TAbstractVertexAttributeNode>;

  { Handle GLSL attributes from VRML/X3D "attrib" field.
    Descendants don't have to do anything, this just works
    (using TAbstractGeometryNode.Attrib). }
  TAbstractShaderAttribGenerator = class(TAbstractFogGenerator)
  private
    Attrib: TX3DVertexAttributeNodes;
  protected
    procedure PrepareAttributes(var AllowIndexed: boolean); override;
    procedure GenerateVertex(IndexNum: Integer); override;
  public
    constructor Create(AShape: TShape; AOverTriangulate: boolean); override;
    destructor Destroy; override;
  end;

  { Handle bump mapping.

    Descendants should:
    - override BumpMappingAllowed to return true,
    - call CalculateTangentVectors when needed.
    - Also make sure that GetNormal always
      works (since it's called by CalculateTangentVectors),
      so if you may use NorImplementation = niNone: be sure to override
      GetNormal to return correct normal. }
  TAbstractBumpMappingGenerator = class(TAbstractShaderAttribGenerator)
  private
    { Helpers for bump mapping }
    HasTangentVectors: boolean;
    STangent, TTangent: TVector3Single;
  protected
    procedure GenerateVertex(IndexNum: Integer); override;
    procedure PrepareAttributes(var AllowIndexed: boolean); override;

    { Update tangent vectors (HasTangentVectors, STangent, TTangent).
      Without this, bump mapping will be wrong.
      Give triangle indexes (like IndexNum for GenerateVertex). }
    procedure CalculateTangentVectors(
      const TriangleIndex1, TriangleIndex2, TriangleIndex3: Integer);
  end;

  { Most complete implementation of arrays generator,
    should be used to derive non-abstract renderers for nodes. }
  TAbstractCompleteGenerator = TAbstractBumpMappingGenerator;

{ TVRMLArraysGenerator ------------------------------------------------------ }

constructor TVRMLArraysGenerator.Create(AShape: TShape; AOverTriangulate: boolean);
begin
  inherited Create;

  FShape := AShape;
  OverTriangulate := AOverTriangulate;
  FGeometry := FShape.Geometry(OverTriangulate);
  FState := FShape.State(OverTriangulate);

  Check(Geometry.Coord(State, FCoord),
    'TAbstractCoordinateRenderer is only for coordinate-based nodes');
  FCoordIndex := Geometry.CoordIndex;
end;

procedure TVRMLArraysGenerator.WarningShadingProblems(
  const ColorPerVertex, NormalPerVertex: boolean);
const
  SPerVertex: array [boolean] of string = ('per-face', 'per-vertex');
begin
  OnWarning(wtMajor, 'VRML/X3D', Format(
    'Colors %s and normals %s used in the same node %s. Shading results may be incorrect',
    [ SPerVertex[ColorPerVertex], SPerVertex[NormalPerVertex],
      Geometry.NodeTypeName]));
end;

function TVRMLArraysGenerator.GenerateArrays: TGeometryArrays;
var
  AllowIndexed: boolean;
  MaxIndex: Integer;
begin
  Arrays := TGeometryArrays.Create;
  Result := Arrays;

  { no geometry if coordinates are empty. Leave empty Arrays. }
  if Coord = nil then Exit;

  { initialize stuff for generating }
  IndexesFromCoordIndex := nil;
  try
    ArrayIndexNum := -1;

    PrepareIndexesPrimitives;

    { Assert about Arrays.Counts.Sum. Note that even when
      IndexesFromCoordIndex = nil, Arrays.Counts.Sum should usually be equal
      to final Arrays.Count. But not always: it may not be equal
      for invalid nodes, with non-complete triangle strips / fans etc.
      (then Arrays.Counts will not contain all coordinates). }
    Assert(
      (Arrays.Counts = nil) or
      (IndexesFromCoordIndex = nil) or
      (Arrays.Counts.Sum = IndexesFromCoordIndex.Count) );

    if IndexesFromCoordIndex <> nil then
    begin
      Assert(CoordIndex <> nil);
      MaxIndex := IndexesFromCoordIndex.Max;

      { check do we have enough coordinates. TGeometryArrays data may be passed
        quite raw to OpenGL, so this may be our last chance to check correctness
        and avoid passing data that would cause OpenGL errors. }
      if MaxIndex >= Coord.Count then
      begin
        CoordIndex.OnWarning_WrongVertexIndex(Geometry.NodeTypeName,
          MaxIndex, Coord.Count);
        Exit; { leave Arrays created but empty }
      end;
    end;

    AllowIndexed := true;
    PrepareAttributes(AllowIndexed);

    try
      if Log then
        WritelnLog('Renderer', Format('Shape %s is rendered with indexes: %s',
          [Shape.NiceName, BoolToStr[AllowIndexed]]));

      if AllowIndexed or (IndexesFromCoordIndex = nil) then
      begin
        Arrays.Indexes := IndexesFromCoordIndex;
        IndexesFromCoordIndex := nil;

        Arrays.Count := Coord.Count;

        AssignToInterleaved(Coord.Items, Arrays.Position, Arrays.CoordinateSize, Arrays.Count);
      end else
      begin
        Arrays.Count := IndexesFromCoordIndex.Count;

        { Expand IndexesFromCoordIndex, to specify vertexes multiple times }
        AssignToInterleavedIndexed(Coord.Items, Arrays.Position, Arrays.CoordinateSize, Arrays.Count, IndexesFromCoordIndex);
      end;

      GenerateCoordinateBegin;
      try
        GenerateCoordinate;
      finally GenerateCoordinateEnd; end;
    except
      on E: EAssignInterleavedRangeError do
        OnWarning(wtMajor, 'VRML/X3D', Format('Invalid number of items in a normal or texture coordinate array for shape "%s": %s',
          [Shape.NiceName, E.Message]));
    end;
  finally FreeAndNil(IndexesFromCoordIndex); end;
end;

procedure TVRMLArraysGenerator.PrepareAttributes(var AllowIndexed: boolean);
begin
  if Geometry is TAbstractComposedGeometryNode then
  begin
    Arrays.CullBackFaces := (Geometry as TAbstractComposedGeometryNode).FdSolid.Value;
    Arrays.FrontFaceCcw := (Geometry as TAbstractComposedGeometryNode).FdCcw.Value;
  end;
end;

procedure TVRMLArraysGenerator.GenerateCoordinateBegin;
begin
  { nothing to do in this class }
end;

procedure TVRMLArraysGenerator.GenerateCoordinateEnd;
begin
  { nothing to do in this class }
end;

procedure TVRMLArraysGenerator.GenerateVertex(IndexNum: integer);
begin
  if CoordIndex <> nil then
  begin
    if Arrays.Indexes = nil then
      Inc(ArrayIndexNum) else
      ArrayIndexNum := CoordIndex.Items.L[IndexNum];
  end else
    ArrayIndexNum := IndexNum;
end;

function TVRMLArraysGenerator.GetVertex(IndexNum: integer): TVector3Single;
begin
  { This assertion should never fail, it's the responsibility
    of the programmer. }
  Assert(IndexNum < CoordCount);

  if CoordIndex <> nil then
    Result := Coord.ItemsSafe[CoordIndex.Items.L[IndexNum]] else
    Result := Coord.Items.L[IndexNum];
end;

function TVRMLArraysGenerator.CoordCount: Integer;
begin
  if CoordIndex <> nil then
    Result := CoordIndex.Items.Count else
    Result := Coord.Items.Count;
end;

procedure TVRMLArraysGenerator.GenerateCoordsRange(
  const RangeNumber: Cardinal; BeginIndex, EndIndex: Integer);
begin
  FCurrentRangeNumber := RangeNumber;
end;

class function TVRMLArraysGenerator.BumpMappingAllowed: boolean;
begin
  Result := false;
end;

{ TAbstractTextureCoordinateGenerator ----------------------------------------- }

constructor TAbstractTextureCoordinateGenerator.Create(AShape: TShape; AOverTriangulate: boolean);
begin
  inherited;
  if not Geometry.TexCoord(State, TexCoord) then
    TexCoord := nil;
end;

procedure TAbstractTextureCoordinateGenerator.PrepareAttributes(
  var AllowIndexed: boolean);

  { Is a texture used on given unit, and it's 3D texture. }
  function IsTexture3D(const TexUnit: Cardinal): boolean;

    { Knowing that Tex is not nil,
      check is it a single (not MultiTexture) 3D texture. }
    function IsSingleTexture3D(Tex: TX3DNode): boolean;
    begin
      Result :=
         (Tex is TAbstractTexture3DNode) or
        ((Tex is TShaderTextureNode) and
         (TShaderTextureNode(Tex).FdDefaultTexCoord.Value = 'BOUNDS3D'));
    end;

  var
    Tex: TAbstractTextureNode;
  begin
    Tex := State.Texture;
    Result := (
      (Tex <> nil) and
      ( ( (TexUnit = 0) and IsSingleTexture3D(Tex) )
        or
        ( (Tex is TMultiTextureNode) and
          (TMultiTextureNode(Tex).FdTexture.Count > TexUnit) and
          IsSingleTexture3D(TMultiTextureNode(Tex).FdTexture[TexUnit])
        )));
  end;

  { Set length of TexCoordArray* arrays. }
  procedure SetTexLengths(const Count: Integer);
  begin
    SetLength(TexCoordArray2d, Count);
    SetLength(TexCoordArray3d, Count);
    SetLength(TexCoordArray4d, Count);
  end;

  function Bounds2DTextureGenVectors: TTextureGenerationVectors;
  var
    LocalBBox: TBox3D;
    LocalBBoxSize: TVector3Single;

    { Setup and enable glTexGen to make automatic 2D texture coords
      based on shape bounding box. On texture unit 0. }
    procedure SetupCoordGen(out Gen: TVector4Single;
      const Coord: integer; const GenStart, GenEnd: Single);

    { We want to map float from range
        LocalBBox[0, Coord]...LocalBBox[0, Coord] + LocalBBoxSize[Coord]
      to
        GenStart...GenEnd.

      For a 3D point V let's define S1 as
        S1 = (V[Coord] - LocalBBox[0, Coord]) / LocalBBoxSize[Coord]
      and so S1 is in 0..1 range, now
        S = S1 * (GenEnd - GenStart) + GenStart
      and so S is in GenStart...GenEnd range, like we wanted.

      It remains to rewrite this to a form that we can pass to OpenGL
      glTexGenfv(..., GL_OBJECT_PLANE, ...).

        S = V[Coord] * (GenEnd - GenStart) / LocalBBoxSize[Coord]
           - LocalBBox[0, Coord] * (GenEnd - GenStart) / LocalBBoxSize[Coord]
           + GenStart

      Simple check: for GenStart = 0, GenEnd = 1 this simplifies to
        S = V[Coord] / LocalBBoxSize[Coord] -
            LocalBBox[0, Coord] / LocalBBoxSize[Coord]
          = (V[Coord] - LocalBBox[0, Coord]) / LocalBBoxSize[Coord]
          = S1
    }

    begin
      FillChar(Gen, SizeOf(Gen), 0);
      Gen[Coord] := (GenEnd - GenStart) / LocalBBoxSize[Coord];
      Gen[3] :=
        - LocalBBox.Data[0, Coord] * (GenEnd - GenStart) / LocalBBoxSize[Coord]
        + GenStart;
    end;

  var
    SCoord, TCoord: integer;
  begin
    LocalBBox := Shape.LocalBoundingBox;

    if not LocalBBox.IsEmpty then
    begin
      LocalBBoxSize := LocalBBox.Sizes;

      Geometry.GetTextureBounds2DST(LocalBBoxSize, SCoord, TCoord);

      { Calculate TextureGen[0..1]. }
      SetupCoordGen(Result[0], SCoord, 0, 1);
      SetupCoordGen(Result[1], TCoord, 0, LocalBBoxSize[TCoord] / LocalBBoxSize[SCoord]);
    end else
    begin
      { When local bounding box is empty, set these to any sensible value }
      Result[0] := Vector4Single(1, 0, 0, 0);
      Result[1] := Vector4Single(0, 1, 0, 0);
    end;

    Result[2] := Vector4Single(0, 0, 1, 0); //< whatever, just to be defined.
  end;

  function Bounds3DTextureGenVectors: TTextureGenerationVectors;
  var
    Box: TBox3D;
    XStart, YStart, ZStart, XSize, YSize, ZSize: Single;
  begin
    Box := Shape.LocalBoundingBox;

    if not Box.IsEmpty then
    begin
      { Texture S should range from 0..1 when X changes from X1 .. X2.
        So S = X / (X2 - X1) - X1 / (X2 - X1).
        Same for T.
        For R, X3D spec says that coords go backwards, so just SwapValues. }

      SwapValues(Box.Data[0][2], Box.Data[1][2]);

      XStart := Box.Data[0][0];
      YStart := Box.Data[0][1];
      ZStart := Box.Data[0][2];

      XSize := Box.Data[1][0] - Box.Data[0][0];
      YSize := Box.Data[1][1] - Box.Data[0][1];
      ZSize := Box.Data[1][2] - Box.Data[0][2];

      Result[0] := Vector4Single(1 / XSize, 0, 0, - XStart / XSize);
      Result[1] := Vector4Single(0, 1 / YSize, 0, - YStart / YSize);
      Result[2] := Vector4Single(0, 0, 1 / ZSize, - ZStart / ZSize);
    end else
    begin
      { When local bounding box is empty, set these to any sensible value }
      Result[0] := Vector4Single(1, 0, 0, 0);
      Result[1] := Vector4Single(0, 1, 0, 0);
      Result[2] := Vector4Single(0, 0, 1, 0);
    end;
  end;

  { Initialize Arrays.TexCoords and TexCoordArray2/3/4d, based on TexCoord.

    If any usable tex coords are found
    (that is, Arrays.TexCoords.Count <> 0 on exit) then this array
    contains at least TexCoordsNeeded units. }
  procedure InitializeTexCoordGenArray;

    { Add single texture coord configuration
      to Arrays.TexCoord and TexCoordArray2/3/4d.
      Assume that TexCoordArray2/3/4d already have required length.
      Pass any TexCoord node except TMultiTextureCoordinateNode. }
    procedure AddSingleTexCoord(const TextureUnit: Cardinal; TexCoord: TX3DNode);

      function TexCoordGenFromString(const S: string; const IsTexture3D: boolean): TTextureCoordinateGeneration;
      begin
        if S = 'SPHERE' then
          Result := tgSphereMap else
        if S = 'COORD' then
          Result := tgCoord else
        if (S = 'COORD-EYE') or (S = 'CAMERASPACEPOSITION') then
          Result := tgCoordEye else
        if S = 'CAMERASPACENORMAL' then
          Result := tgCameraSpaceNormal else
        if S = 'WORLDSPACENORMAL' then
          Result := tgWorldSpaceNormal else
        if S = 'CAMERASPACEREFLECTIONVECTOR' then
          Result := tgCameraSpaceReflectionVector else
        if S = 'WORLDSPACEREFLECTIONVECTOR' then
          Result := tgWorldSpaceReflectionVector else
        if S = 'PROJECTION' then
          Result := tgProjection else
        if S = 'BOUNDS' then
        begin
          if IsTexture3D then
            Result := tgBounds3d else
            Result := tgBounds2d;
        end else
        if S = 'BOUNDS2D' then
          Result := tgBounds2d else
        if S = 'BOUNDS3D' then
          Result := tgBounds3d else
        begin
          Result := tgCoord;
          OnWarning(wtMajor, 'VRML/X3D', Format('Unsupported TextureCoordinateGenerator.mode: "%s", will use "COORD" instead',
            [S]));
        end;
      end;

      { For tgProjection generation, calculate function that should be
        later used to calculate matrix to pass to glTexGen as eye plane.

        Gets projector matrices from a TextureCoordinateGenerator or
        ProjectedTextureCoordinate node.
        If this projector is a correct light source or viewpoint,
        then get it's projection and modelview matrix and return @true.
        Returns @false (and does correct OnWarning)
        if it's empty or incorrect. }
      function GetProjectorMatrixFunction(GeneratorNode: TX3DNode): TProjectorMatrixFunction;
      var
        ProjectorValue: TX3DNode; { possible ProjectorLight or ProjectorViewpoint }
      begin
        Result := nil;

        if GeneratorNode is TTextureCoordinateGeneratorNode then
        begin
          ProjectorValue := TTextureCoordinateGeneratorNode(GeneratorNode).FdProjectedLight.Value;
          if (ProjectorValue <> nil) and
             (ProjectorValue is TAbstractLightNode) then
          begin
            Result := @TAbstractLightNode(ProjectorValue).GetProjectorMatrix;
          end else
            OnWarning(wtMajor, 'VRML/X3D', 'Using TextureCoordinateGenerator.mode = "PROJECTION", but TextureCoordinateGenerator.projectedLight is NULL or incorrect');
        end else
        if GeneratorNode is TProjectedTextureCoordinateNode then
        begin
          ProjectorValue := TProjectedTextureCoordinateNode(GeneratorNode).FdProjector.Value;
          if (ProjectorValue <> nil) and
             (ProjectorValue is TAbstractLightNode) then
          begin
            Result := @TAbstractLightNode(ProjectorValue).GetProjectorMatrix;
          end else
          if (ProjectorValue <> nil) and
             (ProjectorValue is TAbstractX3DViewpointNode) then
          begin
            Result := @TAbstractX3DViewpointNode(ProjectorValue).GetProjectorMatrix;
          end else
            OnWarning(wtMajor, 'VRML/X3D', 'ProjectedTextureCoordinate.projector is NULL or incorrect');
        end else
          { This should not actually happen (GeneratorNode passed here should be like this) }
          OnWarning(wtMajor, 'VRML/X3D', 'Invalid texture generator node');
      end;

    begin
      if TexCoord is TTextureCoordinateNode then
      begin
        Arrays.AddTexCoord2D(TextureUnit);
        TexCoordArray2d[TextureUnit] := TTextureCoordinateNode(TexCoord).FdPoint;
      end else
      if TexCoord is TTextureCoordinate2Node_1 then
      begin
        Arrays.AddTexCoord2D(TextureUnit);
        TexCoordArray2d[TextureUnit] := TTextureCoordinate2Node_1(TexCoord).FdPoint;
      end else
      if TexCoord is TTextureCoordinate3DNode then
      begin
        Arrays.AddTexCoord3D(TextureUnit);
        TexCoordArray3d[TextureUnit] := TTextureCoordinate3DNode(TexCoord).FdPoint;
      end else
      if TexCoord is TTextureCoordinate4DNode then
      begin
        Arrays.AddTexCoord4D(TextureUnit);
        TexCoordArray4d[TextureUnit] := TTextureCoordinate4DNode(TexCoord).FdPoint;
      end else
      if TexCoord is TTextureCoordinateGeneratorNode then
      begin
        Arrays.AddTexCoordGenerated(
          TexCoordGenFromString(TTextureCoordinateGeneratorNode(TexCoord).FdMode.Value,
            IsTexture3D(TextureUnit)), TextureUnit);
      end else
      if TexCoord is TProjectedTextureCoordinateNode then
      begin
        Arrays.AddTexCoordGenerated(tgProjection, TextureUnit);
      end else
      begin
        { dummy default }
        Arrays.AddTexCoordGenerated(tgBounds2d, TextureUnit);
        if TexCoord <> nil then
          OnWarning(wtMajor, 'VRML/X3D', Format('Unsupported texture coordinate node: %s, inside multiple texture coordinate', [TexCoord.NodeTypeName])) else
          OnWarning(wtMajor, 'VRML/X3D', 'NULL texture coordinate node');
      end;

      { Calculate some Generation-specific values }
      case Arrays.TexCoords[TextureUnit].Generation of
        tgBounds2d: Arrays.TexCoords[TextureUnit].GenerationBoundsVector := Bounds2DTextureGenVectors;
        tgBounds3d: Arrays.TexCoords[TextureUnit].GenerationBoundsVector := Bounds3DTextureGenVectors;
        tgProjection: Arrays.TexCoords[TextureUnit].GenerationProjectorMatrix := GetProjectorMatrixFunction(TexCoord);
      end;
    end;

  var
    MultiTexCoord: TX3DNodeList;
    I, LastCoord: Integer;
  begin
    if TexCoord = nil then
    begin
      { Leave TexCoords.Count = 0, no OnWarning }
      Exit;
    end else
    if TexCoord is TMultiTextureCoordinateNode then
    begin
      MultiTexCoord := TMultiTextureCoordinateNode(TexCoord).FdTexCoord.Items;
      SetTexLengths(MultiTexCoord.Count);
      for I := 0 to MultiTexCoord.Count - 1 do
        AddSingleTexCoord(I, MultiTexCoord[I]);
    end else
    begin
      SetTexLengths(1);
      AddSingleTexCoord(0, TexCoord);
    end;

    Assert(Arrays.TexCoords.Count = Length(TexCoordArray2d));
    Assert(Arrays.TexCoords.Count = Length(TexCoordArray3d));
    Assert(Arrays.TexCoords.Count = Length(TexCoordArray4d));

    if (Arrays.TexCoords.Count <> 0) and
       (Arrays.TexCoords.Count < TexCoordsNeeded) then
    begin
      LastCoord := Arrays.TexCoords.Count - 1;
      SetTexLengths(TexCoordsNeeded);

      { We copy tex coord LastCoord values to all following items.
        This way we do what X3D spec says:
        - if non-MultiTextureCoordinate is used for multitexturing,
          channel 0 is replicated
        - if MultiTextureCoordinate is used, but with too few items,
          last channel is replicated. }
      for I := LastCoord + 1 to TexCoordsNeeded - 1 do
      begin
        Arrays.AddTexCoordCopy(I, LastCoord);
        TexCoordArray2d[I] := TexCoordArray2d[LastCoord];
        TexCoordArray3d[I] := TexCoordArray3d[LastCoord];
        TexCoordArray4d[I] := TexCoordArray4d[LastCoord];
      end;
    end;
  end;

  { Setup 2D texture coordinates suitable for IndexedFaceSet without
    explicit texture coords, following X3D 3D Texturing spec.
    We set texture generation to tgBounds2d
    on all texture units within TexCoordsNeeded.
    We also set TexImplementation := tcAllGenerated. }
  procedure Bounds2DTextureGen;
  var
    I: integer;
    TexGenVectors: TTextureGenerationVectors;
  begin
    TexGenVectors := Bounds2DTextureGenVectors;

    TexImplementation := tcAllGenerated;
    SetTexLengths(TexCoordsNeeded);
    for I := 0 to TexCoordsNeeded - 1 do
    begin
      Arrays.AddTexCoordGenerated(tgBounds2d, I);
      Arrays.TexCoords[I].GenerationBoundsVector := TexGenVectors;
    end;
  end;

  { Setup 3D texture coordinates suitable for "primitives without
    explicit texture coordinates", following X3D 3D Texturing spec.
    We set tgBounds3d on all texture units within TexCoordsNeeded.
    We also set TexImplementation := tcAllGenerated. }
  procedure Bounds3DTextureGen;
  var
    I: Integer;
    TexGenVectors: TTextureGenerationVectors;
  begin
    TexGenVectors := Bounds3DTextureGenVectors;

    TexImplementation := tcAllGenerated;
    SetTexLengths(TexCoordsNeeded);
    for I := 0 to TexCoordsNeeded - 1 do
    begin
      Arrays.AddTexCoordGenerated(tgBounds3d, I);
      Arrays.TexCoords[I].GenerationBoundsVector := TexGenVectors;
    end;
  end;

begin
  inherited;

  TexImplementation := tcNotGenerated;

  { Make sure they are initially empty. }
  Assert(Arrays.TexCoords.Count = 0);
  Assert(Length(TexCoordArray2d) = 0);
  Assert(Length(TexCoordArray3d) = 0);
  Assert(Length(TexCoordArray4d) = 0);

  if TexCoordsNeeded > 0 then
  begin
    if { Original shape node is a primitive, without explicit texCoord }
       Shape.OriginalGeometry.AutoGenerate3DTexCoords and
       { First texture is 3D texture }
       IsTexture3D(0) then
    begin
      Bounds3DTextureGen;
    end else

    { Handle VRML 1.0 case when TexCoord present but TexCoordIndex empty
      before calling InitializeTexCoordGenArray. That's because we have
      to ignore TexCoord in this case (so says VRML 1.0 spec, and it's
      sensible since for VRML 1.0 there is always some last TexCoord node).
      So we don't want to let InitializeTexCoordGenArray to call
      any Arrays.AddTexCoord. }
    if (State.ShapeNode = nil) and
       (TexCoordIndex <> nil) and
       (TexCoordIndex.Count < CoordIndex.Count) then
    begin
      Bounds2DTextureGen;
    end else

    begin
      InitializeTexCoordGenArray;
      if Arrays.TexCoords.Count > 0 then
      begin
        if TexCoordIndex = nil then
        begin
          { This happens only for X3D non-indexed primitives:
            Triangle[Fan/Strip]Set, QuadSet. Spec says that TexCoord should be
            used just like Coord, so IndexNum indexes it directly. }
          TexImplementation := tcNonIndexed;
          Assert(CoordIndex = nil);
        end else
        if TexCoordIndex.Count >= CoordIndex.Count then
        begin
          TexImplementation := tcTexIndexed;
        end else
        begin
          { If TexCoord <> nil (non-zero Arrays.TexCoords.Count guarantees this)
            but TexCoordIndex is empty then
            - VRML 2.0 spec says that coordIndex is used
              to index texture coordinates for IndexedFaceSet.
            - VRML 1.0 spec says that in this case default texture
              coordinates should be generated (that's because for
              VRML 1.0 there is always some TexCoord <> nil,
              so it cannot be used to produce different behavior).
              We handled this case in code above.
            - Note that this cannot happen at all for X3D primitives
              like IndexedTriangle[Fan/Strip]Set, QuadSet, since they
              have TexCoordIndex = CoordIndex (just taken from "index" field).
          }
          Assert(State.ShapeNode <> nil);
          TexImplementation := tcCoordIndexed;
        end;
      end else
        Bounds2DTextureGen;
    end;
  end;

  if TexImplementation in [tcTexIndexed, tcNonIndexed] then
    AllowIndexed := false;
end;

procedure TAbstractTextureCoordinateGenerator.GenerateCoordinateBegin;

  { Set explicit texture coordinates in Arrays,
    for texture units where Arrays.TexCoords[].Generation = tgExplicit.
    This is only for TexImplementation in [tcNonIndexed, tcCoordIndexed],
    other TexImplementation have to be handled elsewhere. }
  procedure EnableExplicitTexCoord;
  var
    I: Integer;

    procedure Handle(const Dimensions: TTexCoordDimensions;
      TexCoordArray: TFPSList);
    var
      A: Pointer;
    begin
      A := Arrays.TexCoord(Dimensions, I, 0);

      if TexImplementation = tcCoordIndexed then
      begin
        if Arrays.Indexes <> nil then
          AssignToInterleaved(TexCoordArray, A, Arrays.AttributeSize, Arrays.Count) else
          AssignToInterleavedIndexed(TexCoordArray, A, Arrays.AttributeSize, Arrays.Count, IndexesFromCoordIndex);
      end else
      begin
        Assert(TexImplementation = tcNonIndexed);
        Assert(CoordIndex = nil); { tcNonIndexed happens only for non-indexed triangle/quad primitives }
        Assert(Arrays.Indexes = nil);
        AssignToInterleaved(TexCoordArray, A, Arrays.AttributeSize, Arrays.Count);
      end;
    end;

  begin
    for I := 0 to Arrays.TexCoords.Count - 1 do
      if Arrays.TexCoords[I].Generation = tgExplicit then
        case Arrays.TexCoords[I].Dimensions of
          2: Handle(2, TexCoordArray2d[I].Items);
          3: Handle(3, TexCoordArray3d[I].Items);
          4: Handle(4, TexCoordArray4d[I].Items);
        end;
  end;

begin
  inherited;

  if TexImplementation in [tcNonIndexed, tcCoordIndexed] then
    EnableExplicitTexCoord;
end;

function TAbstractTextureCoordinateGenerator.GetTextureCoord(
  IndexNum: integer; const TextureUnit: Cardinal;
  out Tex: TVector4Single): boolean;

  function GenerateTexCoord(const TexCoord: TGeometryTexCoord): TVector4Single;
  var
    Vertex: TVector3Single;
  begin
    case TexCoord.Generation of
      tgBounds2d:
        begin
          Vertex := GetVertex(IndexNum);
          Result[0] := VectorDotProduct(Vertex, TexCoord.GenerationBoundsVector[0]);
          Result[1] := VectorDotProduct(Vertex, TexCoord.GenerationBoundsVector[1]);
          Result[2] := 0;
          Result[3] := 1;
        end;
      tgBounds3d:
        begin
          Vertex := GetVertex(IndexNum);
          Result[0] := VectorDotProduct(Vertex, TexCoord.GenerationBoundsVector[0]);
          Result[1] := VectorDotProduct(Vertex, TexCoord.GenerationBoundsVector[1]);
          Result[2] := VectorDotProduct(Vertex, TexCoord.GenerationBoundsVector[2]);
          Result[3] := 1;
        end;
      tgCoord:
        begin
          Vertex := GetVertex(IndexNum);
          Result[0] := Vertex[0];
          Result[1] := Vertex[1];
          Result[2] := Vertex[2];
          Result[3] := 1;
        end;
      else OnWarning(wtMajor, 'VRML/X3D', Format('Generating on CPU texture coordinates with %d not implemented yet',
        [TexCoord.Generation]));
    end;
  end;

  { Sets Tex to TexCoordArray*[TextureUnit][Index] value. }
  procedure SetTexFromTexCoordArray(const Dimensions: TTexCoordDimensions;
    const Index: Integer);
  var
    Tex2d: TVector2Single absolute Tex;
    Tex3d: TVector3Single absolute Tex;
  begin
    case Dimensions of
      2: Tex2d := TexCoordArray2d[TextureUnit].ItemsSafe[Index];
      3: Tex3d := TexCoordArray3d[TextureUnit].ItemsSafe[Index];
      4: Tex   := TexCoordArray4d[TextureUnit].ItemsSafe[Index];
    end;
  end;

begin
  Result := TexImplementation <> tcNotGenerated;

  if Result then
  begin
    { This assertion should never fail, it's the responsibility
      of the programmer. Note that we don't need any TexCoordCount
      here, since IndexNum allowed for GetTextureCoord are the same
      and come from the same range as coords. }
    Assert(IndexNum < CoordCount);

    { Initialize to common values }
    Tex := Vector4Single(0, 0, 0, 1);

    Result := TextureUnit < Arrays.TexCoords.Count;
    if not Result then Exit;

    if Arrays.TexCoords[TextureUnit].Generation = tgExplicit then
    begin
      case TexImplementation of
        tcTexIndexed:
          { tcTexIndexed is set only if
            TexCoordIndex.Count >= CoordIndex.Count, so the IndexNum index
            is Ok for sure. That's why we don't do "ItemsSafe"
            for TexCoordIndex. }
          SetTexFromTexCoordArray(Arrays.TexCoords[TextureUnit].Dimensions, TexCoordIndex.Items.L[IndexNum]);
        tcCoordIndexed:
          { We already checked that IndexNum < CoordCount, so the first index
            is Ok for sure. }
          SetTexFromTexCoordArray(Arrays.TexCoords[TextureUnit].Dimensions, CoordIndex.Items.L[IndexNum]);
        tcNonIndexed:
          SetTexFromTexCoordArray(Arrays.TexCoords[TextureUnit].Dimensions, IndexNum);
        else raise EInternalError.Create('TAbstractTextureCoordinateGenerator.GetTextureCoord?');
      end;
    end else
      Tex := GenerateTexCoord(Arrays.TexCoords[TextureUnit]);
  end;
end;

function TAbstractTextureCoordinateGenerator.GetTextureCoord(
  IndexNum: integer; const TextureUnit: Cardinal;
  out Tex: TVector2Single): boolean;
var
  Tex4f: TVector4Single;
begin
  Result := GetTextureCoord(IndexNum, TextureUnit, Tex4f);
  Tex[0] := Tex4f[0];
  Tex[1] := Tex4f[1];
end;

procedure TAbstractTextureCoordinateGenerator.GenerateVertex(indexNum: integer);

  procedure DoTexCoord(Index: Integer);
  var
    TextureUnit: Integer;
  begin
    Assert(Arrays.Indexes = nil);
    for TextureUnit := 0 to Arrays.TexCoords.Count - 1 do
      if Arrays.TexCoords[TextureUnit].Generation = tgExplicit then
        case Arrays.TexCoords[TextureUnit].Dimensions of
          2: Arrays.TexCoord2D(TextureUnit, ArrayIndexNum)^ := TexCoordArray2d[TextureUnit].ItemsSafe[Index];
          3: Arrays.TexCoord3D(TextureUnit, ArrayIndexNum)^ := TexCoordArray3d[TextureUnit].ItemsSafe[Index];
          4: Arrays.TexCoord4D(TextureUnit, ArrayIndexNum)^ := TexCoordArray4d[TextureUnit].ItemsSafe[Index];
        end;
  end;

begin
  inherited;
  if TexImplementation = tcTexIndexed then
    DoTexCoord(TexCoordIndex.Items.L[IndexNum]);
end;

{ TAbstractMaterial1Generator ------------------------------------------ }

constructor TAbstractMaterial1Generator.Create(AShape: TShape; AOverTriangulate: boolean);
begin
  inherited;
  MaterialBinding := BIND_DEFAULT;
  UpdateMat1Implementation;
end;

procedure TAbstractMaterial1Generator.UpdateMat1Implementation;

  function IndexListNotEmpty(MFIndexes: TMFLong): boolean;
  begin
    Result :=
      (MFIndexes.Count > 0) and
      { For VRML 1.0, [-1] value is default for materialIndex
        and should be treated as "empty", as far as I understand
        the spec. }
      (not ((MFIndexes.Count = 1) and (MFIndexes.Items.L[0] = -1)));
  end;

begin
  { Calculate Mat1Implementation }

  Mat1Implementation := miOverall;

  case MaterialBinding of
    { BIND_OVERALL, BIND_DEFAULT: take default miOverall }
    BIND_PER_VERTEX:
      Mat1Implementation := miPerVertexCoordIndexed;
    BIND_PER_VERTEX_INDEXED:
      if IndexListNotEmpty(MaterialIndex) then
        Mat1Implementation := miPerVertexMatIndexed;
    BIND_PER_PART, BIND_PER_FACE:
      Mat1Implementation := miPerFace;
    BIND_PER_PART_INDEXED, BIND_PER_FACE_INDEXED:
      if IndexListNotEmpty(MaterialIndex) then
        Mat1Implementation := miPerFaceMatIndexed;
  end;

  { TODO: we handle all material bindings, but we handle BIND_PER_PART
    and BIND_PER_PART_INDEXED wrong for IndexedLineSet. }
end;

procedure TAbstractMaterial1Generator.PrepareAttributes(var AllowIndexed: boolean);
begin
  inherited;

  if Mat1Implementation in
    [ miPerFace, miPerFaceMatIndexed,
      miPerVertexCoordIndexed, miPerVertexMatIndexed ] then
  begin
    Arrays.AddColor;
    if Mat1Implementation in
      [ miPerFace, miPerFaceMatIndexed, miPerVertexMatIndexed ] then
      AllowIndexed := false;
  end;
end;

function TAbstractMaterial1Generator.GetMaterial1Color(
  const MaterialIndex: Integer): TVector4Single;
var
  M: TMaterialNode_1;
begin
  M := State.LastNodes.Material;
  if M.OnlyEmissiveMaterial then
    Result := M.EmissiveColor4Single(MaterialIndex) else
    Result := M.DiffuseColor4Single(MaterialIndex);
end;

procedure TAbstractMaterial1Generator.GenerateVertex(IndexNum: Integer);
begin
  inherited;
  case Mat1Implementation of
    miPerVertexCoordIndexed:
      Arrays.Color(ArrayIndexNum)^ := GetMaterial1Color(CoordIndex.ItemsSafe[IndexNum]);
    miPerVertexMatIndexed:
      Arrays.Color(ArrayIndexNum)^ := GetMaterial1Color(MaterialIndex.ItemsSafe[IndexNum]);
    miPerFace, miPerFaceMatIndexed:
      Arrays.Color(ArrayIndexNum)^ := FaceMaterial1Color;
  end;
end;

procedure TAbstractMaterial1Generator.GenerateCoordsRange(
  const RangeNumber: Cardinal; BeginIndex, EndIndex: Integer);
begin
  inherited;

  case Mat1Implementation of
    miPerFace:
      FaceMaterial1Color := GetMaterial1Color(RangeNumber);
    miPerFaceMatIndexed:
      FaceMaterial1Color := GetMaterial1Color(MaterialIndex.Items.L[RangeNumber]);
  end;
end;

{ TAbstractColorGenerator --------------------------------------- }

procedure TAbstractColorGenerator.PrepareAttributes(var AllowIndexed: boolean);
begin
  inherited;

  if Geometry is TAbstractComposedGeometryNode then
    RadianceTransfer := (Geometry as TAbstractComposedGeometryNode).FdRadianceTransfer.Items;

  { calculate final RadianceTransfer:
    Leave it non-nil, and calculate RadianceTransferVertexSize,
    if it's useful. }
  if RadianceTransfer <> nil then
  begin
    if (RadianceTransfer.Count <> 0) and
       Assigned(OnRadianceTransfer) then
    begin
      if RadianceTransfer.Count mod Coord.Count <> 0 then
      begin
        OnWarning(wtMajor, 'VRML/X3D', 'radianceTransfer field must be emppty, or have a number of items being multiple of coods');
        RadianceTransfer := nil;
      end else
      if RadianceTransfer.Count < Coord.Count then
      begin
        OnWarning(wtMajor, 'VRML/X3D', 'radianceTransfer field must be emppty, or have a number of items >= number of coods');
        RadianceTransfer := nil;
      end else
        RadianceTransferVertexSize := RadianceTransfer.Count div Coord.Count;
    end else
      RadianceTransfer := nil;
  end;

  if Assigned(OnVertexColor) or
     (RadianceTransfer <> nil) then
  begin
    Arrays.AddColor;
    AllowIndexed := false;
  end else
  if (Color <> nil) or (ColorRGBA <> nil) then
  begin
    Arrays.AddColor;
    if (ColorIndex <> nil) or (not ColorPerVertex) then
      AllowIndexed := false;
  end;
end;

procedure TAbstractColorGenerator.GenerateVertex(IndexNum: integer);
var
  VertexColor: TVector3Single;
  VertexIndex: Cardinal;
begin
  inherited;
  { Implement different color per vertex here. }
  if Assigned(OnVertexColor) then
  begin
    if CoordIndex <> nil then
      VertexIndex := CoordIndex.ItemsSafe[IndexNum] else
      VertexIndex := IndexNum;

    { Get vertex color, taking various possible configurations.
      OnVertexColor will be able to change it. }
    if (Color <> nil) and ColorPerVertex then
    begin
      if (ColorIndex <> nil) and (ColorIndex.Count <> 0) then
        VertexColor := Color.ItemsSafe[ColorIndex.ItemsSafe[IndexNum]] else
      if CoordIndex <> nil then
        VertexColor := Color.ItemsSafe[CoordIndex.ItemsSafe[IndexNum]] else
        VertexColor := Color.ItemsSafe[IndexNum];
    end else
    if (State.ShapeNode <> nil) and
       (State.ShapeNode.Material <> nil) then
    begin
      VertexColor := State.ShapeNode.Material.FdDiffuseColor.Value;
    end else
      VertexColor := White3Single; { default fallback }

    OnVertexColor(VertexColor, Shape, GetVertex(IndexNum), VertexIndex);
    Arrays.Color(ArrayIndexNum)^ := Vector4Single(VertexColor, MaterialOpacity);
  end else
  if RadianceTransfer <> nil then
  begin
    if CoordIndex <> nil then
      VertexIndex := CoordIndex.ItemsSafe[IndexNum] else
      VertexIndex := IndexNum;

    VertexColor := OnRadianceTransfer(Geometry,
      Addr(RadianceTransfer.L[VertexIndex * RadianceTransferVertexSize]),
      RadianceTransferVertexSize);

    Arrays.Color(ArrayIndexNum)^ := Vector4Single(VertexColor, MaterialOpacity);
  end else
  if Color <> nil then
  begin
    if ColorPerVertex then
    begin
      if (ColorIndex <> nil) and (ColorIndex.Count <> 0) then
        Arrays.Color(ArrayIndexNum)^ := Vector4Single(Color.ItemsSafe[ColorIndex.ItemsSafe[IndexNum]], MaterialOpacity) else
      if CoordIndex <> nil then
        Arrays.Color(ArrayIndexNum)^ := Vector4Single(Color.ItemsSafe[CoordIndex.ItemsSafe[IndexNum]], MaterialOpacity) else
        Arrays.Color(ArrayIndexNum)^ := Vector4Single(Color.ItemsSafe[IndexNum], MaterialOpacity);
    end else
      Arrays.Color(ArrayIndexNum)^ := FaceColor;
  end else
  if ColorRGBA <> nil then
  begin
    if ColorPerVertex then
    begin
      if (ColorIndex <> nil) and (ColorIndex.Count <> 0) then
        Arrays.Color(ArrayIndexNum)^ := ColorRGBA.ItemsSafe[ColorIndex.ItemsSafe[IndexNum]] else
      if CoordIndex <> nil then
        Arrays.Color(ArrayIndexNum)^ := ColorRGBA.ItemsSafe[CoordIndex.ItemsSafe[IndexNum]] else
        Arrays.Color(ArrayIndexNum)^ := ColorRGBA.ItemsSafe[IndexNum];
    end else
      Arrays.Color(ArrayIndexNum)^ := FaceColor;
  end;
end;

procedure TAbstractColorGenerator.GenerateCoordsRange(
  const RangeNumber: Cardinal; BeginIndex, EndIndex: Integer);
begin
  inherited;

  { Implement different color per face here. }
  if (not Assigned(OnVertexColor)) and
     (RadianceTransfer = nil) then
  begin
    if (Color <> nil) and (not ColorPerVertex) then
    begin
      if (ColorIndex <> nil) and (ColorIndex.Count <> 0) then
        FaceColor := Vector4Single(Color.ItemsSafe[ColorIndex.ItemsSafe[RangeNumber]], MaterialOpacity) else
        FaceColor := Vector4Single(Color.ItemsSafe[RangeNumber], MaterialOpacity);
    end else
    if (ColorRGBA <> nil) and (not ColorPerVertex) then
    begin
      if (ColorIndex <> nil) and (ColorIndex.Count <> 0) then
        FaceColor := ColorRGBA.ItemsSafe[ColorIndex.ItemsSafe[RangeNumber]] else
        FaceColor := ColorRGBA.ItemsSafe[RangeNumber];
    end;
  end;
end;

{ TAbstractNormalGenerator ----------------------------------------------------- }

procedure TAbstractNormalGenerator.PrepareAttributes(
  var AllowIndexed: boolean);
begin
  inherited;

  if not (
      { When IndexNum for normal works exactly like for position,
        then normals can be indexed. This is true in two cases:
        - there is no coordIndex, and normal vectors are not indexed
        - there is coordIndex, and normal vectors are indexed by coordIndex }
      (NorImplementation = niPerVertexCoordIndexed) or
     ((NorImplementation = niPerVertexNonIndexed) and (CoordIndex = nil)) ) then
    AllowIndexed := false;
end;

function TAbstractNormalGenerator.
  NorImplementationFromVRML1Binding(NormalBinding: Integer): TNormalsImplementation;
begin
  Result := niNone;

  if (Normals = nil) or (NormalIndex = nil) then
    Exit;

  case NormalBinding of
    BIND_DEFAULT, BIND_PER_VERTEX_INDEXED:
      if (NormalIndex.Count > 0) and (NormalIndex.Items.L[0] >= 0) then
        Result := niPerVertexNormalIndexed;
    BIND_PER_VERTEX:
      if CoordIndex <> nil then
        Result := niPerVertexCoordIndexed;
    BIND_OVERALL:
      if Normals.Count > 0 then
        Result := niOverall;
    BIND_PER_PART, BIND_PER_FACE:
      Result := niPerFace;
    BIND_PER_PART_INDEXED, BIND_PER_FACE_INDEXED:
      if (NormalIndex.Count > 0) and (NormalIndex.Items.L[0] >= 0) then
        Result := niPerFaceNormalIndexed;
  end;

  { If no normals are provided (for VRML 1.0, this means that last Normal
    node was empty, or it's the default empty node from DefaultLastNodes scen)
    then generate normals. }
  if Normals.Count = 0 then
    Result := niNone;
end;

function TAbstractNormalGenerator.CcwNormalsSafe(
  const Index: Integer): TVector3Single;
begin
  if Index < CcwNormals.Count then
    Result := CcwNormals.L[Index] else
    Result := ZeroVector3Single;
end;

procedure TAbstractNormalGenerator.GetNormal(
  IndexNum: Integer; RangeNumber: Integer; out N: TVector3Single);
begin
  case NorImplementation of
    niOverall:
      N := CcwNormals.L[0];
    niPerVertexNonIndexed:
      N := CcwNormals.L[IndexNum];
    niPerVertexCoordIndexed:
      N := CcwNormals.L[CoordIndex.Items.L[IndexNum]];
    niPerVertexNormalIndexed:
      N := CcwNormals.L[NormalIndex.ItemsSafe[IndexNum]];
    niPerFace:
      N := CcwNormals.L[RangeNumber];
    niPerFaceNormalIndexed:
      N := CcwNormals.L[NormalIndex.ItemsSafe[RangeNumber]];
    else
      raise EInternalError.CreateFmt('NorImplementation unknown (probably niNone, and not overridden GetNormal) in class %s',
        [ClassName]);
  end;
end;

function TAbstractNormalGenerator.NormalsFlat: boolean;
begin
  Result := NorImplementation in [niOverall, niPerFace, niPerFaceNormalIndexed];
end;

procedure TAbstractNormalGenerator.GenerateVertex(IndexNum: Integer);
begin
  inherited;
  case NorImplementation of
    niPerVertexNormalIndexed:
      begin
        Assert(Arrays.Indexes = nil);
        Arrays.Normal(ArrayIndexNum)^ := CcwNormalsSafe(NormalIndex.ItemsSafe[IndexNum]);
      end;
    niPerVertexNonIndexed:
      if CoordIndex <> nil then
      begin
        Assert(Arrays.Indexes = nil);
        Arrays.Normal(ArrayIndexNum)^ := CcwNormalsSafe(IndexNum);
      end;
    niPerFace, niPerFaceNormalIndexed:
      begin
        Assert(Arrays.Indexes = nil);
        Arrays.Normal(ArrayIndexNum)^ := FaceNormal;
      end;
  end;
end;

procedure TAbstractNormalGenerator.GenerateCoordinateBegin;

  procedure SetAllNormals(const Value: TVector3Single);
  var
    N: PVector3Single;
    I: Integer;
  begin
    N := Arrays.Normal;
    for I := 0 to Arrays.Count - 1 do
    begin
      N^ := Value;
      Arrays.IncNormal(N);
    end;
  end;

begin
  inherited;

  if Normals <> nil then
  begin
    if NormalsCcw then
      CcwNormals := Normals else
    begin
      CcwNormals := TVector3SingleList.Create;
      CcwNormals.AssignNegated(Normals);
    end;
  end;

  if NorImplementation = niPerVertexCoordIndexed then
  begin
    if Arrays.Indexes <> nil then
      AssignToInterleaved(CcwNormals, Arrays.Normal, Arrays.CoordinateSize, Arrays.Count) else
      AssignToInterleavedIndexed(CcwNormals, Arrays.Normal, Arrays.CoordinateSize, Arrays.Count, IndexesFromCoordIndex);
  end else
  if (NorImplementation = niPerVertexNonIndexed) and (CoordIndex = nil) then
  begin
    Assert(Arrays.Indexes = nil);
    AssignToInterleaved(CcwNormals, Arrays.Normal, Arrays.CoordinateSize, Arrays.Count);
  end else
  if NorImplementation = niOverall then
  begin
    SetAllNormals(CcwNormalsSafe(0));
  end;
end;

procedure TAbstractNormalGenerator.GenerateCoordinateEnd;
begin
  if (Normals <> nil) and (not NormalsCcw) then
    FreeAndNil(CcwNormals);

  inherited;
end;

procedure TAbstractNormalGenerator.GenerateCoordsRange(
  const RangeNumber: Cardinal; BeginIndex, EndIndex: Integer);
begin
  inherited;

  { FaceNormal will be actually copied to Arrays.Normal in GenerateVertex
    for this face. }
  case NorImplementation of
    niPerFace:
      FaceNormal := CcwNormalsSafe(RangeNumber);
    niPerFaceNormalIndexed:
      FaceNormal := CcwNormalsSafe(NormalIndex.ItemsSafe[RangeNumber]);
  end;
end;

{ TAbstractFogGenerator --------------------------------- }

constructor TAbstractFogGenerator.Create(AShape: TShape; AOverTriangulate: boolean);
begin
  inherited;

  if Geometry.FogCoord <> nil then
    FogCoord := Geometry.FogCoord.Items;
end;

procedure TAbstractFogGenerator.PrepareAttributes(
  var AllowIndexed: boolean);
begin
  inherited;

  if (FogCoord <> nil) or FogVolumetric then
  begin
    Arrays.AddFogCoord;
    Arrays.FogDirectValues := FogCoord <> nil;
  end;
end;

procedure TAbstractFogGenerator.GenerateVertex(
  IndexNum: Integer);

  function GetFogCoord: Single;
  begin
    { make IndexNum independent of coordIndex, always work like index to coords }
    if CoordIndex <> nil then
      IndexNum := CoordIndex.Items.L[IndexNum];

    { calculate Fog, based on FogCoord and IndexNum }
    if IndexNum < FogCoord.Count then
      Result := FogCoord.L[IndexNum] else
    if FogCoord.Count <> 0 then
      Result := FogCoord.Last else
      Result := 0; //< some default
  end;

  function GetFogVolumetric: Single;
  var
    Position, Projected: TVector3Single;
  begin
    { calculate global vertex position }
    if CoordIndex <> nil then
      Position := Coord.Items.L[CoordIndex.Items.L[IndexNum]] else
      Position := Coord.Items.L[IndexNum];
    Position := MatrixMultPoint(State.Transform, Position);

    Projected := PointOnLineClosestToPoint(
      ZeroVector3Single, FogVolumetricDirection, Position);
    Result := VectorLen(Projected);
    if not AreParallelVectorsSameDirection(
      Projected, FogVolumetricDirection) then
      Result := -Result;
    { Now I want
      - Result = FogVolumetricVisibilityStart -> 0
      - Result = FogVolumetricVisibilityStart + X -> X
        (so that Result = FogVolumetricVisibilityStart +
        FogVisibilityRangeScaled -> FogVisibilityRangeScaled) }
    Result -= FogVolumetricVisibilityStart;
  end;

  procedure SetFog(const Fog: Single);
  begin
    { When Result < 0 our intention is to have no fog (at least
      for volumetric fog, for explicit FogCoordinate we don't know what
      was user's intention).
      So Result < 0 should be equivalent to Result = 0.
      However, OpenGL doesn't necessarily interpret it like this.

      Since factor given by glFogCoordfEXT is interpreted just like
      eye distance (i.e. it's processed by appopriate linear or exp or exp2
      equations), negative values may produce quite unexpected results
      (unless you really look at the equations).

      This is mentioned in the extension specification
      [http://oss.sgi.com/projects/ogl-sample/registry/EXT/fog_coord.txt].
      First is says:

        * Should the specified value be used directly as the fog weighting
          factor, or in place of the z input to the fog equations?

          As the z input; more flexible and meets ISV requests.

      ... which means that what glFogCoordfEXT gives is interpreted
      just like eye distance for normal fog (so it's e.g. affected
      by fog linear / exp / exp2 modes, affected by fog start and end values,
      etc.). Later it says:

        * Should the fog coordinate be restricted to non-negative values?

          Perhaps. Eye-coordinate distance of fragments will be
          non-negative due to clipping. Specifying explicit negative
          coordinates may result in very large computed f values, although
          they are defined to be clipped after computation.

      ... and this is precisely why specifying negative glFogCoordfEXT
      parameters is a bad idea: you don't really know what OpenGL
      implementation will do. NVidia OpenGL seems to actually assume
      that factor < 0 means the same as factor = 0, so my code
      worked OK without clamping below
      (because NVidia OpenGL was actually doing it anyway).
      Mesa 3D (and Radeon, as I suspect, because similar problems
      were reported for "The Castle" on Radeon) seem to just use the negative
      value directly, which causes strange artifacts
      (see e.g. "The Castle" gate_final.wrl VRML file).

      The clamping below makes volumetric fog work
      OK as expected for all OpenGL implementations.

      Note: we don't limit Fog to be <= 1 (although we could
      for X3D FogCoordinate). glFogCoord is like a distance from the eye,
      so it may be >= 1, and GetFogVolumetric depends on it to work. }
    Arrays.FogCoord(ArrayIndexNum)^ := Max(Fog, 0);
  end;

begin
  inherited;
  if FogCoord <> nil then
    SetFog(GetFogCoord) else
  if FogVolumetric then
    SetFog(GetFogVolumetric);
end;

{ TAbstractShaderAttribGenerator ------------------------------ }

constructor TAbstractShaderAttribGenerator.Create(AShape: TShape; AOverTriangulate: boolean);
var
  A: TMFNode;
  I: Integer;
begin
  inherited;

  A := Geometry.Attrib;
  if A <> nil then
    for I := 0 to A.Count - 1 do
      if A[I] is TAbstractVertexAttributeNode then
      begin
        { To conserve time and memory, create Attrib instance only when needed }
        if Attrib = nil then
          Attrib := TX3DVertexAttributeNodes.Create(false);
        Attrib.Add(TAbstractVertexAttributeNode(A[I]));
      end;
end;

destructor TAbstractShaderAttribGenerator.Destroy;
begin
  FreeAndNil(Attrib);
  inherited;
end;

procedure TAbstractShaderAttribGenerator.PrepareAttributes(var AllowIndexed: boolean);
var
  I: Integer;
begin
  inherited;
  if Attrib <> nil then
    for I := 0 to Attrib.Count - 1 do
    begin
      { call Arrays.AddGLSLAttribute* }
      if Attrib[I] is TFloatVertexAttributeNode then
      begin
        case TFloatVertexAttributeNode(Attrib[I]).FdNumComponents.Value of
          1: Arrays.AddGLSLAttributeFloat(Attrib[I].FdName.Value, false);
          2: Arrays.AddGLSLAttributeVector2(Attrib[I].FdName.Value, false);
          3: Arrays.AddGLSLAttributeVector3(Attrib[I].FdName.Value, false);
          4: Arrays.AddGLSLAttributeVector4(Attrib[I].FdName.Value, false);
          else OnWarning(wtMajor, 'VRML/X3D', Format('Invalid FloatVertexAttribute.numComponents: %d (should be between 1..4)',
            [TFloatVertexAttributeNode(Attrib[I]).FdNumComponents.Value]));
        end;
      end else
      if Attrib[I] is TMatrix3VertexAttributeNode then
        Arrays.AddGLSLAttributeMatrix3(Attrib[I].FdName.Value, false) else
      if Attrib[I] is TMatrix4VertexAttributeNode then
        Arrays.AddGLSLAttributeMatrix4(Attrib[I].FdName.Value, false) else
        OnWarning(wtMajor, 'VRML/X3D', Format('Not handled vertex attribute class %s',
          [Attrib[I].NodeTypeName]));
    end;
end;

procedure TAbstractShaderAttribGenerator.GenerateVertex(IndexNum: Integer);
var
  I: Integer;
  VertexIndex: Integer;
begin
  inherited;
  if Attrib <> nil then
  begin
    if CoordIndex <> nil then
      VertexIndex := CoordIndex.Items.L[IndexNum] else
      VertexIndex := IndexNum;

    for I := 0 to Attrib.Count - 1 do
    begin
      { set Arrays.GLSLAttribute*(ArrayIndexNum).
        Note we don't do some warnings here, that were already done
        in PrepareAttributes. }
      if Attrib[I] is TFloatVertexAttributeNode then
      begin
        case TFloatVertexAttributeNode(Attrib[I]).FdNumComponents.Value of
          1: Arrays.GLSLAttributeFloat(Attrib[I].FdName.Value, ArrayIndexNum)^ :=
               TFloatVertexAttributeNode(Attrib[I]).FdValue.ItemsSafe[VertexIndex];
          2: Arrays.GLSLAttributeVector2(Attrib[I].FdName.Value, ArrayIndexNum)^ := Vector2Single(
               TFloatVertexAttributeNode(Attrib[I]).FdValue.ItemsSafe[VertexIndex * 2],
               TFloatVertexAttributeNode(Attrib[I]).FdValue.ItemsSafe[VertexIndex * 2 + 1]);
          3: Arrays.GLSLAttributeVector3(Attrib[I].FdName.Value, ArrayIndexNum)^ := Vector3Single(
               TFloatVertexAttributeNode(Attrib[I]).FdValue.ItemsSafe[VertexIndex * 3],
               TFloatVertexAttributeNode(Attrib[I]).FdValue.ItemsSafe[VertexIndex * 3 + 1],
               TFloatVertexAttributeNode(Attrib[I]).FdValue.ItemsSafe[VertexIndex * 3 + 2]);
          4: Arrays.GLSLAttributeVector4(Attrib[I].FdName.Value, ArrayIndexNum)^ := Vector4Single(
               TFloatVertexAttributeNode(Attrib[I]).FdValue.ItemsSafe[VertexIndex * 4],
               TFloatVertexAttributeNode(Attrib[I]).FdValue.ItemsSafe[VertexIndex * 4 + 1],
               TFloatVertexAttributeNode(Attrib[I]).FdValue.ItemsSafe[VertexIndex * 4 + 2],
               TFloatVertexAttributeNode(Attrib[I]).FdValue.ItemsSafe[VertexIndex * 4 + 3]);
        end;
      end else
      if Attrib[I] is TMatrix3VertexAttributeNode then
        Arrays.GLSLAttributeMatrix3(Attrib[I].FdName.Value, ArrayIndexNum)^ :=
          TMatrix3VertexAttributeNode(Attrib[I]).FdValue.ItemsSafe[VertexIndex] else
      if Attrib[I] is TMatrix4VertexAttributeNode then
        Arrays.GLSLAttributeMatrix4(Attrib[I].FdName.Value, ArrayIndexNum)^ :=
          TMatrix4VertexAttributeNode(Attrib[I]).FdValue.ItemsSafe[VertexIndex];
    end;
  end;
end;

{ TAbstractBumpMappingGenerator ----------------------------------------------- }

procedure TAbstractBumpMappingGenerator.PrepareAttributes(var AllowIndexed: boolean);
begin
  inherited;
  if ShapeBumpMappingUsed then
    Arrays.AddGLSLAttributeMatrix3('kambi_tangent_to_object_space', true);
end;

procedure TAbstractBumpMappingGenerator.GenerateVertex(IndexNum: Integer);

  procedure DoBumpMapping;

    function TangentToObjectSpace: TMatrix3Single;

      procedure SetResult(const Normal, STangent, TTangent: TVector3Single);
      begin
        Result[0] := STangent;
        Result[1] := TTangent;
        Result[2] := Normal;
      end;

    var
      LocalSTangent, LocalTTangent: TVector3Single;
      Normal: TVector3Single;
    begin
      GetNormal(IndexNum, CurrentRangeNumber, Normal);

      if HasTangentVectors and
        (Abs(VectorDotProduct(STangent, Normal)) < 0.95) and
        (Abs(VectorDotProduct(TTangent, Normal)) < 0.95) then
      begin
        if NormalsFlat then
        begin
          SetResult(Normal, STangent, TTangent);
        end else
        begin
          { If not NormalsFlat, you want to calculate local STangent and TTangent,
            I mean STangent and TTangent adjusted to current vertex (since each
            vertex may have different normal on the face when not NormalsFlat).

            Without doing this, you would see strange artifacts, smoothed
            faces would look somewhat like flat faces. Concenptually, for smoothed
            faces, whole tangent space should vary for each vertex, so Normal,
            and both tangents may be different on each vertex. }

          LocalSTangent := STangent;
          MakeVectorsOrthoOnTheirPlane(LocalSTangent, Normal);

          LocalTTangent := TTangent;
          MakeVectorsOrthoOnTheirPlane(LocalTTangent, Normal);

          SetResult(Normal, LocalSTangent, LocalTTangent);
        end;
      end else
      begin
        SetResult(Normal,
          { would be more correct to set LocalSTangent as anything perpendicular
            to Normal, and LocalTTangent as vector product (normal, LocalSTangent) }
          Vector3Single(1, 0, 0), Vector3Single(0, 1, 0));
      end;
    end;

  begin
    Arrays.GLSLAttributeMatrix3('kambi_tangent_to_object_space',
      ArrayIndexNum)^ := TangentToObjectSpace;
  end;

begin
  inherited;
  if ShapeBumpMappingUsed then
    DoBumpMapping;
end;

procedure TAbstractBumpMappingGenerator.CalculateTangentVectors(
  const TriangleIndex1, TriangleIndex2, TriangleIndex3: Integer);

  { This procedure can change Triangle*, but only by swapping some vertexes,
    so we pass Triangle* by reference instead of by value, to avoid
    needless mem copying.

    Returns @false if cannot be calculated. }
  function CalculateTangent(IsSTangent: boolean; var Tangent: TVector3Single;
    var Triangle3D: TTriangle3Single;
    var TriangleTexCoord: TTriangle2Single): boolean;
  var
    D: TVector2Single;
    LineA, LineBC, DIn3D: TVector3Single;
    MiddleIndex: Integer;
    FarthestDistance, NewDistance, Alpha: Single;
    SearchCoord, OtherCoord: Cardinal;
  begin
    if ISSTangent then
      SearchCoord := 0 else
      SearchCoord := 1;
    OtherCoord := 1 - SearchCoord;

    { choose such that 1st and 2nd points have longest distance along
      OtherCoord, so 0 point is in the middle. }

    { MiddleIndex means that
      MiddleIndex, (MiddleIndex + 1) mod 3 are farthest. }

    MiddleIndex := 2;
    FarthestDistance := Abs(TriangleTexCoord[0][OtherCoord] - TriangleTexCoord[1][OtherCoord]);

    NewDistance := Abs(TriangleTexCoord[1][OtherCoord] - TriangleTexCoord[2][OtherCoord]);
    if NewDistance > FarthestDistance then
    begin
      MiddleIndex := 0;
      FarthestDistance := NewDistance;
    end;

    NewDistance := Abs(TriangleTexCoord[2][OtherCoord] - TriangleTexCoord[0][OtherCoord]);
    if NewDistance > FarthestDistance then
    begin
      MiddleIndex := 1;
      FarthestDistance := NewDistance;
    end;

    if Zero(FarthestDistance) then
      Exit(false);

    if MiddleIndex <> 0 then
    begin
      SwapValues(TriangleTexCoord[0], TriangleTexCoord[MiddleIndex]);
      SwapValues(Triangle3D      [0], Triangle3D      [MiddleIndex]);
    end;

    if IsSTangent then
    begin
      { we want line Y = TriangleTexCoord[0][1]. }
      LineA[0] := 0;
      LineA[1] := 1;
      LineA[2] := -TriangleTexCoord[0][1];
    end else
    begin
      { we want line X = TriangleTexCoord[0][0]. }
      LineA[0] := 1;
      LineA[1] := 0;
      LineA[2] := -TriangleTexCoord[0][0];
    end;
    LineBC := LineOfTwoDifferentPoints2d(
      TriangleTexCoord[1], TriangleTexCoord[2]);

    try
      D := Lines2DIntersection(LineA, LineBC);
    except
      on ELinesParallel do begin Result := false; Exit; end;
    end;

    { LineBC[0, 1] is vector 2D orthogonal to LineBC.
      If Abs(LineBC[0]) is *smaller* then it means that B and C points
      are most different on 0 coord. }
    if Abs(LineBC[0]) < Abs(LineBC[1]) then
      Alpha := (                  D[0] - TriangleTexCoord[1][0]) /
               (TriangleTexCoord[2][0] - TriangleTexCoord[1][0]) else
      Alpha := (                  D[1] - TriangleTexCoord[1][1]) /
               (TriangleTexCoord[2][1] - TriangleTexCoord[1][1]);

    DIn3D := VectorAdd(
      VectorScale(Triangle3D[1], 1 - Alpha),
      VectorScale(Triangle3D[2], Alpha));

    if D[SearchCoord] > TriangleTexCoord[0][SearchCoord] then
      Tangent := VectorSubtract(DIn3D, Triangle3D[0]) else
      Tangent := VectorSubtract(Triangle3D[0], DIn3D);

    NormalizeTo1st(Tangent);

    Result := true;
  end;

var
  Triangle3D: TTriangle3Single;
  TriangleTexCoord: TTriangle2Single;
begin
  HasTangentVectors := false;
  if ShapeBumpMappingUsed then
  begin
    { calculate Triangle3D }
    Triangle3D[0] := GetVertex(TriangleIndex1);
    Triangle3D[1] := GetVertex(TriangleIndex2);
    Triangle3D[2] := GetVertex(TriangleIndex3);

    { This is just to shut up FPC 2.2.0 warnings about
      TriangleTexCoord not initialized. }
    TriangleTexCoord[0][0] := 0.0;

    HasTangentVectors :=
      { calculate TriangleTexCoord }
      GetTextureCoord(TriangleIndex1, 0, TriangleTexCoord[0]) and
      GetTextureCoord(TriangleIndex2, 0, TriangleTexCoord[1]) and
      GetTextureCoord(TriangleIndex3, 0, TriangleTexCoord[2]) and
      { calculate STangent, TTangent }
      CalculateTangent(true , STangent, Triangle3D, TriangleTexCoord) and
      CalculateTangent(false, TTangent, Triangle3D, TriangleTexCoord) and
      (Abs(VectorDotProduct(STangent, TTangent)) < 0.95);
  end;
end;

{ non-abstract generators ---------------------------------------------------- }

{$I vrmlarraysgenerator_x3d_rendering.inc}
{$I vrmlarraysgenerator_x3d_geometry3d.inc}

{ global routines ------------------------------------------------------------ }

function ArraysGenerator(AGeometry: TAbstractGeometryNode): TVRMLArraysGeneratorClass;
begin
  if AGeometry is TIndexedTriangleMeshNode_1 then
    Result := TTriangleStripSetGenerator else
  if AGeometry is TIndexedFaceSetNode_1 then
    Result := TIndexedFaceSet_1Generator else
  if AGeometry is TIndexedFaceSetNode then
    Result := TIndexedFaceSetGenerator else
  if AGeometry is TIndexedLineSetNode_1 then
    Result := TIndexedLineSet_1Generator else
  if (AGeometry is TIndexedLineSetNode) or
     (AGeometry is TLineSetNode) then
    Result := TLineSetGenerator else
  if AGeometry is TPointSetNode_1 then
    Result := TPointSet_1Generator else
  if AGeometry is TPointSetNode then
    Result := TPointSetGenerator else
  if (AGeometry is TTriangleSetNode) or
     (AGeometry is TIndexedTriangleSetNode) then
    Result := TTriangleSetGenerator else
  if (AGeometry is TTriangleFanSetNode) or
     (AGeometry is TIndexedTriangleFanSetNode) then
    Result := TTriangleFanSetGenerator else
  if (AGeometry is TTriangleStripSetNode) or
     (AGeometry is TIndexedTriangleStripSetNode) then
    Result := TTriangleStripSetGenerator else
  if (AGeometry is TQuadSetNode) or
     (AGeometry is TIndexedQuadSetNode) then
    Result := TQuadSetGenerator else
    Result := nil;
end;

end.
