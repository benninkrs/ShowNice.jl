module ShowNice

export _show, set_depth

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


# Show a component as nested
show_nested(io, x) = _show(IOContext(io, :depth => get(io, :depth, 0) + 1), x)

# Show a component compactly
show_compact(io, x) = _show(IOContext(io, :compact => true, :depth => get(io, :depth, 0) + 1), x)

# Show a component without explicit type annotation
show_typeless(io, x) = _show(IOContext(io, :show_typeinfo => false, :depth => get(io, :depth, 0) + 1), x)


function _show(io::IO, ::Type{Base.Bottom})
    get(io, :show_typeinfo, true) && print(io, "type ")
    print(io, "Union{}")
end


function _show(io::IO, @nospecialize(t::Union))
    get(io, :show_typeinfo, true) && print(io, "type ")
    print(io, "Union")

    utypes = uniontypes(t)
    if get(io, :depth, 0) == max_tdepth
        isempty(utypes) || print(io, "{…}")
    else
        show_delim_array(typecontex(io), utypes, '{', ',', '}', false)
    end
end



function _show(io::IO, @nospecialize(t::DataType))
    get(io, :show_typeinfo, true) && print(io, "type ")
    show_type_name(io, t.name)

    n = length(t.parameters)::Int
    n==0 && return

    if  get(io, :depth, 0) == max_tdepth
        print(io, "{…}")
    else
        print(io, '{')
        # don't include type annotation in type parameters
        for (i, p) in enumerate(t.parameters)
            show_typeless(io, p)
            i < n && print(io, ',')
        end
        print(io, '}')
    end
end



function _show(io::IO, @nospecialize(t::UnionAll))
    get(io, :show_typeinfo, true) && print(io, "type ")

    if get(io, :depth, 0) == max_tdepth
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
        # don't increase depth for nested UnionAll's
        _show(IOContext(io, :unionall_env => t.var, :show_typeinfo => false), t.body)
        print(io, " where ")
        show_typeless(io, t.var)
    end
    nothing
end



# TODO:  When _show is renamed to show, this method can be eliminated
function _show(io::IO, tv::TypeVar)
    in_env = (:unionall_env => tv) in io
    function show_bound(io::IO, @nospecialize(b))
        parens = isa(b,UnionAll) && !print_without_params(b) && (get(io, :depth, 0) < max_tdepth)
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
            show_compact(io, getfield(t, i))
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
