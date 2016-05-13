export RangeImage, CoordinateFrame, createFromPointCloud

const CoordinateFrame = Cxx.CppEnum{symbol("pcl::RangeImage::CoordinateFrame"),UInt32}

for name in [
    :CAMERA_FRAME,
    :LASER_FRAME,
    ]
    ex = Expr(:macrocall, Symbol("@icxx_str"), string("pcl::RangeImage::", name, ";"))
    @eval begin
        global const $name = $ex
        export $name
    end
end

@defpcltype RangeImage "pcl::RangeImage"
@defptrconstructor RangeImage() "pcl::RangeImage"
@defconstructor RangeImageVal() "pcl::RangeImage"

function createFromPointCloud(ri::RangeImage, cloud::PointCloud,
        angular_resolution=deg2rad(0.5), max_angle_width=deg2rad(360.0),
        max_angle_height=deg2rad(180.0),
        sensor_pose=icxx"Eigen::Affine3f::Identity();",
        coordinate_frame=CAMERA_FRAME,
        noise_level=0.0, min_range=0.0, border_size=0)
    icxx"""
    $(ri.handle)->createFromPointCloud(*$(cloud.handle),
        $angular_resolution, $max_angle_width,
        $max_angle_height, $sensor_pose,
        $coordinate_frame, $noise_level, $min_range, $border_size);
    """
end

for f in [
        :getAngularResolution,
        :getAngularResolutionX,
        :getAngularResolutionY,
        ]
    body = Expr(:macrocall, Symbol("@icxx_str"), "\$(ri.handle)->$f();")
    @eval $f(ri::RangeImage) = $body
end
