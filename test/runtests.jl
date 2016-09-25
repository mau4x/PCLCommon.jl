using PCLCommon
using Cxx
using Base.Test

import PCLCommon: PointCloudVal, StdVector, isOrganized, width, height, is_dense


@testset "@boostsharedptr" begin
    v = @boostsharedptr "std::vector<double>"
    @test icxx"$v->size();" == 0
    v = @boostsharedptr "std::vector<double>" "10"
    @test icxx"$v->size();" == 10
end

# TODO: The test below will fail in @testset (but why?)
let
    cloud = PointCloud{PointXYZ}()
    @test use_count(cloud) == 1
    cloud_copy = copy(cloud)
    @test use_count(cloud) == 2
    @test use_count(cloud_copy) == 2
    cloud_copy = 0
    gc()
    @test use_count(cloud) == 1
    @test pointer(cloud) != C_NULL
end

@testset "Point types" begin
    p = PointXYZ()
    @test icxx"$p.x;" == 0.0f0
    @test icxx"$p.y;" == 0.0f0
    @test icxx"$p.z;" == 0.0f0

    p = PointXYZI()
    @test icxx"$p.intensity;" == 0.0f0

    p = PointXYZRGBA()
    @test icxx"$p.r;" == 0.0f0
    @test icxx"$p.g;" == 0.0f0
    @test icxx"$p.b;" == 0.0f0
    @test icxx"$p.a;" == 0xff
end

@testset "PoindCloud" begin
    cloudxyz = PointCloud{PointXYZ}()
    @test (@cxx (cloudxyz.handle)->get()) != C_NULL
    @test !isOrganized(cloudxyz)
    cloudxyzi = PointCloud{PointXYZI}()
    @test (@cxx (cloudxyzi.handle)->get()) != C_NULL

    cloud = PointCloud{PointXYZ}(2,3)
    @test width(cloud) == 2
    @test height(cloud) == 3
    @test isOrganized(cloud)

    @test typeof(PointCloud{eltype(cloud)}()) == typeof(cloud)
    @test typeof(similar(cloud)) == typeof(cloud)

    cloud = PointCloud{PointXYZ}()
    push!(cloud, PointXYZ(5,5,5))
    @test length(cloud) == 1
end

@testset "PointCloudVal" begin
    cloud = PointCloudVal{PointXYZ}(2,3)
    @test length(cloud) == 6
    @test width(cloud) == 2
    @test height(cloud) == 3
    @test is_dense(cloud)
    @test isOrganized(cloud)
end

@testset "std::vector" begin
    @test length(icxx"std::vector<double>();") == 0
    for n in 0:10
        @test length(icxx"return std::vector<double>($n);") == n
    end
end

@testset "pcl::RangeImage" begin
    # http://pointclouds.org/documentation/tutorials/range_image_creation.php
    cloud = PointCloud{PointXYZ}()
    for y in -0.5:0.01:0.5
        for z in -0.5:0.01:0.5
            push!(cloud, PointXYZ(2.0-y,y,z))
        end
    end
    icxx"$(cloud.handle)->width = $(length(cloud));"
    icxx"$(cloud.handle)->height = 1;"

    angularResolution = 1.0 * pi/180
    maxAngleWidth = 360 * pi/180
    maxAngleHeight = 180 * pi/180
    sensorPose = icxx"(Eigen::Affine3f)Eigen::Translation3f(0.0, 0.0, 0.0);"
    coordinate_frame = CAMERA_FRAME
    noiseLevel = 0.0
    minRange = 0.0
    borderSize = 1

    rangeImage = RangeImage()
    createFromPointCloud(rangeImage, cloud, angularResolution, maxAngleWidth,
        maxAngleHeight, sensorPose, coordinate_frame, noiseLevel,
        minRange, borderSize)
    @test_approx_eq PCLCommon.getAngularResolution(rangeImage) angularResolution
end
