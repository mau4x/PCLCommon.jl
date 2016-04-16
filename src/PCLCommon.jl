module PCLCommon

export @boostsharedptr, @defpcltype, @defptrconstructor, @defconstructor,
    BoostSharedPtr, use_count,
    PointCloud, PointCloud2, transformPointCloud, compute3DCentroid,
    removeNaNFromPointCloud, PCLPointCloud2, Correspondence, Correspondences,
    ModelCoefficients, PointIndices, is_dense, weight, height, points

using LibPCL
using Cxx
using CxxStd

include("macros.jl")
include("std.jl")

import Base: call, eltype, length, size, getindex, setindex!, push!, convert

cxx"""
#include <pcl/common/common_headers.h>
#include <pcl/common/transforms.h>
#include <pcl/common/centroid.h>
"""

typealias BoostSharedPtr{T} cxxt"boost::shared_ptr<$T>"
use_count(s::BoostSharedPtr) = icxx"$s.use_count();"

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
    refname = symbol(name, :Ref)
    valorref = symbol(name, :ValOrRef)
    cppname = string("pcl::", name)
    cxxtdef = Expr(:macrocall, symbol("@cxxt_str"), cppname);
    rcppdef = Expr(:macrocall, symbol("@rcpp_str"), cppname);

    @eval begin
        global const $name = $cxxtdef
        global const $refname = $rcppdef
        global const $valorref = Union{$name, $refname}
        export $name
    end

    # no args constructor
    body = Expr(:macrocall, symbol("@icxx_str"), string(cppname, "();"))
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

@defpcltype PointCloud{T} "pcl::PointCloud"
@defptrconstructor PointCloud{T}() "pcl::PointCloud"
@defptrconstructor PointCloud{T}(w::Integer, h::Integer) "pcl::PointCloud"
@defconstructor PointCloudVal{T}() "pcl::PointCloud"
@defconstructor PointCloudVal{T}(w::Integer, h::Integer) "pcl::PointCloud"

eltype{T}(cloud::PointCloud{T}) = T
eltype{T}(cloud::PointCloudVal{T}) = T

function show(io::IO, cloud::PointCloudPtr)
    println(io, "$(length(cloud))-element ", string(typeof(cloud)))
    println(io, "C++ representation:")
    print(io, icxx"*$(handle(cloud));")
end

function show(io::IO, cloud::PointCloudVal)
    println(io, "$(length(cloud))-element ", string(typeof(cloud)))
    println(io, "C++ representation:")
    print(io, icxx"$(handle(cloud));")
end

import Base: similar

similar{T}(cloud::PointCloud{T}) = PointCloud{T}(width(cloud), height(cloud))

import Base: copy, deepcopy

function deepcopy{T}(cloud::PointCloud{T})
    cloud_out = PointCloud{T}()
    icxx"pcl::copyPointCloud(*$(handle(cloud)), *$(handle(cloud_out)));"
    cloud_out
end

function copy(cloud::PointCloud)
    PointCloud(icxx"auto c = $(cloud.handle); return c;")
end

"""
Converts a point cloud to a different type of point cloud

e.g. PointCloud{PointXYZRGB} to PointCloud{PointXYZ}
"""
function convert{T}(::Type{PointCloud{T}}, cloud::PointCloud)
    cloud_out = PointCloud{T}()
    icxx"pcl::copyPointCloud(*$(handle(cloud)), *$(handle(cloud_out)));"
    cloud_out
end

getindex(cloud::PointCloud, i::Integer) = icxx"$(handle(cloud))->at($i);"

function getindex(cloud::PointCloud, i::Integer, name::Symbol)
    p = icxx"&$(handle(cloud))->points[$i];"
    @eval @cxx $p->$name
end
function setindex!(cloud::PointCloud, v, i::Integer, name::Symbol)
    p = icxx"&$(handle(cloud))->points[$i];"
    vp = @eval @cxx &($p->$name)
    unsafe_store!(vp, v, 1)
end

"""Create PointCloud instance and then load PCD data."""
function (::Type{PointCloud{T}}){T}(path::AbstractString)
    handle = @boostsharedptr "pcl::PointCloud<\$T>"
    cloud = PointCloud(handle)
    @assert !isempty(path)
    pcl.load(path, cloud)
    return cloud
end

push!{T}(cloud::PointCloud{T}, p) = icxx"$(handle(cloud))->push_back($p);"

length(cloud::PointCloud) = convert(Int, icxx"$(handle(cloud))->size();")
width(cloud::PointCloud) = convert(Int, icxx"$(handle(cloud))->width;")
height(cloud::PointCloud) = convert(Int, icxx"$(handle(cloud))->height;")
is_dense(cloud::PointCloud) = icxx"$(handle(cloud))->is_dense;"
points(cloud::PointCloud) = icxx"$(handle(cloud))->points;"

length(cloud::PointCloudVal) = convert(Int, icxx"$(handle(cloud)).size();")
width(cloud::PointCloudVal) = convert(Int, icxx"$(handle(cloud)).width;")
height(cloud::PointCloudVal) = convert(Int, icxx"$(handle(cloud)).height;")
is_dense(cloud::PointCloudVal) = icxx"$(handle(cloud)).is_dense;"
points(cloud::PointCloudVal) = icxx"$(handle(cloud)).points;"

function transformPointCloud(cloud_in::PointCloud, cloud_out::PointCloud,
    transform)
    icxx"pcl::transformPointCloud(*$(handle(cloud_in)),
        *$(handle(cloud_out)), $transform);"
end

function compute3DCentroid(cloud_in::PointCloud, vec4f)
    icxx"pcl::compute3DCentroid(*$(handle(cloud_in)), $vec4f);"
end

function removeNaNFromPointCloud(cloud_in::PointCloud,
    indices::CxxStd.StdVector{Cint})
    icxx"pcl::removeNaNFromPointCloud(*$(handle(cloud_in)), $indices);"
end

function removeNaNFromPointCloud(cloud_in::PointCloud, cloud_out::PointCloud,
    indices::CxxStd.StdVector{Cint})
    icxx"pcl::removeNaNFromPointCloud(*$(handle(cloud_in)),
        *$(handle(cloud_out)), $indices);"
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

length(cs::Correspondences) = convert(Int, icxx"$(handle(cs))->size();")
push!(cs::Correspondences, c::CorrespondenceVal) =
    icxx"$(handle(cs))->push_back($(handle(c)));"

@defpcltype ModelCoefficients "pcl::ModelCoefficients"
@defptrconstructor ModelCoefficients() "pcl::ModelCoefficients"
@defconstructor ModelCoefficientsVal() "pcl::ModelCoefficients"

length(coef::ModelCoefficients) =
    convert(Int, icxx"$(handle(coef))->values.size();")

@defpcltype PointIndices "pcl::PointIndices"
@defptrconstructor PointIndices() "pcl::PointIndices"
@defconstructor PointIndicesVal() "pcl::PointIndices"

length(indices::PointIndices) =
    convert(Int, icxx"$(handle(indices))->indices.size();")

end # module