import CompScienceMeshes.coordtype

export numfunctions, coordtype, scalartype, assemblydata, geometry, refspace, valuetype

abstract RefSpace{T,D}

abstract AbstractSpace
abstract Space{T} <: AbstractSpace

scalartype{T}(s::RefSpace{T}) = T
scalartype{T}(s::Space{T}) = T

"""
    refspace(basis)

Returns the ReferenceSpace of local shape functions on which the basis is built.
"""
function refspace end


"""
    coordtype(s)

The scalar field over which the argument to a basis function or operator's integration
kernel are defined. This is always a salar data type, even if the function or kernel
is defined over a multi-dimensional space.
"""
coordtype{T}(::RefSpace{T}) = T
coordtype{T}(::Space{T}) = T


"""
    numfunctions(r)

Return the number of functions in a `Space` or `RefSpace`.
"""
numfunctions{T,D}(rs::RefSpace{T,D}) = D


"""
    scalartype(x)

The scalar field over which the values of a global or local basis function, or an
operator are defined. This should always be a scalar type, even if the basis or
operator takes on values in a vector or tensor space. This data type is used to
determine the `eltype` of assembled discrete operators.
"""
function scalartype end


"""
    geometry(basis)

Returns an iterable collection of geometric elements on which the functions
in `basis` are defined. The order the elements are encountered needs correspond
to the element indices used in the data structure returned by `assemblydata`.
"""
geometry(s::Space) = s.geo
basisfunction(s::Space, i) = s.fns[i]
numfunctions(space::Space) = length(space.fns)

type DirectProductSpace{T} <: AbstractSpace
    factors::Vector{Space{T}}
end

import Base.cross
cross{T}(a::Space{T}, b::Space{T}) = DirectProductSpace(Space{T}[a,b])
cross{T}(a::DirectProductSpace{T}, b::Space{T}) = DirectProductSpace(Space{T}[a.factors; b])
numfunctions(S::DirectProductSpace) = sum([numfunctions(s) for s in S.factors])
scalartype{T}(s::DirectProductSpace{T}) = T
geometry(x::DirectProductSpace) = weld(x.geo...)

type Shape{T}
  cellid::Int
  refid::Int
  coeff::T
end

immutable AssemblyData{T}
    data::Array{Tuple{Int,T},3}
end

Base.getindex(ad::AssemblyData, c, r) = ADIterator(c,r,size(ad.data,1),ad)

immutable ADIterator{T}
    c::Int
    r::Int
    I::Int
    ad::AssemblyData{T}
end

Base.start(it::ADIterator) = 1
Base.next(it::ADIterator, i) = (it.ad.data[i,it.r,it.c], i+1)
Base.done(it::ADIterator, i) = (it.I < i || it.ad.data[i,it.r,it.c][1] < 1)


function add!{T}(bf::Vector{Shape{T}}, cellid, refid, coeff)
    push!(bf, Shape(cellid, refid, coeff))
end


"""
    assemblydata(basis)

Given a Basis this function returns a data structure containing the information
required for matrix assemble. More precise the following expressions are valid
for the returned object `ad`:

```
ad[c,r,i].globalindex
ad[c,r,i].coefficient
```

Here, `c` and `r` are indices in the iterable set of geometric elements and the
set of local shape functions on each element. `i` ranges from 1 to the maximum
number of basis functions local shape function `r` on element `r` contributes
to.

For a triplet `(c,r,i)`, `globalindex` is the index in the Basis of the
`i`-th basis function that has a contribution from local shape function `r` on
element `r`. `coefficient` is the coefficient of that contribution in the
linear combination defining that basis function in terms of local shape
function.

*Note*: the indices `c` correspond to the position of the corresponding
element whilst iterating over `geometry(basis)`.
"""
function assemblydata(basis::Space)

    T = coordtype(basis)

    geo = geometry(basis)
    num_cells = numcells(geo)

    num_bfs  = numfunctions(basis)
    num_refs = numfunctions(refspace(basis))

    # determine the maximum number of function defined over a given cell
    celltonum = zeros(Int, num_cells, num_refs)
    for b in 1 : num_bfs
        for shape in basisfunction(basis, b)
            c = shape.cellid
            r = shape.refid
            celltonum[c,r] += 1
        end
    end

    # mark the active elements, i.e. elements over which
    # at least one function is defined.
    active_cell_indices = zeros(Int, num_cells)
    j = 0
    for i in 1:size(celltonum, 1)
        m = maximum(celltonum[i,j] for j in 1:num_refs)
        if m > 0
            j += 1
            active_cell_indices[j] = i
        end
    end
    resize!(active_cell_indices, j)
    num_active_cells = length(active_cell_indices)

    #elements = [simplex(cellvertices(geo,i)) for i in active_cell_indices]

    # TODO: remove dependency on explicit indexing into the cell collection
    elements = [simplex(vertices(geo, geo.faces[i])) for i in active_cell_indices]

    max_celltonum = maximum(celltonum)
    fill!(celltonum, 0)
    data = fill((0,zero(T)), max_celltonum, num_refs, num_active_cells)
    for b in 1 : num_bfs
        for shape in basisfunction(basis, b)
            c = shape.cellid
            l = searchsortedfirst(active_cell_indices, c)
            @assert 0 < l <= num_active_cells
            r = shape.refid
            w = shape.coeff
            k = (celltonum[c,r] += 1)
            data[k,r,l] = (b,w)
        end
    end

    return elements, AssemblyData(data)
end
