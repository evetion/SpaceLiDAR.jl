abstract type AbstractTable end
struct Table{K,V,G} <: AbstractTable
    table::NamedTuple{K,V}
    granule::G
    function Table(table::NamedTuple{K,V}, g::G) where {K,V,G}
        new{K,typeof(values(table)),G}(table, g)
    end
end
_table(t::Table) = getfield(t, :table)
_granule(t::AbstractTable) = getfield(t, :granule)
Base.size(table::Table) = size(_table(table))
Base.getindex(t::Table, i) = _table(t)[i]
Base.show(io::IO, t::Table) = _show(io, t)
Base.show(io::IO, ::MIME"text/plain", t::Table) = _show(io, t)
Base.haskey(table::Table, x) = haskey(_table(table), x)
Base.keys(table::Table) = keys(_table(table))
Base.values(table::Table) = values(_table(table))
Base.length(table::Table) = length(_table(table))
Base.iterate(table::Table, args...) = iterate(_table(table), args...)
Base.merge(table::Table, others...) = Table(merge(_table(table), others...), _granule(table))
Base.parent(table::Table) = _table(table)

function Base.getproperty(table::Table, key::Symbol)
    getproperty(_table(table), key)
end
Base.propertynames(table::Table) = propertynames(_table(table))

function _show(io, t::Table)
    g = _granule(t)
    isnothing(g) ? print(io, "Table") : print(io, "Table of $g")
end

struct PartitionedTable{T<:Tuple{Vararg{NamedTuple}},G} <: AbstractTable
    tables::T
    granule::G
end
PartitionedTable(t::NamedTuple) = PartitionedTable((t,))
Base.size(t::PartitionedTable) = (length(t.tables),)
Base.length(t::PartitionedTable) = length(t.tables)
Base.getindex(t::PartitionedTable, i) = t.tables[i]
Base.lastindex(t::PartitionedTable) = length(t.tables)
Base.show(io::IO, t::PartitionedTable) = _show(io, t)
Base.show(io::IO, ::MIME"text/plain", t::PartitionedTable) = _show(io, t)
Base.iterate(table::PartitionedTable, args...) = iterate(table.tables, args...)
Base.merge(table::PartitionedTable, others...) = PartitionedTable(merge.(table.tables, Ref(others...)), _granule(table))
Base.parent(table::PartitionedTable) = collect(getfield(table, :tables))

function Base.getproperty(table::PartitionedTable, key::Symbol)
    key in (:tables, :granule) && return getfield(table, key)
    reduce(vcat, [getproperty(t, key) for t in getfield(table, :tables)])
end
Base.propertynames(table::PartitionedTable) = propertynames(first(getfield(table, :tables)))

function _show(io, t::PartitionedTable)
    g = _granule(t)
    isnothing(g) ? print(io, "Table with $(length(t.tables)) partitions") :
        print(io, "Table with $(length(t.tables)) partitions of $g")
end

function add_info(table::PartitionedTable)
    it = info(table.granule)
    nts = map(table.tables) do t
        nt = NamedTuple(zip(keys(it), Fill.(values(it), length(first(t)))))
        merge(t, nt)
    end
    return PartitionedTable(nts, table.granule)
end

function add_id(table::PartitionedTable)
    nts = map(table.tables) do t
        nt = (; id = Fill(id(table.granule), length(first(t))))
        merge(t, nt)
    end
    return PartitionedTable(nts, table.granule)
end

function add_id(table::Table)
    g = _granule(table)
    t = _table(table)
    nt = (; id = Fill(id(g), length(first(t))))
    nts = merge(t, nt)
    return Table(nts, g)
end

function add_info(table::Table)
    g = _granule(table)
    it = info(g)
    t = _table(table)
    nt = NamedTuple(zip(keys(it), Fill.(values(it), length(first(t)))))
    nts = merge(t, nt)
    return Table(nts, g)
end

_info(g::Granule) = merge((; id = id(g)), info(g))

DataAPI.metadatasupport(::Type{<:AbstractTable}) = (read = true, write = false)
function DataAPI.metadatakeys(t::AbstractTable)
    g = _granule(t)
    isnothing(g) ? String[] : map(String, keys(pairs(_info(g))))
end
function DataAPI.metadata(t::AbstractTable, k; style::Bool = false)
    g = _granule(t)
    isnothing(g) && throw(ArgumentError("Table has no granule metadata"))
    if style
        getfield(_info(g), Symbol(k)), :default
    else
        getfield(_info(g), Symbol(k))
    end
end

Tables.istable(::Type{<:Granule}) = true
Tables.columnaccess(::Type{<:Granule}) = true
Tables.partitions(g::Granule) = points(g)
Tables.columns(g::Granule) = Tables.CopiedColumns(joinpartitions(g))

Tables.istable(::Type{<:PartitionedTable}) = true
Tables.columnaccess(::Type{<:PartitionedTable}) = true
Tables.partitions(g::PartitionedTable) = getfield(g, :tables)
Tables.columns(g::PartitionedTable) = Tables.CopiedColumns(joinpartitions(g))

# ICESat has no beams, so no need for partitions
Tables.istable(::Type{<:ICESat_Granule}) = true
Tables.columnaccess(::Type{<:ICESat_Granule}) = true
Tables.columns(g::ICESat_Granule) = getfield(points(g), :table)

Tables.istable(::Type{<:Table}) = true
Tables.columnaccess(::Type{<:Table}) = true
Tables.columns(g::Table) = getfield(g, :table)

# ─── GranuleSource: a granule-backed H5Table source ──────────────────────────
# Wraps a `Granule` together with its open `HDF5.File` (and, for multi-track
# instruments, the track this table belongs to). This is what lets a generic,
# read-only `H5Table` keep its provenance: granule id/info become table
# metadata, and `resolve_variable` can pull a known column on demand using the
# granule's `default_variables` template (see operations.jl auto-pull).
struct GranuleSource{G<:Granule}
    granule::G
    file::HDF5.File
    track::String
end
GranuleSource(g::Granule, file::HDF5.File) = GranuleSource(g, file, "")

H5Tables.h5handle(s::GranuleSource) = s.file
H5Tables.source_metadata(s::GranuleSource) =
    Dict{String,Any}(string(k) => v for (k, v) in pairs(_info(s.granule)))

"""Resolve `name` to a fully-built [`Variable`](@ref) using the granule's
`default_variables` template, prefixed with this source's track. Returns
`nothing` if the granule has no such column or it is absent from the file."""
function H5Tables.resolve_variable(s::GranuleSource, name::Symbol)
    dvars = default_variables(s.granule)
    i = findfirst(v -> v.name == name, dvars)
    isnothing(i) && return nothing
    dv = dvars[i]
    fullpath = isempty(s.track) ? dv.path : "$(s.track)/$(dv.path)"
    haskey(s.file, fullpath) || return nothing
    return H5Tables.make_variable(s.file, name, fullpath; transform = dv.f)
end

"""The granule backing a table, or `nothing` for a sourceless/generic table."""
granuleof(t::H5Tables.H5Table) = _granuleof(getfield(t, :f))
function granuleof(t::H5Tables.PartitionedH5Table)
    isempty(t.tables) ? nothing : granuleof(t.tables[1])
end
_granuleof(s::GranuleSource) = s.granule
_granuleof(::Any) = nothing

# ─── collect: materialize H5Table into SpaceLiDAR Table types ─────────────────

Base.collect(t::H5Tables.H5Table) = Table(Tables.columntable(t), granuleof(t))
function Base.collect(t::H5Tables.PartitionedH5Table)
    nts = Tuple(Tables.columntable(p) for p in Tables.partitions(t))
    PartitionedTable(nts, granuleof(t))
end


function materialize!(df::DataFrame)
    for (name, col) in zip(names(df), eachcol(df))
        if col isa CategoricalArray || eltype(col) <: CategoricalValue
            df[!, name] = String.(col)
        elseif col isa Fill
            df[!, name] = Vector(col)
        end
    end
    df
end

# ─── table(::Granule) → H5Table dispatch ─────────────────────────────────────

default_tracks(::ICESat2_Granule) = icesat2_tracks
default_tracks(::GEDI_Granule) = gedi_tracks
default_tracks(::ICESat_Granule) = ()

"""
    table(g::Granule; tracks=default_tracks(g), variables=default_variables(g))

Open the granule file and return an H5Table (or PartitionedH5Table) using
the specified variables and `default_attributes` for the granule type.

For multi-track instruments (ICESat-2, GEDI), returns a `PartitionedH5Table`.
For single-track instruments (ICESat), returns a single `H5Table`.
"""
function table end

function _h5table_for_track(file::HDF5.File, g::Granule, track::AbstractString, dvars; nrow::Union{Int,Nothing}=nothing)
    vars = [v.name => "$track/$(v.path)" for v in dvars]
    transforms = Dict{Symbol,Any}(v.name => v.f for v in dvars if v.f !== identity)
    attrs = [a.name => "$track/$(a.attribute)" for a in default_attributes(g)]
    source = GranuleSource(g, file, String(track))
    H5Tables.H5Table(source; vars, attrs, transforms, include_dimensions=false, nrow)
end

"""Rebuild `t` carrying a `GranuleSource` for `track` (used after the cheap
template-reuse path, which copies the template's source)."""
function _retrack(t::H5Tables.H5Table, g::Granule, file::HDF5.File, track::AbstractString)
    source = GranuleSource(g, file, String(track))
    H5Tables.H5Table(f=source, vars=t.vars, attrs=t.attrs, nrow=t.nrow)
end

"""Check if an H5Table can be used as a template (trivial flattening, no track-dependent transforms)."""
function _is_flat(t::H5Tables.H5Table)
    all(t.vars) do v
        v.inner == 1 && v.outer == 1
    end
end

"""Check if any default variable has a track-dependent transform (e.g. ExpandDims)."""
_has_track_transform(dvars) = any(v -> v.f isa H5Tables.ExpandDims, dvars)

"""
    _quick_nrow(file, track, dvars) -> Union{Int, Nothing}

Cheaply determine nrow by checking if the first variable is 1D.
Returns its length if 1D, or `nothing` if multi-dimensional (requires full resolution).
"""
function _quick_nrow(file::HDF5.File, track::AbstractString, dvars)
    path = "$track/$(dvars[1].path)"
    ds = HDF5.open_dataset(file, path)
    dspace = HDF5.dataspace(ds)
    nd = HDF5.API.h5s_get_simple_extent_ndims(dspace)
    nrow = if nd == 1
        dims, _ = HDF5.API.h5s_get_simple_extent_dims(dspace)
        Int(dims[1])
    else
        nothing
    end
    close(dspace)
    close(ds)
    return nrow
end

function table(g::Granule; tracks=default_tracks(g), variables=default_variables(g))
    file = HDF5.h5open(g.url, "r")
    tables = H5Tables.H5Table[]
    template = nothing
    first_track = nothing
    can_template = !_has_track_transform(variables)
    for track in tracks
        haskey(file, track) || continue
        if isnothing(template)
            # Try cheap nrow detection (skips expensive resolve_global_dims for 1D data)
            nrow = _quick_nrow(file, track, variables)
            t = _h5table_for_track(file, g, track, variables; nrow)
            # Only use template optimization if no track-dependent transforms and trivial flat
            if can_template && _is_flat(t)
                template = t
                first_track = track
            end
        else
            # Reuse template structure — just remap paths, then re-source for this track
            t = H5Tables.H5Table(template, track, first_track)
            t = _retrack(t, g, file, track)
        end
        push!(tables, t)
    end
    if isempty(tables)
        close(file)
        error("No tracks found in $(g.id) for tracks=$(collect(tracks))")
    end
    H5Tables.PartitionedH5Table(tables)
end

function table(g::ICESat_Granule; variables=default_variables(g))
    file = HDF5.h5open(g.url, "r")
    vars = [v.name => v.path for v in variables]
    transforms = Dict{Symbol,Any}(v.name => v.f for v in variables if v.f !== identity)
    attrs = Pair{Symbol,String}[]
    H5Tables.H5Table(GranuleSource(g, file); vars, attrs, transforms)
end

# ─── explore(::Granule) → interactive selection with track replication ─────────

"""
    explore(g::Granule)

Interactively explore the granule's HDF5 file. Select variables from any track;
the selection is automatically replicated across all tracks.

For multi-track instruments (ICESat-2, GEDI), returns a `PartitionedH5Table`.
For single-track instruments (ICESat), returns a single `H5Table`.
"""
function explore end

"""
Separate selected paths into track-relative (prefix stripped) and shared (root-level) paths.
"""
function _split_track_paths(selected_paths::Vector{String}, tracks)
    track_paths = String[]
    shared_paths = String[]
    for p in selected_paths
        first_comp = first(split(p, "/"))
        if first_comp in tracks
            push!(track_paths, join(split(p, "/")[2:end], "/"))
        else
            push!(shared_paths, p)
        end
    end
    return (track_paths, shared_paths)
end

function explore(g::Granule; tracks=default_tracks(g))
    file = HDF5.h5open(g.url, "r")
    selected_paths, selected_attrs = H5Tables.select(file)
    suffix_paths, shared_paths = _split_track_paths(selected_paths, tracks)
    shared_vars = [Symbol(split(p, "/")[end]) => p for p in shared_paths]
    tables = H5Tables.H5Table[]
    for track in tracks
        haskey(file, track) || continue
        all(haskey(file[track], sp) for sp in suffix_paths) || continue
        vars = vcat([Symbol(split(sp, "/")[end]) => "$track/$sp" for sp in suffix_paths], shared_vars)
        push!(tables, H5Tables.H5Table(GranuleSource(g, file, String(track)); vars, attrs=selected_attrs, include_dimensions=false))
    end
    if isempty(tables)
        close(file)
        error("No tracks found in $(g.id) with selected variables")
    end
    H5Tables.PartitionedH5Table(tables)
end

function explore(g::ICESat_Granule)
    file = HDF5.h5open(g.url, "r")
    selected_paths, selected_attrs = H5Tables.select(file)
    vars = [Symbol(split(p, "/")[end]) => p for p in selected_paths]
    H5Tables.H5Table(GranuleSource(g, file); vars, attrs=selected_attrs, include_dimensions=false)
end
