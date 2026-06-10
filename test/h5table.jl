using Test
using Tables
using HDF5
using DataFrames
using FoldingTrees: unfold!, fold!, Node, count_open_leaves, setcurrent!, isroot
using FoldingTrees: prev as ft_prev
using REPL.TerminalMenus
using REPL.TerminalMenus: ARROW_LEFT, ARROW_RIGHT
using FoldingTrees: TreeMenu
using DataAPI: metadata, colmetadata
using SpaceLiDAR.H5Tables: H5Table, explore, get_dimensions, get_references,
    resolve_global_dims, is_dim_compatible, _h5read_attr,
    build_tree, resolve_children!, recompute_global!, update_compatibility!,
    ExplorerState, _set_selected!, _mark_groups!, expand_attrs!,
    auto_select_dims!, auto_select_refs!, reset_selection!, collect_selected,
    collect_selected_attrs, check_compatible,
    SliceRow, apply_transform_dims, resolve_var_dims

@testset "H5Table" begin

    @testset "basic construction and metadata" begin
        h5open(ATL08_fn, "r") do h5
            table = H5Table(h5,
                vars=[
                    :longitude => "gt1l/land_segments/longitude",
                    :latitude => "gt1l/land_segments/latitude",
                    :brightness_flag => "gt1l/land_segments/brightness_flag",
                ],
                attrs=[:units => "gt1l/land_segments/latitude/units"],
                include_dimensions=true,
                include_references=true,
            )

            @test Tables.istable(table)
            @test :longitude in Tables.columnnames(table)
            @test :latitude in Tables.columnnames(table)
            @test :brightness_flag in Tables.columnnames(table)

            # metadata round-trips through DataFrame
            md = metadata(table)
            @test md isa AbstractDict
            cmd = colmetadata(table, :latitude)
            @test cmd isa AbstractDict
            cmd_idx = colmetadata(table, 1)
            @test cmd_idx isa AbstractDict

            df = DataFrame(table)
            @test metadata(df) == md
            @test colmetadata(df, :latitude) == cmd
        end
    end

    @testset "multi-dimensional flattening" begin
        # latitude_20m (5×998) with 1D latitude (998)
        # Expected: all columns flattened to 998*5 = 4990 rows
        h5open(ATL08_fn, "r") do h5
            table = H5Table(h5,
                vars=[
                    :latitude_20m => "gt1l/land_segments/latitude_20m",
                    :latitude => "gt1l/land_segments/latitude",
                ],
                include_dimensions=true,
            )

            @test nrow(table) == 4990

            lat20 = Tables.getcolumn(table, :latitude_20m)
            lat = Tables.getcolumn(table, :latitude)
            @test length(lat20) == 4990
            @test length(lat) == 4990

            # latitude repeated inner=5
            @test lat[1] == lat[2] == lat[3] == lat[4] == lat[5]
            # latitude_20m is not uniformly repeated
            @test lat20[1] != lat20[2] || lat20[1] != lat20[6]

            # delta_time auto-included as a dimension
            @test :delta_time in Tables.columnnames(table)
            dt = Tables.getcolumn(table, :delta_time)
            @test length(dt) == 4990
            @test dt[1] == dt[2] == dt[3] == dt[4] == dt[5]
        end
    end

    @testset "include_references" begin
        h5open(ATL08_fn, "r") do h5
            table = H5Table(h5,
                vars=[:delta_time => "gt1l/land_segments/delta_time"],
                include_dimensions=false,
                include_references=true,
            )
            cols = Tables.columnnames(table)

            @test :latitude in cols
            @test :longitude in cols
            @test :h_te_mean in cols
            # 2D vars in references trigger flattening to 4990
            @test nrow(table) == 4990
            @test length(Tables.getcolumn(table, :latitude)) == 4990
            @test length(Tables.getcolumn(table, :latitude_20m)) == 4990
        end
    end

    @testset "is_dim_compatible" begin
        h5open(ATL08_fn, "r") do h5
            gd, ds, _ = resolve_global_dims(h5, ["gt1l/land_segments/latitude_20m"])
            # latitude shares the delta_time dim → compatible
            @test is_dim_compatible(h5, gd, ds, "gt1l/land_segments/latitude")
            # delta_time is a dim scale in global_dims → compatible
            @test is_dim_compatible(h5, gd, ds, "gt1l/land_segments/delta_time")
        end
    end

    @testset "_h5read_attr" begin
        h5open(ATL08_fn, "r") do h5
            # String attribute on a dataset (fallback path)
            val = _h5read_attr(h5, "gt1l/land_segments/latitude", "units")
            @test val == "degrees"

            # String attribute on a group (fallback path)
            val2 = _h5read_attr(h5, "gt1l", "atlas_beam_type")
            @test val2 isa AbstractString
            @test !isempty(val2)

            # Matches high-level API
            ref = HDF5.read_attribute(h5["gt1l"], "atlas_beam_type")
            @test val2 == ref

            # Typed primitive path (Float32 scalar)
            val3 = _h5read_attr(h5, "gt1l/land_segments/latitude", "valid_min", Float32)
            @test val3 isa Float32
            @test val3 == Float32(-90)

            # Typed matches untyped
            val4 = _h5read_attr(h5, "gt1l/land_segments/latitude", "valid_min")
            @test val3 == val4
        end
    end

    @testset "GEDI flattening" begin
        h5open(GEDI02_fn, "r") do h5
            @testset "rh (101×41946)" begin
                table = H5Table(h5,
                    vars=[:lat => "BEAM0000/lat_lowestmode", :rh => "BEAM0000/rh"],
                    include_dimensions=false,
                )
                @test nrow(table) == 101 * 41946
                lat = Tables.getcolumn(table, :lat)
                @test length(lat) == 101 * 41946
                @test lat[1] == lat[101]
            end

            @testset "elevs_allmodes (20×41946)" begin
                table = H5Table(h5,
                    vars=[:lat => "BEAM0000/lat_lowestmode", :elev => "BEAM0000/geolocation/elevs_allmodes_a1"],
                    include_dimensions=false,
                )
                @test nrow(table) == 20 * 41946
                lat = Tables.getcolumn(table, :lat)
                @test length(lat) == 20 * 41946
                @test lat[1] == lat[20]
            end

            @testset "1D only (no flattening)" begin
                table = H5Table(h5,
                    vars=[:lat => "BEAM0000/lat_lowestmode", :dt => "BEAM0000/delta_time"],
                    include_dimensions=false,
                )
                @test nrow(table) == 41946
            end
        end
    end

    @testset "SliceRow dim resolution" begin
        # signal_conf_ph is (5, N_photons): Julia axis 1 = surface_type (size 5),
        # Julia axis 2 = photon axis. SliceRow(row) → data[row, :] keeps axis 2.
        # The remaining photon axis must still participate in global dim resolution.
        h5open(ATL03_fn, "r") do h5
            path = "gt1l/heights/signal_conf_ph"
            vdims, vsizes = resolve_var_dims(h5, path)
            @test length(vdims) == 2
            photon_dim = vdims[2]
            n_photons = vsizes[photon_dim]

            # apply_transform_dims drops Julia axis 1 (the sliced axis)
            @test apply_transform_dims(SliceRow(1), vdims) == [photon_dim]
            # identity / default: dims unchanged
            @test apply_transform_dims(identity, vdims) == vdims

            # SliceRow var alone: nrow should be the photon dim length, not 1.
            t1 = H5Table(h5,
                vars=[:conf => path],
                transforms=Dict{Symbol,Any}(:conf => SliceRow(1)),
            )
            @test nrow(t1) == n_photons
            @test length(Tables.getcolumn(t1, :conf)) == n_photons

            # SliceRow + sibling 1D var on the same photon axis: aligned, no inflation.
            t2 = H5Table(h5,
                vars=[
                    :dt => "gt1l/heights/delta_time",
                    :conf => path,
                ],
                transforms=Dict{Symbol,Any}(:conf => SliceRow(1)),
            )
            @test nrow(t2) == n_photons
            @test length(Tables.getcolumn(t2, :dt)) == n_photons
            @test length(Tables.getcolumn(t2, :conf)) == n_photons
        end
    end

    @testset "explore internals" begin
        h5open(ATL08_fn, "r") do h5
            @testset "build_tree" begin
                root = build_tree(h5)
                @test root.data.label == basename(ATL08_fn)
                @test root.data.path == ""
                @test !root.data.is_dataset
                @test length(root.children) > 0
                # Should contain both datasets and groups
                has_group = any(!c.data.is_dataset for c in root.children)
                has_dataset = any(c.data.is_dataset for c in root.children)
                @test has_group
                @test has_dataset
                # Group labels end with "/"
                group_node = first(c for c in root.children if !c.data.is_dataset)
                @test endswith(group_node.data.label, "/")
            end

            @testset "resolve_children!" begin
                root = build_tree(h5)
                # Unfold to get access to gt1l/land_segments
                function find_node(node, path)
                    node.data.path == path && return node
                    for child in node.children
                        r = find_node(child, path)
                        !isnothing(r) && return r
                    end
                    nothing
                end
                # Unfold all
                function unfold_all!(node)
                    unfold!(node)
                    for child in node.children
                        child.data.is_dataset || unfold_all!(child)
                    end
                end
                unfold_all!(root)

                land = find_node(root, "gt1l/land_segments")
                @test !isnothing(land)
                resolve_children!(land, h5)
                # After resolve, datasets should have dims cached
                lat_node = find_node(root, "gt1l/land_segments/latitude")
                @test !isnothing(lat_node)
                @test !isnothing(lat_node.data.dims)
                @test !isnothing(lat_node.data.dim_sizes)
                @test length(lat_node.data.dims) > 0
            end

            @testset "selection and recompute" begin
                root = build_tree(h5)
                function unfold_all!(node)
                    unfold!(node)
                    for child in node.children
                        child.data.is_dataset || unfold_all!(child)
                    end
                end
                unfold_all!(root)

                # Resolve all children first
                function resolve_all!(node, file)
                    resolve_children!(node, file)
                    for child in node.children
                        child.data.is_dataset || resolve_all!(child, file)
                    end
                end
                resolve_all!(root, h5)

                state = ExplorerState(false, false, String[], Dict{String,Int}())

                # Select latitude
                @test _set_selected!(root, "gt1l/land_segments/latitude", true)
                recompute_global!(state, root, h5)
                @test !isempty(state.global_dims)
                @test !isempty(state.dim_sizes)

                # Update compatibility
                update_compatibility!(root, state)

                # Mark groups
                _mark_groups!(root)

                # Reset
                reset_selection!(root, state)
                @test isempty(state.global_dims)
                @test isempty(collect_selected(root))
            end

            @testset "auto_select_dims!" begin
                root = build_tree(h5)
                function unfold_all!(node)
                    unfold!(node)
                    for child in node.children
                        child.data.is_dataset || unfold_all!(child)
                    end
                end
                unfold_all!(root)

                auto_select_dims!(root, h5, "gt1l/land_segments/latitude")
                selected = collect_selected(root)
                # latitude has delta_time as dimension
                @test "gt1l/land_segments/delta_time" in selected
            end

            @testset "auto_select_refs!" begin
                root = build_tree(h5)
                function unfold_all!(node)
                    unfold!(node)
                    for child in node.children
                        child.data.is_dataset || unfold_all!(child)
                    end
                end
                unfold_all!(root)

                auto_select_refs!(root, h5, "gt1l/land_segments/delta_time")
                selected = collect_selected(root)
                # delta_time references latitude, longitude, etc.
                @test "gt1l/land_segments/latitude" in selected
                @test "gt1l/land_segments/longitude" in selected
            end

            @testset "expand_attrs!" begin
                root = build_tree(h5)
                function unfold_all!(node)
                    unfold!(node)
                    for child in node.children
                        child.data.is_dataset || unfold_all!(child)
                    end
                end
                unfold_all!(root)

                function find_node(node, path)
                    node.data.path == path && return node
                    for child in node.children
                        r = find_node(child, path)
                        !isnothing(r) && return r
                    end
                    nothing
                end
                lat_node = find_node(root, "gt1l/land_segments/latitude")
                @test isempty(lat_node.children)
                expand_attrs!(lat_node, h5)
                @test !isempty(lat_node.children)
                # All attr children should be marked is_attr
                @test all(c.data.is_attr for c in lat_node.children)
            end

            @testset "attribute selection" begin
                root = build_tree(h5)
                function unfold_all!(node)
                    unfold!(node)
                    for child in node.children
                        child.data.is_dataset || unfold_all!(child)
                    end
                end
                unfold_all!(root)

                function find_node(node, path)
                    node.data.path == path && return node
                    for child in node.children
                        r = find_node(child, path)
                        !isnothing(r) && return r
                    end
                    nothing
                end

                # Expand attrs on a dataset
                lat_node = find_node(root, "gt1l/land_segments/latitude")
                expand_attrs!(lat_node, h5)
                @test !isempty(lat_node.children)

                # Initially no attrs selected
                @test isempty(collect_selected_attrs(root))

                # Select a compatible (non-internal) attribute
                units_node = findfirst(c -> c.data.compatible && contains(c.data.label, "units"), lat_node.children)
                @test !isnothing(units_node)
                attr_node = lat_node.children[units_node]
                @test attr_node.data.is_attr
                @test !attr_node.data.selected

                # Toggle selection
                attr_node.data.selected = true
                selected_attrs = collect_selected_attrs(root)
                @test length(selected_attrs) == 1
                @test first(selected_attrs).first == :units
                @test first(selected_attrs).second == "gt1l/land_segments/latitude/units"

                # Reset clears attribute selections too
                state = ExplorerState(false, false, String[], Dict{String,Int}())
                reset_selection!(root, state)
                @test isempty(collect_selected_attrs(root))

                # Deselect
                attr_node.data.selected = false
                @test isempty(collect_selected_attrs(root))

                # Internal attrs (compatible=false) should not be selectable
                internal_node = findfirst(c -> !c.data.compatible, lat_node.children)
                if !isnothing(internal_node)
                    inode = lat_node.children[internal_node]
                    @test !inode.data.compatible
                end
            end

            @testset "group attribute selection" begin
                root = build_tree(h5)
                function unfold_all!(node)
                    unfold!(node)
                    for child in node.children
                        child.data.is_dataset || unfold_all!(child)
                    end
                end
                unfold_all!(root)

                function find_node(node, path)
                    node.data.path == path && return node
                    for child in node.children
                        r = find_node(child, path)
                        !isnothing(r) && return r
                    end
                    nothing
                end

                # Expand attrs on a group node
                gt1l_node = find_node(root, "gt1l")
                @test !isnothing(gt1l_node)
                expand_attrs!(gt1l_node, h5)
                # Should have attr children prepended
                attr_children = filter(c -> c.data.is_attr, gt1l_node.children)
                @test !isempty(attr_children)

                # Select a group attribute
                compatible_attr = findfirst(c -> c.data.is_attr && c.data.compatible, gt1l_node.children)
                @test !isnothing(compatible_attr)
                ga_node = gt1l_node.children[compatible_attr]
                ga_node.data.selected = true

                selected_attrs = collect_selected_attrs(root)
                @test length(selected_attrs) == 1
                @test startswith(string(first(selected_attrs).second), "gt1l/")

                # Calling expand_attrs! again should not duplicate
                n_before = count(c -> c.data.is_attr, gt1l_node.children)
                expand_attrs!(gt1l_node, h5)
                n_after = count(c -> c.data.is_attr, gt1l_node.children)
                @test n_before == n_after
            end

            @testset "attr selection preserved across close/open" begin
                root = build_tree(h5)
                function unfold_all!(node)
                    unfold!(node)
                    for child in node.children
                        child.data.is_dataset || unfold_all!(child)
                    end
                end
                unfold_all!(root)

                function find_node(node, path)
                    node.data.path == path && return node
                    for child in node.children
                        r = find_node(child, path)
                        !isnothing(r) && return r
                    end
                    nothing
                end

                # Dataset: attrs persist through fold/unfold (children kept)
                lat_node = find_node(root, "gt1l/land_segments/latitude")
                expand_attrs!(lat_node, h5)
                units_idx = findfirst(c -> contains(c.data.label, "units"), lat_node.children)
                lat_node.children[units_idx].data.selected = true
                # Fold (simulates left arrow on dataset)
                fold!(lat_node)
                # Unfold (simulates 'a' to reopen)
                unfold!(lat_node)
                # Selection is preserved
                @test lat_node.children[units_idx].data.selected

                # Group: attrs removed/re-added with saved state
                saved = Set{String}()
                gt1l_node = find_node(root, "gt1l")
                expand_attrs!(gt1l_node, h5)
                compat_idx = findfirst(c -> c.data.is_attr && c.data.compatible, gt1l_node.children)
                ga_node = gt1l_node.children[compat_idx]
                ga_node.data.selected = true
                selected_path = ga_node.data.path
                # Save selection before removing (simulates 'a' close)
                for c in gt1l_node.children
                    c.data.is_attr && c.data.selected && push!(saved, c.data.path)
                end
                filter!(c -> !c.data.is_attr, gt1l_node.children)
                @test !any(c.data.is_attr for c in gt1l_node.children)
                # Re-expand (simulates 'a' open)
                expand_attrs!(gt1l_node, h5)
                for c in gt1l_node.children
                    c.data.is_attr && c.data.path in saved && (c.data.selected = true)
                end
                # Selection is restored
                restored = findfirst(c -> c.data.path == selected_path, gt1l_node.children)
                @test !isnothing(restored)
                @test gt1l_node.children[restored].data.selected
            end

            @testset "check_compatible" begin
                @test check_compatible(String[], ["a"])
                @test check_compatible(["a", "b"], ["a"])
                @test check_compatible(["a", "b"], ["a", "b"])
                @test check_compatible(["a"], ["a", "b"])
                @test !check_compatible(["a", "b"], ["b", "a"])
                @test !check_compatible(["a", "b", "c"], ["a", "c"])
            end

            @testset "cursor position after fold-parent (LEFT key)" begin
                root = build_tree(h5)
                function unfold_all!(node)
                    unfold!(node)
                    for child in node.children
                        child.data.is_dataset || unfold_all!(child)
                    end
                end
                unfold_all!(root)
                resolve_children!(root, h5)

                state = ExplorerState(false, false, String[], Dict{String,Int}())
                cursor_ref = Ref(1)

                # Mimics the keypress handler from select() - fold parent case
                function simulate_left!(menu, cursor_ref, root)
                    node = setcurrent!(menu, menu.cursoridx)
                    d = node.data
                    if root.foldchildren
                        unfold!(root)
                    end
                    if !node.foldchildren && !isempty(node.children)
                        if d.is_dataset
                            empty!(node.children)
                        end
                        fold!(node)
                    elseif !isroot(node)
                        parent = node.parent
                        if !isroot(parent) || parent === root
                            steps = 0
                            n = node
                            depth = menu.currentdepth
                            while n !== parent
                                n, depth = ft_prev(n, depth)
                                steps += 1
                                steps > 500 && break
                            end
                            if parent.data.is_dataset
                                empty!(parent.children)
                            end
                            fold!(parent)
                            menu.cursoridx -= steps
                            menu.current = parent
                            menu.currentidx = menu.cursoridx
                            menu.currentdepth = depth
                            cursor_ref[] = menu.cursoridx
                        end
                    end
                    if menu.dynamic
                        menu.pagesize = min(menu.maxsize, count_open_leaves(root))
                    end
                end

                # Simulate the printmenu step (what request() does after keypress)
                function simulate_printmenu!(menu, cursor_ref)
                    n_opts = max(1, TerminalMenus.numoptions(menu))
                    clamped = clamp(cursor_ref[], 1, n_opts)
                    menu.cursoridx = clamped
                    return clamped
                end

                menu = TreeMenu(root; pagesize=19, dynamic=true, maxsize=19, keypress=(m,i)->false)

                # Test: fold parent from a deep leaf
                cursor_ref[] = 30
                menu.cursoridx = 30
                setcurrent!(menu, 30)
                target_parent = menu.current.parent

                simulate_left!(menu, cursor_ref, root)
                displayed = simulate_printmenu!(menu, cursor_ref)

                @test menu.current === target_parent
                @test displayed == cursor_ref[]
                @test menu.cursoridx == cursor_ref[]

                # Test: consecutive LEFT presses (fold parent, then grandparent)
                unfold_all!(root)
                cursor_ref[] = 200
                menu.cursoridx = 200
                setcurrent!(menu, 200)
                parent1 = menu.current.parent
                grandparent = parent1.parent

                simulate_left!(menu, cursor_ref, root)
                simulate_printmenu!(menu, cursor_ref)
                @test menu.current === parent1

                simulate_left!(menu, cursor_ref, root)
                simulate_printmenu!(menu, cursor_ref)
                @test menu.current === grandparent
                @test cursor_ref[] == menu.cursoridx
            end
        end
    end
end
