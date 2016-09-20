"""
PCL common types, functions and utilities. The primary export is the
`PointCloud{PointT}` (aliased to `PointCloudPtr{PointT}`), which represents a
shared pointer of a point cloud (i.e. `pcl::PointCloud<PointT>::Ptr`) in PCL.
You can create point clouds as follows:

```@example
using PCLCommon

# Create empty point cloud
cloud = PointCloud{PointXYZRGBA}()
```

or

```@example
using PCLCommon
using PCLIO

# Create and load point cloud from a PCD file
cloud = PointCloud{PointXYZRGB}("your_pcd_file.pcd")
```
"""
module PCLCommon

export @boostsharedptr, @defpcltype, @defptrconstructor, @defconstructor,
    BoostSharedPtr, use_count,
    PointCloud, PointCloud2,
    PCLBase, setInputCloud, getInputCloud, setIndices, getIndices,
    transformPointCloud, compute3DCentroid, removeNaNFromPointCloud,
    PCLPointCloud2, Correspondence, Correspondences,
    ModelCoefficients, PointIndices

using LibPCL
using Cxx
using CxxStd
using DocStringExtensions

include("macros.jl")
include("std.jl")

import Base: call, eltype, length, size, getindex, setindex!, push!, convert

cxx"""
#include <pcl/common/common_headers.h>
#include <pcl/common/transforms.h>
#include <pcl/common/centroid.h>
#include <pcl/range_image/range_image.h>
"""

"""
boost::shared_ptr<T>
"""
typealias BoostSharedPtr{T} cxxt"boost::shared_ptr<$T>"

"""
$(SIGNATURES)

Returns reference count
"""
use_count(s::BoostSharedPtr) = icxx"$s.use_count();"
Base.pointer(s::BoostSharedPtr) = convert(Ptr{Void}, icxx"$s.get();")

### PointType definitions ###

# from PCL_POINT_TYPES in point_types.hpp
for name in [
    :PointXYZ,
    :PointXYZI,
    :PointXYZL,
    :Label,
    :PointXYZRGBA,
    :PointXYZRGB,
    :PointXYZRGBL,
    :PointXYZHSV,
    :PointXY,
    :InterestPoint,
    :Axis,
    :Normal,
    :PointNormal,
    :PointXYZRGBNormal,
    :PointXYZINormal,
    :PointXYZLNormal,
    :PointWithRange,
    :PointWithViewpoint,
    :MomentInvariants,
    :PrincipalRadiiRSD,
    :Boundary,
    :PrincipalCurvatures,
    :PFHSignature125,
    :PFHRGBSignature250,
    :PPFSignature,
    :CPPFSignature,
    :PPFRGBSignature,
    :NormalBasedSignature12,
    :FPFHSignature33,
    :VFHSignature308,
    :GRSDSignature21,
    :ESFSignature640,
    :BRISKSignature512,
    :Narf36,
    :IntensityGradient,
    :PointWithScale,
    :PointSurfel,
    :ShapeContext1980,
    :UniqueShapeContext1960,
    :SHOT352,
    :SHOT1344,
    :PointUV,
    :ReferenceFrame,
    :PointDEM,
    ]
    refname = Symbol(name, :Ref)
    valorref = Symbol(name, :ValOrRef)
    cppname = string("pcl::", name)
    cxxtdef = Expr(:macrocall, Symbol("@cxxt_str"), cppname);
    rcppdef = Expr(:macrocall, Symbol("@rcpp_str"), cppname);

    @eval begin
        global const $name = $cxxtdef
        global const $refname = $rcppdef
        global const $valorref = Union{$name, $refname}
        export $name, $refname, $valorref
    end

    # no args constructor
    body = Expr(:macrocall, Symbol("@icxx_str"), string(cppname, "();"))
    @eval (::Type{$name})() = $body
end

(::Type{PointXYZ})(x, y, z) = icxx"pcl::PointXYZ($x, $y, $z);"

import Base: show

function show(io::IO, p::PointXYZRGBValOrRef)
    x = icxx"$p.x;"
    y = icxx"$p.y;"
    z = icxx"$p.z;"
    r = icxx"$p.r;"
    g = icxx"$p.g;"
    b = icxx"$p.b;"
    print(io, string(typeof(p)));
    print(io, "\n");
    print(io, "(x,y,z,r,g,b): ");
    print(io, (x,y,z,r,g,b))
end

function show(io::IO, p::PointXYZValOrRef)
    x = icxx"$p.x;"
    y = icxx"$p.y;"
    z = icxx"$p.z;"
    println(io, string(typeof(p)));
    print(io, "(x,y,z): ");
    print(io, (x,y,z))
end

### Utils ###

"""
pcl::deg2rad
"""
deg2rad(alpha::AbstractFloat) = icxx"pcl::deg2rad($alpha);"

### PointCloud ###

@defpcltype PointCloud{T} "pcl::PointCloud"
@defptrconstructor PointCloud{T}() "pcl::PointCloud"
@defptrconstructor PointCloud{T}(w::Integer, h::Integer) "pcl::PointCloud"
@defconstructor PointCloudVal{T}() "pcl::PointCloud"
@defconstructor PointCloudVal{T}(w::Integer, h::Integer) "pcl::PointCloud"

"""
pcl::PointCloud<PointT>::Ptr

**Examples**

```julia
cloud = PointCloud{PointXYZ}("my_xyz_cloud.pcd")
```

```julia
cloud = PointCloud{PointXYZRGBA}(100, 200) # width=100, height=200
```

"""
PointCloud

eltype{T}(cloud::PointCloud{T}) = T
eltype{T}(cloud::PointCloudVal{T}) = T

function show(io::IO, cloud::PointCloudPtr)
    println(io, "$(length(cloud))-element ", string(typeof(cloud)))
    println(io, "Dereferenced C++ representation:")
    print(io, icxx"*$(cloud.handle);")
end

function show(io::IO, cloud::PointCloudVal)
    println(io, "$(length(cloud))-element ", string(typeof(cloud)))
    println(io, "C++ representation:")
    print(io, icxx"$(cloud.handle);")
end

import Base: similar

similar{T}(cloud::PointCloud{T}) = PointCloud{T}(width(cloud), height(cloud))

import Base: copy, deepcopy

function deepcopy{T}(cloud::PointCloud{T})
    cloud_out = PointCloud{T}()
    icxx"pcl::copyPointCloud(*$(cloud.handle), *$(cloud_out.handle));"
    cloud_out
end

function copy(cloud::PointCloud)
    PointCloud(icxx"auto c = $(cloud.handle); return c;")
end

"""
$(SIGNATURES)

Converts a point cloud to a different type of point cloud

**Examples**

```julia
cloud = PointCloud{PointXYZRGB}()
xyz_cloud = convert(PointCloud{PointXYZ}, cloud)
```
"""
function convert{T}(::Type{PointCloud{T}}, cloud::PointCloud)
    cloud_out = PointCloud{T}()
    icxx"pcl::copyPointCloud(*$(cloud.handle), *$(cloud_out.handle));"
    cloud_out
end

getindex(cloud::PointCloud, i::Integer) = icxx"$(cloud.handle)->at($i);"

function getindex(cloud::PointCloud, i::Integer, name::Symbol)
    p = icxx"&$(cloud.handle)->points[$i];"
    @eval @cxx $p->$name
end
function setindex!(cloud::PointCloud, v, i::Integer, name::Symbol)
    p = icxx"&$(cloud.handle)->points[$i];"
    vp = @eval @cxx &($p->$name)
    unsafe_store!(vp, v, 1)
end

push!{T}(cloud::PointCloud{T}, p) = icxx"$(cloud.handle)->push_back($p);"

length(cloud::PointCloud) = convert(Int, icxx"$(cloud.handle)->size();")
width(cloud::PointCloud) = convert(Int, icxx"$(cloud.handle)->width;")
height(cloud::PointCloud) = convert(Int, icxx"$(cloud.handle)->height;")
is_dense(cloud::PointCloud) = icxx"$(cloud.handle)->is_dense;"
points(cloud::PointCloud) = icxx"$(cloud.handle)->points;"

length(cloud::PointCloudVal) = convert(Int, icxx"$(cloud.handle).size();")
width(cloud::PointCloudVal) = convert(Int, icxx"$(cloud.handle).width;")
height(cloud::PointCloudVal) = convert(Int, icxx"$(cloud.handle).height;")
is_dense(cloud::PointCloudVal) = icxx"$(cloud.handle).is_dense;"
points(cloud::PointCloudVal) = icxx"$(handle(cloud)).points;"

### PCLBase Interface ###

"""
Similar to pcl::PCLBase, for dispatch
"""
abstract PCLBase

setInputCloud(base::PCLBase, cloud::PointCloud) =
    icxx"$(base.handle)->setInputCloud($(cloud.handle));"

getInputCloud(base::PCLBase) =
    PointCloud(icxx"$(base.handle)->getInputCloud();")

setIndices(base::PCLBase, indices) =
    icxx"$(base.handle)->setIndices($(indices.handle));"

getIndices(base::PCLBase) = icxx"$(base.handle)->getIndices();"

function transformPointCloud(cloud_in::PointCloud, cloud_out::PointCloud,
    transform)
    icxx"pcl::transformPointCloud(*$(cloud_in.handle),
        *$(cloud_out.handle), $transform);"
end

function compute3DCentroid(cloud_in::PointCloud, vec4f)
    icxx"pcl::compute3DCentroid(*$(cloud_in.handle), $vec4f);"
end

function removeNaNFromPointCloud(cloud_in::PointCloud,
    indices::CxxStd.StdVector{Cint})
    icxx"pcl::removeNaNFromPointCloud(*$(cloud_in.handle), $indices);"
end

function removeNaNFromPointCloud(cloud_in::PointCloud, cloud_out::PointCloud,
    indices::CxxStd.StdVector{Cint})
    icxx"pcl::removeNaNFromPointCloud(*$(cloud_in.handle),
        *$(cloud_out.handle), $indices);"
end

@defpcltype PCLPointCloud2 "pcl::PCLPointCloud2"
@defptrconstructor PCLPointCloud2() "pcl::PCLPointCloud2"
@defconstructor PCLPointCloud2Val() "pcl::PCLPointCloud2"

@defpcltype Correspondence "pcl::Correspondence"
@defconstructor CorrespondenceVal() "pcl::Correspondence"
@defconstructor(CorrespondenceVal(index_query, index_match, distance),
    "pcl::Correspondence")

@defpcltype Correspondences "pcl::Correspondences"
@defptrconstructor Correspondences() "pcl::Correspondences"

length(cs::Correspondences) = convert(Int, icxx"$(cs.handle)->size();")
push!(cs::Correspondences, c::CorrespondenceVal) =
    icxx"$(cs.handle)->push_back($(handle(c)));"

@defpcltype ModelCoefficients "pcl::ModelCoefficients"
@defptrconstructor ModelCoefficients() "pcl::ModelCoefficients"
@defconstructor ModelCoefficientsVal() "pcl::ModelCoefficients"

length(coef::ModelCoefficients) =
    convert(Int, icxx"$(coef.handle)->values.size();")

@defpcltype PointIndices "pcl::PointIndices"
@defptrconstructor PointIndices() "pcl::PointIndices"
@defconstructor PointIndicesVal() "pcl::PointIndices"

length(indices::PointIndices) =
    convert(Int, icxx"$(indices.handle)->indices.size();")

include("range_image.jl")

end # module
