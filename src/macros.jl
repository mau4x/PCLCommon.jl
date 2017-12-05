using Cxx
using DocStringExtensions

function remove_type_annotation(e)
    if isa(e, Symbol)
        return e
    elseif isa(e, Expr)
        return remove_type_annotation(e.args[1])
    else
        @assert false
    end
end

function remove_type_annotation(args::Vector)
    ret_args = Any[]
    for e in args
        push!(ret_args, remove_type_annotation(e))
    end
    ret_args
end

"""
$(SIGNATURES)

creates boost::shared_ptr expression (for package development)

**Parameters**

- `name` : C++ type name
- `args` : argments will be passed to constructor

template parameters in 1st argment and embedding expression in 2nd argment
must be escaped.

**Returns**

- `handle` : C++ boost shared pointer of a given C++ type name and argments

**Example**

```julia
handle = @boostsharedptr(
    "pcl::visualization::PointCloudColorHandlerRGBField<\\\$T>",
    "\\\$(cloud.handle)")
```
"""
macro boostsharedptr(name, args...)
    @assert length(args) <= 1
    if length(args) > 0 && args[1] != nothing
        Expr(:macrocall, Symbol("@icxx_str"), """
        boost::shared_ptr<$name>(new $name($(args...)));""")
    else
        Expr(:macrocall, Symbol("@icxx_str"), """
        boost::shared_ptr<$name>(new $name());""")
    end
end

"""
$(SIGNATURES)

A macro to define PCL convenient types. Mostly intended to be used by package
development.

**Parameters**

- `expr` : Julia type name (can have type params)
- `cxxname` : C++ type name

**Example**

```julia
@defpcltype PointCloud{T} "pcl::PointCloud"

```

which defines Julia wrapper types for C++ types:

- **PointCloudPtr{T}**: boost shared pointer of `pcl::PointCloud<T>` (i.e.
  `pcl::PointCloud<T>::Ptr`) wrapper
- **PointCloudVal{T}**: `pcl::PointCloud<T>` value wrapper
- **PointCloud{T}**: type aliased to `PointCloudPtr{T}`

and also Cxx types:

- **pclPointCloudPtr{T}**: `pcl::PointCloud<T>::Ptr`
- **pclPointCloudVal{T}**: `pcl::PointCloud<T>`

With the combination of [`@defptrconstructor`](@ref), you can then use
`pcl::PointCloud<T>::Ptr` (entirely used in PCL tutorials) as follows:

```julia
cloud = PointCloud{PointXYZ}()
```

Note that `PointCloud{T}` is a Julia wrapper, you can get the C++ representation
as `PCLCommon.handle(cloud)` or use `handle = pclPointCloud{PointXYZ}()` which
returns C++ type.
"""
macro defpcltype(expr, cxxname)
    if isa(expr, Expr) && (expr.head == :comparison || expr.head == :<:)
        has_supertype = true
        jlname = expr.args[1]
        super_name = (expr.args[2] == :(<:)) ? expr.args[3] : expr.args[2]
    else
        has_supertype = false
        jlname = expr
    end

    # build names
    if isa(jlname, Expr) && jlname.head == :curly
        jlname_noparams = jlname.args[1]
        jlname_noparams_ptr = Symbol(jlname_noparams, :Ptr)
        jlname_ptr = copy(jlname)
        jlname_noparams_val = Symbol(jlname_noparams, :Val)
        jlname_ptr.args[1] = jlname_noparams_ptr
        jlname_val = copy(jlname)
        jlname_val.args[1] = jlname_noparams_val
        pclname_ptr = copy(jlname_ptr)
        pclname_ptr.args[1] = Symbol(:pcl, pclname_ptr.args[1])
        pclname_val = copy(jlname_val)
        pclname_val.args[1] = Symbol(:pcl, pclname_val.args[1])
    else
        jlname_noparams = jlname
        jlname_noparams_ptr = Symbol(jlname_noparams, :Ptr)
        jlname_ptr = jlname_noparams_ptr
        jlname_noparams_val = Symbol(jlname_noparams, :Val)
        jlname_val = jlname_noparams_val
        pclname_ptr = Symbol(:pcl, jlname_ptr)
        pclname_val = Symbol(:pcl, jlname_val)
    end

    # build cxxt str
    if isa(jlname, Expr) && jlname.head == :curly
        type_params = jlname.args[2:end]
        esc_type_params = map(x -> string("\$", x), type_params)
        cxxtstr_body = string(cxxname, "<", join(esc_type_params, ','), ">")

        cxxname_with_params_str = string(cxxname, "<", join(type_params, ','), ">")
    else
        cxxtstr_body = string(cxxname)

        cxxname_with_params_str = cxxtstr_body
    end
    cxxtstr_ptr_body = string("boost::shared_ptr<", cxxtstr_body, ">")
    cxxptrtype = Expr(:macrocall, Symbol("@cxxt_str"), cxxtstr_ptr_body)
    cxxvaltype = Expr(:macrocall, Symbol("@cxxt_str"), cxxtstr_body)

    # For docs
    jlname_noparams_ptrstr = string(jlname_noparams_ptr)

    # type body
    ptrtype_body = Expr(:(::), :handle, cxxptrtype)
    valtype_body = Expr(:(::), :handle, cxxvaltype)

    if has_supertype
        ptrtype_def = Expr(:comparison, jlname_ptr, :(:<), super_name)
        valtype_def = Expr(:comparison, jlname_val, :(:<), super_name)
    else
        ptrtype_def = jlname_ptr
        valtype_def = jlname_val
    end

    typdef = has_supertype ? quote
        @doc """
        Pointer representation for `$($cxxname_with_params_str)` in C++
        """ type $jlname_ptr <: $super_name
            $ptrtype_body
        end

        @doc """
        Value representation for `$($cxxname_with_params_str)` in C++
        """ type $jlname_val <: $super_name
            $valtype_body
        end
    end : quote
        @doc """
        Pointer representation for `$($cxxname_with_params_str)` in C++
        """ type $jlname_ptr
            $ptrtype_body
        end

        @doc """
        Value representation for `$($cxxname_with_params_str)` in C++
        """ type $jlname_val
            $valtype_body
        end
    end

    typaliases = quote
        @doc """
        Pointer representation for `$($cxxname_with_params_str)` in C++

        typealias of [`$($jlname_noparams_ptrstr)`](@ref)
        """ $jlname = $jlname_ptr
        $pclname_ptr = $cxxptrtype
        $pclname_val = $cxxvaltype
    end

    def = esc(quote
        $typdef
        $typaliases
        @inline handle(x::$jlname_noparams_ptr) = x.handle
        @inline handle(x::$jlname_noparams_val) = x.handle
        use_count(x::$jlname_noparams_ptr) = icxx"$(x.handle).use_count();"
        Base.pointer(x::$jlname_noparams_ptr) = convert(Ptr{Void}, icxx"$(x.handle).get();")
    end)

    #@show def
    #return nothing
    return def
end

"""
$(SIGNATURES)

Defines convenient constructor for point types

**Parameters**

- `expr` : Constructor expression
- `cxxname` : C++ type name

**Examples**

```julia
@defptrconstructor PointCloud{PointT}() "pcl::PointCloud"
```

"""
macro defptrconstructor(expr, cxxname)
    _defconstructor_impl(expr, cxxname, true)
end

"""
$(SIGNATURES)

Defines convenient constructor for value types

**Parameters**

- `expr` : Constructor expression
- `cxxname` : C++ type name

**Examples**

```julia
@defptrconstructor PointCloudVal{PointT}() "pcl::PointCloud"
```

"""
macro defconstructor(expr, cxxname)
    _defconstructor_impl(expr, cxxname, false)
end

function _defconstructor_impl(expr::Expr, cxxname, is_sharedptr::Bool)
    @assert expr.head == :call
    typname = expr.args[1]

    if isa(typname, Expr) && typname.head == :curly
        type_params = typname.args[2:end]
        esc_type_params = map(x -> string("\$", x), type_params)
        cxxconstructor_def = string(cxxname, "<",
            join(esc_type_params, ','), ">")
    else
        type_params = nothing
        cxxconstructor_def = string(cxxname)
    end

    cxxconstructor_args = ""
    if length(expr.args) > 1
        simplified_args = remove_type_annotation(expr.args[2:end])
        esc_args = map(x -> string("\$", x), simplified_args)
        cxxconstructor_args = join(esc_args, ',')
    end

    # Function args
    fargs = length(expr.args) > 1 ? expr.args[2:end] : nothing
    fargs = Any[Expr(:(::), Expr(:curly, :Type, typname))]
    if length(expr.args) > 1
        for e in expr.args[2:end]
            push!(fargs, e)
        end
    end

    # build shared pointer or value instantiation expr
    cxxvalnew = Expr(:macrocall, Symbol("@icxx_str"),
        string(cxxconstructor_def, "(", cxxconstructor_args, ");"))
    handledef = is_sharedptr ? quote
        @boostsharedptr $cxxconstructor_def $cxxconstructor_args
    end : cxxvalnew

    typname_no_params = isa(typname, Symbol) ? typname : typname.args[1]

    # Function body
    body = quote
        handle = $handledef
        $(typname_no_params)(handle)
        # $(typname)(handle)
    end

    if type_params != nothing
        callexpr = Expr(:call, Expr(:curly, fargs[1], type_params...),
            fargs[2:end]...)
    else
        callexpr = Expr(:call, fargs...)
    end

    # Function definition
    def = esc(Expr(:function, callexpr, Expr(:block, body)))
    # @show def
    # return nothing

    return def
end
