
#=
Current design:

The only io context is :depth, with  0 <==> toplevel.
At depth 0:
    - The quantity is shown in "long" form, possible multi-line
    - The type and metadata is explicitly shown at level 1 (if not evident from annotation)
    - Field names are shown
    - Constituent values and parameters are shown at level 1
For 1 <= depth < max_depth:
    - The quantity is shown in compact form, genrally single-line
    - No explicit type annotation, unless
    - Field names are not shown
    - Contained values are shown at depth+1
For depth == max_depth:
    - Primitive quantities are shown
    - Composite quantities are shown as type{...}(...)
=#

module ShowNice

export _show, set_depth, set_tdepth

import Base: show
using Base: print_without_params, show_datatype, io_has_tvar_name, uniontypes, show_delim_array, show_type_name, has_typevar, unwrap_unionall, print_without_params


global max_depth = 2
global max_tdepth = 4

function set_depth(d::Int)
    global max_depth
    if d>=0
        max_depth = d
    else
        error("Depth must be a non-negative integer")
    end
    nothing
end

function set_tdepth(d::Int)
    global max_tdepth
    if d>=0
        max_tdepth = d
    else
        error("Depth must be a non-negative integer")
    end
    nothing
end


_show(x) = _show(stdout, x)
_show(io::IO, x) = show(io, x)

## show types


nested(io::IO) = IOContext(io, :depth => get(io, :depth, 0) + 1)


depth(io::IO) = get(io, :depth, 0)

function _show(io::IO, ::Type{Base.Bottom})
    depth(io) == 0 && print(io, "type ")
    print(io, "Union{}")
end


function _show(io::IO, @nospecialize(t::Union))
    depth(io) == 0 && print(io, "type ")
    print(io, "Union")

    utypes = uniontypes(t)
    if depth(io) == max_tdepth
        isempty(utypes) || print(io, "{…}")
    else
        show_delim_array(nested(io), utypes, '{', ',', '}', false)
    end
end



function _show(io::IO, @nospecialize(t::DataType))
    depth(io) == 0 && print(io, "type ")
    show_type_name(io, t.name)

    n = length(t.parameters)::Int
    n==0 && return

    if depth(io) == max_tdepth
        print(io, "{…}")
    else
        print(io, '{')
        for (i, p) in enumerate(t.parameters)
            _show(nested(io), p)
            i < n && print(io, ',')
        end
        print(io, '}')
    end
end



function _show(io::IO, @nospecialize(t::UnionAll))
    if depth(io) == max_tdepth
        max_tdepth == 0 && print(io, "type ")
        ut = unwrap_unionall(t)
        show_type_name(io, ut.name)
        print(io, "{⋰}")
    else
        if t.var.name === :_ || io_has_tvar_name(io, t.var.name, t)
            counter = 1
            while true
                newname = Symbol(t.var.name, counter)
                if !io_has_tvar_name(io, newname, t)
                    newtv = TypeVar(newname, t.var.lb, t.var.ub)
                    t = UnionAll(newtv, t{newtv})
                    break
                end
                counter += 1
            end
        end

        # We don't need to worry about printing "type" here.
        # When the UnionAll is fully unwrapped, we will get a "regular" type that will
        # print "type" if appropriate.
        _show(IOContext(io, :unionall_env => t.var), t.body)
        print(io, " where ")
        _show(nested(io), t.var)
    end
    nothing
end



# TODO:  When _show is renamed to show, this method can be eliminated
function _show(io::IO, tv::TypeVar)
    in_env = (:unionall_env => tv) in io
    function show_bound(io::IO, @nospecialize(b))
        parens = isa(b,UnionAll) && !print_without_params(b) && depth(io) < max_tdepth
        parens && print(io, "(")
        _show(io, b)        #  the only difference from Base
        parens && print(io, ")")
    end
    lb, ub = tv.lb, tv.ub
    if !in_env && lb !== Union{}
        if ub === Any
            write(io, tv.name)
            print(io, ">:")
            show_bound(io, lb)
        else
            show_bound(io, lb)
            print(io, "<:")
            write(io, tv.name)
        end
    else
        write(io, tv.name)
    end
    if !in_env && ub !== Any
        print(io, "<:")
        show_bound(io, ub)
    end
    nothing
end



# Show NamedTuples with less type information
function _show(io::IO, t::NamedTuple)
    n = nfields(t)
    if n == 0
        print(io, "NamedTuple()")
    else
        typeinfo = get(io, :typeinfo, Any)
        print(io, "(")
        for i = 1:n
            print(io, fieldname(typeof(t),i), " = ")
            # show(IOContext(io, :typeinfo =>
                           # t isa typeinfo <: NamedTuple ? fieldtype(typeinfo, i) : Any),
                 # getfield(t, i))
            _show(nested(io), getfield(t, i))
            if n == 1
                print(io, ",")
            elseif i < n
                print(io, ", ")
            end
        end
        print(io, ")")
    end
end

# function show_datatype(io::IO, x::DataType)
#     istuple = x.name === Tuple.name
#     if (!isempty(x.parameters) || istuple) && x !== Tuple
#         n = length(x.parameters)::Int
#
#         # Print homogeneous tuples with more than 3 elements compactly as NTuple{N, T}
#         if istuple && n > 3 && all(i -> (x.parameters[1] === i), x.parameters)
#             print(io, "NTuple{", n, ',', x.parameters[1], "}")
#         else
#             show_type_name(io, x.name)
#             # Do not print the type parameters for the primary type if we are
#             # printing a method signature or type parameter.
#             # Always print the type parameter if we are printing the type directly
#             # since this information is still useful.
#             print(io, '{')
#             for (i, p) in enumerate(x.parameters)
#                 show(io, p)
#                 i < n && print(io, ',')
#             end
#             print(io, '}')
#         end
#     else
#         show_type_name(io, x.name)
#     end
# end


# change how structs are shown



# function show(io::IO, x::)
# 	iscompact = get(io, :compact, false)
# 	X = typeof(x)
# 	if iscompact
# 		print(io, x.delay, ": ", x.name, tuple(qsites(x)...))
# 	else
# 		println(io, X, ":")
# 		ioc = IOContext(io, :compact => true)
# 		for (i, name) in enumerate(fieldnames(X))
# 			print(ioc, "   ", name, " = ")
# 			if name == :owner && x.owner != nothing
# 				# Just show the owner's name (we don't need to see its contents)
# 				show(ioc, fullname(getfield(x, i)))
# 			else
# 				# otherwise show a compact summary of the field's value
# 				show(ioc, getfield(x, i))
# 			end
# 			println(ioc)
# 		end
# 	end
# end

end # module
