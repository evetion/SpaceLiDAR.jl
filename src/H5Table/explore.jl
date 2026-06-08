
"""Node data for the HDF5 explorer tree."""
mutable struct H5NodeData
    label::String
    path::String
    is_dataset::Bool
    is_attr::Bool       # attribute display node (selectable with space)
    selected::Bool
    compatible::Bool
    size_str::String
    description::String
    dims::Union{Nothing,Vector{String}}
    dim_sizes::Union{Nothing,Dict{String,Int}}
end
H5NodeData(label, path, is_dataset, selected, compatible, size_str, desc, dims) =
    H5NodeData(label, path, is_dataset, false, selected, compatible, size_str, desc, dims, nothing)

"""Explorer state shared across callbacks."""
mutable struct ExplorerState
    auto_dims::Bool
    auto_refs::Bool
    global_dims::Vector{String}
    dim_sizes::Dict{String,Int}
end

"""Render a StyledString to ANSI escape codes."""
function styled_ansi(s)
    io = IOContext(IOBuffer(), :color => true)
    print(io, s)
    return String(take!(io.io))
end

# Module-level context for the dynamic header (set by explore(), read by header())
const _EXPLORER_CTX = Ref{Any}(nothing)

"""Dynamic header for TreeMenu: shows D/R flags and breadcrumb path to cursor.
Always returns exactly 1 line to keep terminal line-count accounting stable."""
function TerminalMenus.header(menu::TreeMenu{Node{H5NodeData}})
    ctx = _EXPLORER_CTX[]
    ctx === nothing && return " "
    state::ExplorerState, filename::String, root = ctx
    # D/R flag indicators
    flags = String[]
    state.auto_dims && push!(flags, styled_ansi(styled"{yellow:[D]}"))
    state.auto_refs && push!(flags, styled_ansi(styled"{yellow:[R]}"))
    flag_str = isempty(flags) ? "" : " " * join(flags, " ")
    # Find cursor node — clamp to valid range (tree may have shrunk after fold)
    n_opts = max(1, TerminalMenus.numoptions(menu))
    safe_idx = clamp(menu.cursoridx, 1, n_opts)
    saved = (menu.current, menu.currentidx, menu.currentdepth)
    node = try
        FoldingTrees.setcurrent!(menu, safe_idx)
    catch
        menu.current, menu.currentidx, menu.currentdepth = saved
        return styled_ansi(styled"{shadow:space=select  a=attrs  d=dims  r=refs  c=clear  ←→=fold  q=done}") * flag_str
    end
    menu.current, menu.currentidx, menu.currentdepth = saved
    # Breadcrumb: collect ancestor groups (skip the node itself, skip root)
    parts = String[]
    n = node.data.is_attr ? node.parent : node
    n = isdefined(n, :parent) ? n.parent : n
    while n !== root && isdefined(n, :parent)
        !n.data.is_attr && pushfirst!(parts, n.data.label)
        n = n.parent
    end
    crumb = join(parts, " > ")
    # Always return something — keeps nheaderlines constant at 1
    if isempty(crumb) && isempty(flag_str)
        return styled_ansi(styled"{shadow:space=select  a=attrs  d=dims  r=refs  c=clear  ←→=fold  q=done}")
    end
    return styled_ansi(styled"{shadow:$crumb}") * flag_str
end

"""Override printmenu to sync cursoridx (clamped) and fix pageoffset after folds."""
function TerminalMenus.printmenu(out::IO, menu::TreeMenu{Node{H5NodeData}}, cursoridx::Int; kwargs...)
    # Clamp: after fold, AbstractMenu's cursor[] may exceed visible node count
    n_opts = max(1, TerminalMenus.numoptions(menu))
    cursoridx = clamp(cursoridx, 1, n_opts)
    menu.cursoridx = cursoridx
    # Fix pageoffset: after collapse it may be too large, leaving most of the page empty
    if menu.pageoffset >= n_opts
        menu.pageoffset = max(0, n_opts - menu.pagesize)
    end
    if cursoridx <= menu.pageoffset
        menu.pageoffset = cursoridx - 1
    elseif cursoridx > menu.pageoffset + menu.pagesize
        menu.pageoffset = cursoridx - menu.pagesize
    end
    invoke(TerminalMenus.printmenu, Tuple{IO, TerminalMenus.AbstractMenu, Int}, out, menu, cursoridx; kwargs...)
end

# Clamp cursor to valid range before standard navigation (fixes stuck cursor after fold)
function TerminalMenus.move_up!(menu::TreeMenu{Node{H5NodeData}}, cursor::Int, lastoption::Int=TerminalMenus.numoptions(menu))
    cursor = min(cursor, lastoption)
    invoke(TerminalMenus.move_up!, Tuple{TerminalMenus.AbstractMenu, Int, Int}, menu, cursor, lastoption)
end
function TerminalMenus.move_down!(menu::TreeMenu{Node{H5NodeData}}, cursor::Int, lastoption::Int=TerminalMenus.numoptions(menu))
    cursor = min(cursor, lastoption)
    invoke(TerminalMenus.move_down!, Tuple{TerminalMenus.AbstractMenu, Int, Int}, menu, cursor, lastoption)
end

"""Build a FoldingTrees.Node tree from an HDF5 group, recursively."""
function build_tree(file::HDF5.File)
    root_data = H5NodeData(basename(HDF5.filename(file)), "", false, false, true, "", "", nothing)
    root = Node(root_data, true)
    _build_tree!(root, file["/"])
    unfold!(root)
    return root
end

function _build_tree!(parent_node, group)
    for name in keys(group)
        obj = group[name]
        path = lstrip(HDF5.name(obj), '/')
        if obj isa HDF5.Dataset
            sz = size(obj)
            size_str = isempty(sz) ? "(scalar)" : string(sz)
            data = H5NodeData(name, path, true, false, true, size_str, "", nothing)
            Node(data, parent_node)
        else
            data = H5NodeData(name * "/", path, false, false, true, "", "", nothing)
            child = Node(data, parent_node, true)
            _build_tree!(child, obj)
        end
    end
end

"""Resolve dims and load description for all dataset children (called on unfold)."""
function resolve_children!(node, file)
    for child in node.children
        d = child.data
        d.is_dataset || continue
        isnothing(d.dims) || continue
        ds = file[d.path]
        # Cache dims and dim_sizes
        d.dims, d.dim_sizes = try
            resolve_var_dims(file, d.path)
        catch
            String[], Dict{String,Int}()
        end
        # Load description (prefer long_name, fall back to description)
        a = HDF5.attrs(ds)
        d.description = get(a, "long_name", get(a, "description", ""))
    end
end

"""Collect all selected paths from the tree."""
function collect_selected(root)
    paths = String[]
    _collect_selected!(paths, root)
    return paths
end

function _collect_selected!(paths, node)
    node.data.is_dataset && !node.data.is_attr && node.data.selected && push!(paths, node.data.path)
    for child in node.children
        _collect_selected!(paths, child)
    end
end

"""Collect all selected attribute paths from the tree as name => path pairs."""
function collect_selected_attrs(root)
    attrs = Pair{Symbol,String}[]
    _collect_selected_attrs!(attrs, root)
    return attrs
end

function _collect_selected_attrs!(attrs, node)
    if node.data.is_attr && node.data.selected && !isempty(node.data.path)
        # path is "parent_path/attr_name"; use attr_name as symbol key
        attr_name = split(node.data.path, "/")[end]
        push!(attrs, Symbol(attr_name) => node.data.path)
    end
    for child in node.children
        _collect_selected_attrs!(attrs, child)
    end
end

"""Recompute global dims from cached node data for selected vars."""
function recompute_global!(state, root, file)
    state.global_dims = String[]
    empty!(state.dim_sizes)
    _recompute_from_tree!(state, root, file)
end

function _recompute_from_tree!(state, node, file)
    d = node.data
    if d.is_dataset && !d.is_attr && d.selected
        # Use cached dims if available, otherwise resolve (and cache)
        if isnothing(d.dims)
            d.dims, d.dim_sizes = try
                resolve_var_dims(file, d.path)
            catch
                String[], Dict{String,Int}()
            end
        end
        vdims = d.dims
        vsizes = d.dim_sizes
        !isnothing(vsizes) && merge!(state.dim_sizes, vsizes)
        if length(vdims) > length(state.global_dims)
            state.global_dims = vdims
        end
    end
    for child in node.children
        _recompute_from_tree!(state, child, file)
    end
end

"""
Check if a candidate's cached dims are compatible with the current global dims.

Handles subset (candidate ⊆ global), equal, and superset (global ⊆ candidate) cases.
Dimensions with the same size are treated as equivalent (for files without shared dim scales).
Returns false for partial overlap or reversed ordering.
"""
function check_compatible(global_dims, candidate_dims, global_sizes=Dict{String,Int}(), candidate_sizes=Dict{String,Int}())
    isempty(global_dims) && return true
    isempty(candidate_dims) && return false

    # Build size-based equivalence: map each candidate dim to a matching global dim by size
    matched_candidate = String[]
    for cd in candidate_dims
        cs = get(candidate_sizes, cd, -1)
        if cd in global_dims
            push!(matched_candidate, cd)
        else
            # Find a global dim with the same size
            match = findfirst(gd -> get(global_sizes, gd, -2) == cs, global_dims)
            if match !== nothing
                push!(matched_candidate, global_dims[match])
            else
                push!(matched_candidate, cd)
            end
        end
    end

    gset = Set(global_dims)
    cset = Set(matched_candidate)

    if cset ⊆ gset
        global_order = Dict(d => i for (i, d) in enumerate(global_dims))
        positions = [global_order[d] for d in matched_candidate]
        issorted(positions) || return false
        length(positions) <= 1 && return true
        min_p, max_p = extrema(positions)
        return all(global_dims[i] ∈ cset for i in min_p:max_p)
    end

    if gset ⊆ cset
        cand_order = Dict(d => i for (i, d) in enumerate(matched_candidate))
        positions = [cand_order[d] for d in global_dims]
        issorted(positions) || return false
        length(positions) <= 1 && return true
        min_p, max_p = extrema(positions)
        return all(matched_candidate[i] ∈ gset for i in min_p:max_p)
    end

    return false
end

"""Update compatibility for all resolved nodes (uses cached dims only — no I/O)."""
function update_compatibility!(root, state)
    _update_compat!(root, state.global_dims, state.dim_sizes)
end

function _update_compat!(node, global_dims, global_sizes=Dict{String,Int}())
    d = node.data
    if d.is_dataset && !d.selected && !isnothing(d.dims)
        candidate_sizes = something(d.dim_sizes, Dict{String,Int}())
        d.compatible = check_compatible(global_dims, d.dims, global_sizes, candidate_sizes)
    end
    for child in node.children
        _update_compat!(child, global_dims, global_sizes)
    end
end

"""Clear all selections and reset state."""
function reset_selection!(root, state)
    _clear_selected!(root)
    state.global_dims = String[]
    empty!(state.dim_sizes)
    _update_compat!(root, state.global_dims)  # everything becomes compatible
end

function _clear_selected!(node)
    # Clear datasets and group "has selected child" markers
    if node.data.is_dataset || !node.data.is_attr
        node.data.selected = false
    end
    for child in node.children
        _clear_selected!(child)
    end
end

"""Auto-select dimension variables for a path."""
function auto_select_dims!(root, file, path)
    ds = file[path]
    dim_paths = get_dimension_paths(ds)
    isnothing(dim_paths) && return
    for dp in dim_paths
        _set_selected!(root, lstrip(dp, '/'), true)
    end
end

"""Auto-select referenced variables for a path."""
function auto_select_refs!(root, file, path)
    ds = file[path]
    ref_paths = get_reference_paths(ds)
    isnothing(ref_paths) && return
    for rp in ref_paths
        _set_selected!(root, lstrip(rp, '/'), true)
    end
end

function _set_selected!(node, path, val)
    if node.data.path == path && node.data.is_dataset
        node.data.selected = val
        return true
    end
    for child in node.children
        _set_selected!(child, path, val) && return true
    end
    return false
end

"""Check if a node has any selected descendants."""
function _has_selected_child(node)
    for child in node.children
        child.data.selected && return true
        _has_selected_child(child) && return true
    end
    return false
end

"""Mark group nodes that contain selected descendants (for display coloring)."""
function _mark_groups!(node)
    if !node.data.is_dataset && !node.data.is_attr
        node.data.selected = _has_selected_child(node)
    end
    for child in node.children
        _mark_groups!(child)
    end
end

# HDF5 internal attributes that are not useful for display
const _INTERNAL_ATTRS = Set(["DIMENSION_LIST", "REFERENCE_LIST", "CLASS", "NAME"])

"""Expand attributes as children of a dataset or group node (called on 'a' key)."""
function expand_attrs!(node, file)
    !isempty(node.children) && node.data.is_dataset && return
    d = node.data
    d.is_attr && return
    # For groups, only add attrs if none exist yet (attrs are prepended before group children)
    if !d.is_dataset && any(c.data.is_attr for c in node.children)
        return
    end
    obj_path_key = isempty(d.path) ? "/" : d.path
    obj = file[obj_path_key]
    attr_keys = keys(HDF5.attrs(obj))
    for (idx, k) in enumerate(attr_keys)
        v = try
            repr(HDF5.read_attribute(obj, k))
        catch
            "?"
        end
        length(v) > 60 && (v = v[1:57] * "...")
        is_internal = k in _INTERNAL_ATTRS || startswith(k, "_")
        label = "$k = $v"
        # Store path as "parent_path/attr_name" for H5Table attrs parameter
        attr_path = isempty(d.path) ? k : d.path * "/" * k
        adata = H5NodeData(label, attr_path, false, true, false, !is_internal, "", "", nothing, nothing)
        if d.is_dataset
            Node(adata, node)
        else
            # Prepend attrs before existing group children by inserting at position
            insert!(node.children, idx, Node(adata))
            node.children[idx].parent = node
        end
    end
end

"""Custom display for H5NodeData in the tree menu using StyledStrings."""
function FoldingTrees.writeoption(buf::IO, data::H5NodeData, charsused::Int; width::Int=(displaysize(stdout)::Tuple{Int,Int})[2])
    if data.is_attr
        # Show selection state for attrs; internal attrs (compatible=false): shadow
        str = if data.selected
            styled_ansi(styled"{green:[✓] $(data.label)}")
        elseif data.compatible
            styled_ansi(styled"{italic:[ ] $(data.label)}")
        else
            styled_ansi(styled"{shadow:[-] _$(data.label)}")
        end
        FoldingTrees.writeoption(buf, str, charsused; width)
    elseif data.is_dataset
        desc = isempty(data.description) ? "" : "  " * data.description
        str = if data.selected
            styled_ansi(styled"{green:[✓] $(data.label)}  {shadow:$(data.size_str)$desc}")
        elseif !data.compatible
            styled_ansi(styled"{shadow:[-] $(data.label)  $(data.size_str)$desc}")
        else
            styled_ansi(styled"[ ] $(data.label)  {shadow:$(data.size_str)$desc}")
        end
        FoldingTrees.writeoption(buf, str, charsused; width)
    else
        # Group node: bold, green tint if it contains selected children
        str = if data.selected
            styled_ansi(styled"{green,bold:$(data.label)}")
        else
            styled_ansi(styled"{bold:$(data.label)}")
        end
        FoldingTrees.writeoption(buf, str, charsused; width)
    end
end

"""
    explore(file::HDF5.File; pagesize=20) -> H5Table
    explore(filename::AbstractString; pagesize=20) -> H5Table

Interactively explore an HDF5 file with a tree menu. Select variables to build an H5Table.

# Controls
- **↑/↓**: navigate
- **←/→**: fold/unfold groups
- **Space**: toggle selection on datasets and attributes
- **a**: expand attributes on the current node (dataset or group)
- **d**: toggle auto-include dimensions (header shows [D])
- **r**: toggle auto-include references (header shows [R])
- **c**: clear all selections
- **q/Enter**: confirm selection and return H5Table
- **Ctrl-C**: cancel

Incompatible variables (can't flatten with current selection) are shown as `[-]` in grey.
Dims and descriptions are resolved lazily as you unfold groups.
"""
function explore(file::HDF5.File; pagesize::Int=min(displaysize(stdout)[1] - 3, 40))
    selected_paths, selected_attrs = select(file; pagesize)
    vars = [Symbol(split(p, "/")[end]) => p for p in selected_paths]
    return H5Table(file; vars, attrs=selected_attrs, include_dimensions=false)
end

function explore(filename::AbstractString; kwargs...)
    file = HDF5.h5open(filename, "r")
    return explore(file; kwargs...)
end

"""
    select(file::HDF5.File; pagesize) → (Vector{String}, Vector{Pair{Symbol,String}})

Run the interactive explorer and return the selected dataset paths and attribute paths.
This is the building block for `explore(file)` and `explore(::Granule)`.
"""
function select(file::HDF5.File; pagesize::Int=min(displaysize(stdout)[1] - 3, 40))
    root = build_tree(file)
    state = ExplorerState(false, false, String[], Dict{String,Int}())

    # Resolve dims/descriptions for initially visible datasets
    resolve_children!(root, file)

    # Set module-level context for the dynamic header
    _EXPLORER_CTX[] = (state, HDF5.filename(file), root)

    # Shared cursor Ref — passed to request() so keypress can sync cursor position
    cursor_ref = Ref(1)

    # Saved attribute selections (for groups: preserve across close/open cycles)
    saved_attr_selections = Set{String}()

    function on_unfold!(node)
        resolve_children!(node, file)
        _update_compat!(node, state.global_dims, state.dim_sizes)
    end

    function keypress(menu, i)
        node = FoldingTrees.setcurrent!(menu, menu.cursoridx)
        d = node.data

        # Prevent root from being folded (space toggles fold before we get here)
        if root.foldchildren
            unfold!(root)
        end

        if i == UInt32(' ') && d.is_dataset && !d.is_attr
            if d.compatible || d.selected
                d.selected = !d.selected
                if d.selected
                    state.auto_dims && auto_select_dims!(root, file, d.path)
                    state.auto_refs && auto_select_refs!(root, file, d.path)
                end
                recompute_global!(state, root, file)
                update_compatibility!(root, state)
                _mark_groups!(root)
            end
            return false
        elseif i == UInt32(' ') && d.is_attr
            # Toggle attribute selection (only non-internal attrs are selectable)
            if d.compatible
                d.selected = !d.selected
                if d.selected
                    push!(saved_attr_selections, d.path)
                else
                    delete!(saved_attr_selections, d.path)
                end
            end
            return false
        elseif i == UInt32('a')
            # Toggle attributes on the current node (dataset or group)
            if !d.is_attr
                has_attrs = any(c.data.is_attr for c in node.children)
                if d.is_dataset
                    if !has_attrs
                        expand_attrs!(node, file)
                        unfold!(node)
                    elseif !node.foldchildren
                        fold!(node)
                    else
                        unfold!(node)
                    end
                else
                    # Group: add/remove attr children (preserving selection)
                    if has_attrs
                        # Save selected attrs before removing
                        for c in node.children
                            c.data.is_attr && c.data.selected && push!(saved_attr_selections, c.data.path)
                        end
                        filter!(c -> !c.data.is_attr, node.children)
                    else
                        expand_attrs!(node, file)
                        # Restore selection from saved state
                        for c in node.children
                            c.data.is_attr && c.data.path in saved_attr_selections && (c.data.selected = true)
                        end
                        unfold!(node)
                    end
                end
            end
            if menu.dynamic
                menu.pagesize = min(menu.maxsize, count_open_leaves(root))
            end
            return false
        elseif i == UInt32('d')
            state.auto_dims = !state.auto_dims
            return false
        elseif i == UInt32('r')
            state.auto_refs = !state.auto_refs
            return false
        elseif i == UInt32('c')
            reset_selection!(root, state)
            empty!(saved_attr_selections)
            _mark_groups!(root)
            return false
        elseif i == UInt32('q')
            return true
        elseif i == UInt32(TerminalMenus.ARROW_LEFT)
            if !node.foldchildren && !isempty(node.children)
                # On a node with visible children: collapse it
                if !d.is_dataset
                    # Save and remove attr children from group (keep dataset/group children)
                    for c in node.children
                        c.data.is_attr && c.data.selected && push!(saved_attr_selections, c.data.path)
                    end
                    filter!(c -> !c.data.is_attr, node.children)
                end
                fold!(node)
            elseif !isroot(node)
                # On a leaf/folded node: collapse the parent and move cursor to it
                parent = node.parent
                if !isroot(parent) || parent === root
                    # Walk cursor back to parent BEFORE folding (prev needs intact tree)
                    steps = 0
                    n = node
                    depth = menu.currentdepth
                    while n !== parent
                        n, depth = FoldingTrees.prev(n, depth)
                        steps += 1
                        steps > 500 && break  # safety guard
                    end
                    # Now fold and clean up
                    if !parent.data.is_dataset
                        for c in parent.children
                            c.data.is_attr && c.data.selected && push!(saved_attr_selections, c.data.path)
                        end
                        filter!(c -> !c.data.is_attr, parent.children)
                    end
                    fold!(parent)
                    menu.cursoridx -= steps
                    menu.current = parent
                    menu.currentidx = menu.cursoridx  # sync internal index with cursor
                    menu.currentdepth = depth
                    # Sync the request() cursor so printmenu receives the correct position
                    cursor_ref[] = menu.cursoridx
                end
            end
            if menu.dynamic
                menu.pagesize = min(menu.maxsize, count_open_leaves(root))
            end
            return false
        elseif i == UInt32(TerminalMenus.ARROW_RIGHT)
            if !d.is_dataset && !d.is_attr && node.foldchildren
                # On a folded group: unfold it
                unfold!(node)
                on_unfold!(node)
            end
            if menu.dynamic
                menu.pagesize = min(menu.maxsize, count_open_leaves(root))
            end
            return false
        end
        return false
    end

    menu = TreeMenu(root; pagesize=pagesize - 1, dynamic=true, maxsize=pagesize - 1, keypress)
    TerminalMenus.request(menu; cursor=cursor_ref)
    _EXPLORER_CTX[] = nothing  # cleanup

    selected_paths = collect_selected(root)
    selected_attrs = collect_selected_attrs(root)
    # Include attrs that were selected then closed (removed from tree but saved)
    existing_paths = Set(last.(selected_attrs))
    for path in saved_attr_selections
        path in existing_paths && continue
        attr_name = split(path, "/")[end]
        push!(selected_attrs, Symbol(attr_name) => path)
    end
    isempty(selected_paths) && isempty(selected_attrs) && error("No variables selected")
    return selected_paths, selected_attrs
end
