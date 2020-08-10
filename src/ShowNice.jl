
#=

Here's how Base works:
1. show(x) = show(stdout, x)
2. show(io, x) is meant for plain text display
3. customize show(io, mime, x) for other mime types.
    show(io, MIME"text/plain", x) calls show(io, x)

4. print(x) = print(stdout, x)
5. print(io, x) falls back to show(io, MIME"text/plain", x)

6. string(x) defaults to print(Buffer, x)


Current design:

There is one context parameter, :depth, which indicates the level of nested structure.

At depth 0:
    - The quantity is shown in "long" form, possibly multi-line
    - If the formatting of the data does not indicate the type, the type and metadata
        (e.g. array size) are explicitly shown at depth 1
    - Field names are shown
    - Constituent values are shown at level 1
For 1 <= depth < structdepth:
    - The quantity is shown in compact form, generally single-line
    - Datatypes are shown as type_name(field_values...)
    - Contained values are shown at depth+1
For depth == maxdepth:
    - Primitive quantities are shown
    - Composite quantities are shown as type{...}(...)

There are currently two different values of maxdepth, one for values and one for types
=#


# TODO:  Continue Implement showing of Arrays
#   - This will not be simple; there is a lot of infrastructure in place.
#   - Note, some deep methods in Base resort to string(T), which loses context
#   - need to fine tune choosing how many rows of matrices to show
#   - figure something clever for ND-s
#
# TODO:  Improve showing of UnionAlls
#   - When possible, abbreviate "A{N} where N<:T" as "A{<:T}"
#       - N must not appears as a bound on any other typevars
#   - Don't show "where N" if N only appears at a depth that is not shown

module ShowNice

export test_show

import Base: show
using Base: print_without_params, show_datatype, io_has_tvar_name, uniontypes, has_typevar, unwrap_unionall, print_without_params, show_circular


function test_show()

t = (2, 'a', 3.1416)

show(t)
println()
show(typeof(t))
println()


nt = (name = "Mary", age = 20)
show(nt)
println()
show(typeof(nt))
println()

end


#-------------------------------------------------------------
## Infrastructure

global structdepth = 2          # the maximum depth of nested structure levels to show
global typedepth = 4            # the maximum depth of nested types to show

# Set the maximum number of structural levels to show
function structdepth!(d::Int)
    global structdepth
    if d>=0
        structdepth = d
    else
        error("Depth must be a non-negative integer")
    end
    nothing
end

function typedepth!(d::Int)
    global typedepth
    if d>=0
        typedepth = d
    else
        error("Depth must be a non-negative integer")
    end
    nothing
end


depth(io::IO) = get(io, :depth, 0)

maxdepth(io::IO) =  get(io, :istype, false) ? typedepth : structdepth


function deeper(io::IO)
    depth(io) == 0 ?
        IOContext(io, :depth => get(io, :depth, 0) + 1) :
        IOContext(io, :compact => true, :depth => get(io, :depth, 0) + 1)
end
#--------------------------------------------------------------
## Fallback

# _show(x) = _show(stdout, x)


#-------------------------------------------------------------
## show types

# Somes types (e.g. Union, UnionAll, Tuple) are actually instances of DataType


function show(io::IO, @nospecialize t::Type)
    depth(io) == 0 && print(io, "type ")
    show_type(IOContext(io, :istype => true), t)
end

# Show with surrounding parentheses if type is a UnionAll
function show_protected(io::IO, @nospecialize t)
    if isa(t, UnionAll)
        print(io, '(')
        show(io, t)
        print(io, ')')
    else
        show(io, t)
    end
end


function show_type(io::IO, t)
    @warn "Unmatched method for type"
    Base.show_type_name(io, t.name)
end


# Default display of a type:  type_name{parameters}
#show_type(io::IO, @nospecialize t) = show_type_default(io, t)
function show_type(io::IO, @nospecialize t)
    n = length(t.parameters)::Int

    # Print homogeneous tuples with >2 elements compactly as NTuple{N, T}
    if isa(t, Tuple) && n > 2 && all(i -> (t.parameters[1] === i), t.parameters)
        if depth(io) >= maxdepth(io)
            print(io, "NTuple{…}")
        else
            print(io, "NTuple{", n, ',', t.parameters[1], "}")
        end
        return
    end

    # Otherwise, display type name and parameters
    Base.show_type_name(io, t.name)

    n = length(t.parameters)::Int
    n==0 && return

    if depth(io) >= maxdepth(io)
        print(io, "{…}")
    else
        print(io, '{')
        for (i, p) in enumerate(t.parameters)
            show(deeper(io), p)
            i < n && print(io, ',')
        end
        print(io, '}')
    end
end

# OOPS!  NTuple will dispatch to ::Type{<:Tuple}, even though it is a UnionAll.



function show_type(io::IO, ::Type{Base.Bottom})
    print(io, "Union{}")
end


function show_type(io::IO, @nospecialize t::Union)
    print(io, "Union")

    utypes = uniontypes(t)
    if depth(io) >= maxdepth(io)
        isempty(utypes) || print(io, "{…}")
    else
        Base.show_delim_array(deeper(io), utypes, '{', ',', '}', false)
    end
end


# function show(io::IO, @nospecialize(x))
#     if isstructtype(typeof(x))
#         show_struct(io, x)
#     else
#         show(io, x)
#     end
# end




function show_type(io::IO, @nospecialize t::UnionAll)
    #@info "show(UnionAll) over $(t.var)"
    if depth(io) >= maxdepth(io)
        ut = unwrap_unionall(t)
        Base.show_type_name(io, ut.name)
        print(io, "{⋰}")
    else
        # Determine unbound type parameters.
        # In a nested UnionAll, IO will contain names of typevars already identified.
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
        # Show the UnionAll recursively
        show_type(IOContext(io, :unionall_env => t.var), t.body)
        print(io, " where ")
        show(deeper(io), t.var)
    end
    nothing
end



# # TODO:  When _show is renamed to show, this method can be eliminated
# function _show(io::IO, tv::TypeVar)
#     in_env = (:unionall_env => tv) in io
#     function show_bound(io::IO, @nospecialize(b))
#         parens = isa(b,UnionAll) && !print_without_params(b) && depth(io) < typedepth
#         parens && print(io, "(")
#         _show(io, b)        #  the only difference from Base
#         parens && print(io, ")")
#     end
#     lb, ub = tv.lb, tv.ub
#     if !in_env && lb !== Union{}
#         if ub === Any
#             write(io, tv.name)
#             print(io, ">:")
#             show_bound(io, lb)
#         else
#             show_bound(io, lb)
#             print(io, "<:")
#             write(io, tv.name)
#         end
#     else
#         write(io, tv.name)
#     end
#     if !in_env && ub !== Any
#         print(io, "<:")
#         show_bound(io, ub)
#     end
#     nothing
# end

#-----------------------------------------------------------------
## Show values

# Can be eliminated
# _show(io::IO, @nospecialize(x::String)) = show(io, x)


# Default (e.g. structs)
function show(io::IO, @nospecialize x)
    t = typeof(x)
    nf = nfields(x)
    nb = sizeof(x)
    if nf ==0 && nb > 0
        @info x
        error("Have a quantity with 0 fields but nonzero size.  What does that mean?")
    end

    if depth(io) >= maxdepth(io)
        # show no structure
        show(deeper(io), t)
        nf == 0 ? print(io, "()") : print(io, "(…)")
    elseif depth(io) == 0
        # Show nested structure
        show(deeper(io), t)
        println(io, ":")
        if nf != 0
            if !show_circular(io, x)
                recur_io = IOContext(deeper(io), Pair{Symbol,Any}(:SHOWN_SET, x),
                                     Pair{Symbol,Any}(:typeinfo, Any))
                for i in 1:nf
                    fname = fieldname(t, i)
                    print(io, "   ", fname, " = ")
                    if !isdefined(x, fname)
                        print(io, undef_ref_str)
                    else
                        show(recur_io, getfield(x, i))
                        println(io)
                    end
                end
            end
        end
    else
        # Show in compact form
        show(deeper(io), t)        # show just t.name?
        print(io, '(')
        if nf != 0
            if !show_circular(io, x)
                recur_io = IOContext(deeper(io), Pair{Symbol,Any}(:SHOWN_SET, x),
                                     Pair{Symbol,Any}(:typeinfo, Any))
                for i in 1:nf
                    f = fieldname(t, i)
                    if !isdefined(x, f)
                        print(io, undef_ref_str)
                    else
                        show(recur_io, getfield(x, i))
                    end
                    if i < nf
                        print(io, ", ")
                    end
                end
            end
        end
        print(io,')')
    end
end



function show(io::IO, @nospecialize(x::Tuple))
    nf = length(x)
    if depth(io) >= maxdepth(io)
        # show no structure
        nf == 0 ? print(io, "()") : print(io, "(…)")
    else
        print(io, '(')
        if nf != 0
            if !show_circular(io, x)
                recur_io = IOContext(deeper(io), Pair{Symbol,Any}(:SHOWN_SET, x),
                                     Pair{Symbol,Any}(:typeinfo, Any))
                for i in 1:nf
                    if !isdefined(x, i)
                        print(io, undef_ref_str)
                    else
                        show(recur_io, getfield(x, i))
                    end
                    if i < nf
                        print(io, ", ")
                    elseif nf == 1
                        print(io, ',')
                    end
                end
            end
        end
        print(io,')')
    end
end


# Don't show type of NamedTUples
function show(io::IO, @nospecialize t::NamedTuple)
    n = nfields(t)
    if depth(io) >= maxdepth(io)
        # show no structure
        n == 0 ? print(io, "(;)") : print(io, "(;…)")
    else
        if n == 0
            print(io, "(;)")
        else
            #typeinfo = get(io, :typeinfo, Any)
            print(io, "(")
            for i = 1:n
                print(io, fieldname(typeof(t),i), " = ")
                # show(IOContext(io, :typeinfo =>
                # t isa typeinfo <: NamedTuple ? fieldtype(typeinfo, i) : Any),
                # getfield(t, i))
                show(deeper(io), getfield(t, i))
                if n == 1
                    print(io, ",")      # add a comma to indicate it's a tuple
                elseif i < n
                    print(io, ", ")
                end
            end
            print(io, ")")
        end
    end
end


size2string(d) = isempty(d) ? "0-dim" :
                 length(d) == 1 ? "$(d[1])×" :
                 join(map(string,d), '×')


function show(io::IO, A::AbstractArray)
    if depth(io) == 0
        # print as usual
        print(io, size2string(size(A)), " ")
        show(deeper(io), typeof(A))
        # show indices?

        if !isempty(A)
            println(io, ':')
            # TODO:  This still shows element types, make it not
            Base.print_array(IOContext(io, :typeinfo => eltype(A)), A)
        end

    # show summary only if:
    #  we're at maxdepth, OR
    #  we're at maxdepth-1 and nothing useful would be shown about its elements
    elseif depth(io) >= maxdepth(io) || depth(io) == maxdepth(io)-1 && eltype(A) <: Union{Tuple, NamedTuple}
        # show as M×N array_type[…]
        print(io, size2string(size(A)), " ")
        show_protected(deeper(io), eltype(A))
        length(A) == 0 ? print(io, "[]") : print(io, "[…]")
    else
        # print inline
        print(io, '[')
        truncated = print_array_inline(io, A, 8)
        print(io, ']')
        truncated && print(io, " (", size2string(size(A)), ")")
    end
end


function print_array_inline(io::IO, A::AbstractVector, max_show, delim = ',')
    # Show vectors as  [a1, a2, a3, ... a_n]
    # Show matrices as [a11 a12 a13; a21 a22 a23; ... ]
    # Show nd-arrays as nested matrices
    # If we can show all the elements, do so.
    n_show = length(A) <= max_show ? length(A) : max_show-1
    for i = 1:n_show
        show(deeper(io), A[i])
        i < n_show && print(io, delim, " ")
    end
    trunc = false
    if n_show < length(A)
        trunc = true
        print(io, " … ")
        show(deeper(io), A[end])
    end
    trunc
end


function print_array_inline(io::IO, A::AbstractMatrix, max_show)
    # Show vectors as  [a1, a2, a3, ... a_n]
    # Show matrices as [a11 a12 a13; a21 a22 a23; ... ]
    # Show nd-arrays as nested matrices
    # If we can show all the elements, do so.
    # number of rows to show
    if length(A) <= max_show
        n_show = size(A,1)
        row_length = size(A,2)
    else
        r = sqrt(length(A) / max_show)
        row_length = max(Int(ceil(size(A,1)/r)), 2)
        max_rows = max(Int(floor(max_show / row_length)), 2)
        n_show =  size(A,2) <= max_rows ? size(A,2) : max_rows - 1
    end
    # @info max_rows, n_show, row_length
    trunc = false
    for i = 1:n_show
        trunc |= print_array_inline(io, A[i,:], row_length, "")
        i < size(A,1) && print(io, ";  ")
    end
    if n_show < size(A,1)
        trunc = true
        print(io, "… ;  ")
        print_array_inline(io, A[end,:], row_length, "")
    end
    trunc
end

function print_array_inline(io::IO, A::AbstractArray, max_show)

end


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
