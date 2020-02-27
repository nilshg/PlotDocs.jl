
module PlotDocs


using Plots, DataFrames, Latexify, MacroTools, OrderedCollections, Dates
import Plots: _examples

export
    generate_markdown,
    generate_supported_markdown,
    generate_attr_markdown,
    generate_graph_attr_markdown,
    GENDIR

const GENDIR = normpath(@__DIR__, "..", "docs", "src", "generated")
mkpath(GENDIR)

# ----------------------------------------------------------------------

# TODO: Make this work now on julia 1.0:
function pretty_print_expr(io::IO, expr::Expr)
    for arg in rmlines(expr).args
        println(io, arg)
    end
end

function markdown_code_to_string(arr, prefix = "")
    string("`", prefix, join(sort(map(string, arr)), "`, `$prefix"), "`")
end
markdown_symbols_to_string(arr) = isempty(arr) ? "" : markdown_code_to_string(arr, ":")

# ----------------------------------------------------------------------

function generate_markdown(pkgname::Symbol; skip = get(Plots._backend_skips, pkgname, Int[]))
    pkg = Plots._backend_instance(pkgname)

    # open the markdown file
    md = open(joinpath(GENDIR, "$(pkgname).md"), "w")

    write(md, """
    ### [Initialize](@id $pkgname-examples)

    ```@example $pkgname
    using Plots
    Plots.reset_defaults() # hide
    $(pkgname)()
    ```
    """)

    for (i,example) in enumerate(_examples)
        i in skip && continue

        # write out the header, description, code block, and image link
        if !isempty(example.header)
            write(md, """
            ### [$(example.header)](@id $pkgname-ref$i)
            """)
        end
        write(md, """
        $(example.desc)
        """)
        # write(md, "```julia\n$(join(map(string, example.exprs), "\n"))\n```\n\n")
        write(md, """
        ```@example $pkgname
        """)
        for expr in example.exprs
            pretty_print_expr(md, expr)
        end
        if pkgname ∈ (:plotly, :plotlyjs)
            write(md, "png(\"$(pkgname)_ex$i\") # hide\n")
        end
        write(md, "```\n")
        if pkgname ∈ (:plotly, :plotlyjs)
            write(md, "![]($(pkgname)_ex$i.png)\n")
        end
    end

    write(md, "- Supported arguments: $(markdown_code_to_string(collect(Plots.supported_attrs(pkg))))\n")
    write(md, "- Supported values for linetype: $(markdown_symbols_to_string(Plots.supported_seriestypes(pkg)))\n")
    write(md, "- Supported values for linestyle: $(markdown_symbols_to_string(Plots.supported_styles(pkg)))\n")
    write(md, "- Supported values for marker: $(markdown_symbols_to_string(Plots.supported_markers(pkg)))\n")

    write(md, "(Automatically generated: $(now()))")
    close(md)
end

# ----------------------------------------------------------------------


# tables detailing the features that each backend supports

function make_support_df(allvals, func)
    vals = sort(allvals) # rows
    bs = sort(backends())
    bs = filter(be -> be ∉ [Plots._deprecated_backends; :plotlyjs; :hdf5], bs) # cols
    df = DataFrames.DataFrame(keys = string.('`', vals, '`'))

    for b in bs
        b_supported_vals = ["" for _ in 1:length(vals)]
        for (i, val) in enumerate(vals)
            if func == Plots.supported_seriestypes
                stype = Plots.seriestype_supported(Plots._backend_instance(b), val)
                b_supported_vals[i] = stype == :native ? "✅" : (stype == :no ? "" : "🔼")
            else
                supported = func(Plots._backend_instance(b))

                b_supported_vals[i] = val in supported ? "✅" : ""
            end
        end
        df[!, b] = b_supported_vals
    end
    return string(mdtable(df, latex=false))
end

function generate_supported_markdown()
    md = open(joinpath(GENDIR, "supported.md"), "w")

    write(md, """
    ## [Series Types](@id supported)

    Key:

    - ✅ the series type is natively supported by the backend.
    - 🔼 the series type is supported through series recipes.


    """)
    write(md, make_support_df(Plots.all_seriestypes(), Plots.supported_seriestypes))

    supported_args =OrderedDict(
        "Keyword Arguments" => (Plots._all_args, Plots.supported_attrs),
        "Markers" => (Plots._allMarkers, Plots.supported_markers),
        "Line Styles" => (Plots._allStyles,  Plots.supported_styles),
        "Scales" => (Plots._allScales,  Plots.supported_scales)
    )

    for (header, args) in supported_args
        write(md, """

        ## $header

        """)
        write(md, make_support_df(args...))
    end

    write(md, "\n(Automatically generated: $(now()))")
    close(md)
end


# ----------------------------------------------------------------------


function make_attr_df(ktype::Symbol, defs::KW)
    n = length(defs)
    df = DataFrame(
        Attribute = fill("", n),
        Default = fill("", n),
        Type = fill("", n),
        Description = fill("", n),
    )
    for (i, (k, def)) in enumerate(defs)
        desc = get(Plots._arg_desc, k, "")
        first_period_idx = findfirst(isequal('.'), desc)

        aliases = sort(collect(keys(filter(p -> p.second == k, Plots._keyAliases))))
        add = isempty(aliases) ? "" : string(
            " *(`",
            join(aliases, "`*, *`"),
            "`)*"
        )
        df.Attribute[i] = string("`", k, "`", add)
        if first_period_idx !== nothing
            typedesc = desc[1:first_period_idx-1]
            desc = strip(desc[first_period_idx+1:end])

            aliases = join(map(string,aliases), ", ")

            df.Default[i] = string("`", def, "`")
            df.Type[i] = string(typedesc)
            df.Description[i] = string(desc)
        end
    end
    sort!(df, [:Attribute])
    return string(mdtable(df, latex=false))
end

const ATTRIBUTE_TEXTS = Dict(
    :Series => "These attributes apply to individual series (lines, scatters, heatmaps, etc)",
    :Plot => "These attributes apply to the full Plot. (A Plot contains a tree-like layout of Subplots)",
    :Subplot => "These attributes apply to settings for individual Subplots.",
    :Axis => "These attributes apply to an individual Axis in a Subplot (for example the `subplot[:xaxis]`)",
)

const ATTRIBUTE_DEFAULTS = Dict(
    :Series => Plots._series_defaults,
    :Plot => Plots._plot_defaults,
    :Subplot => Plots._subplot_defaults,
    :Axis => Plots._axis_defaults,
)

function generate_attr_markdown(c)
    # open the markdown file
    cstr = lowercase(string(c))
    attr_text = ATTRIBUTE_TEXTS[c]
    md = open(joinpath(GENDIR, "attributes_$cstr.md"), "w")

    write(md, """
    ### $c

    $attr_text

    """)
    write(md, make_attr_df(c, ATTRIBUTE_DEFAULTS[c]))

    write(md, "\n(Automatically generated: $(now()))")
    close(md)
end

function generate_attr_markdown()
    for c in (:Series, :Plot, :Subplot, :Axis)
        generate_attr_markdown(c)
    end
end


function generate_graph_attr_markdown()
    md = open(joinpath(GENDIR, "graph_attributes.md"), "w")

    write(md, """
    # [Graph Attributes](@id graph_attributes)

    Where possible, GraphRecipes will adopt attributes from Plots.jl to format visualizations.
    For example, the `linewidth` attribute from Plots.jl has the same effect in GraphRecipes.
    In order to give the user control over the layout of the graph visualization, GraphRecipes
    provides a number of keyword arguments (attributes). Here we describe those attributes
    alongside their default values.

    """)

    df = DataFrame(
        Attribute = [
            "`dim`",
            "`T`",
            "`curves`",
            "`curvature_scalar`, *(`curvaturescalar`, `curvature`)*",
            "`root`",
            "`node_weights`, *(`nodeweights`)*",
            "`names`",
            "`fontsize`",
            "`nodeshape`, *(`node_shape`)*",
            "`nodesize`, *(`node_size`)*",
            "`nodecolor`, *(`marker_color`)*",
            "`x`, `y`, `z`",
            "`method`",
            "`func`",
            "`shorten`, *(`shorten_edge`)*",
            "`axis_buffer`, *(`axisbuffer`)*",
            "`layout_kw`",
            "`edgewidth`, *(`edge_width`, `ew`)*",
            "`edgelabel`, *(`edge_label`, `el`)*",
            "`edgelabel_offset`, *(`edgelabeloffset`, `elo`)*",
            "`self_edge_size`, *(`selfedgesize`, `ses`)*",
            "`edge_label_box`, *(`edgelabelbox`, `edgelabel_box`, `elb`)*",
        ],
        Default = [
            "`2`",
            "`Float64`",
            "`true`",
            "`0.05`",
            "`:top`",
            "`nothing`",
            "`[]`",
            "`7`",
            "`:hexagon`",
            "`0.1`",
            "`1`",
            "`nothing`",
            "`:stress`",
            "`get(_graph_funcs, method, by_axis_local_stress_graph)`",
            "`0.0`",
            "`0.2`",
            "`Dict{Symbol,Any}()`",
            "`(s, d, w) -> 1`",
            "`nothing`",
            "`0.0`",
            "`0.1`",
            "`true`",
        ],
        Description = [
        "The number of dimensions in the visualization.",
        "The data type for the coordinates of the graph nodes.",
        "Whether or not edges are curved. If `curves == true`, then the edge going from node \$s\$ to node \$d\$ will be defined by a cubic spline passing through three points: (i) node \$s\$, (ii) a point `p` that is distance `curvature_scalar` from the average of node \$s\$ and node \$d\$ and (iii) node \$d\$.",
        "A scalar that defines how much edges curve, see `curves` for more explanation.",
        "For displaying trees, choose from `:top`, `:bottom`, `:left`, `:right`. If you choose `:top`, then the tree will be plotted from the top down.",
        "The weight of the nodes given by a list of numbers. If `node_weights != nothing`, then the size of the nodes will be scaled by the `node_weights` vector.",
        "Names of the nodes given by a list of objects that can be parsed into strings. If the list is smaller than the number of nodes, then GraphRecipes will cycle around the list.",
        "Font size for the node labels and the edge labels.",
        "Shape of the nodes, choose from `:hexagon`, `:circle`, `:ellipse`, `:rect` or `:rectangle`.",
        "The size of nodes in the plot coordinates. Note that if `names` is not empty, then nodes will be scaled to fit the labels inside them.",
        "The color of the nodes. If `nodecolor` is an integer, then it will be taken from the current color pallette. Otherwise, the user can pass any color that would be recognised by the Plots `color` attribute.",
        "The coordinates of the nodes.",
        "The method that GraphRecipes uses to produce an optimal layout, choose from `:spectral`, `:sfdp`, `:circular`, `:shell`, `:stress`, `:spring`, `:tree`, `:buchheim`, `:arcdiagram` or `:chorddiagram`. See [NetworkLayout](https://github.com/JuliaGraphs/NetworkLayout.jl) for further details.",
        "A layout algorithm that can be passed in by the user.",
        "An amount to shorten edges by.",
        "Increase the `xlims` and `ylims`/`zlims` of the plot. Can be useful if part of the graph sits outside of the default view.",
        "A list of keywords to be passed to the layout algorithm, see [NetworkLayout](https://github.com/JuliaGraphs/NetworkLayout.jl) for a list of keyword arguments for each algorithm.",
        "The width of the edge going from \$s\$ to node \$d\$ with weight \$w\$.",
        "A dictionary of `(s, d) => label`, where `s` is an integer for the source node, `d` is an integer for the destiny node and `label` is the desired label for the given edge. Alternatively the user can pass a vector or a matrix describing the edge labels. If you use a vector or matrix, then either `missing`, `false`, `nothing`, `NaN` or `\"\"` values will not be displayed. In the case of multigraphs, triples can be used to define edges.",
        "The distance between edge labels and edges.",
        "The size of self edges.",
        "A box around edge labels that avoids intersections between edge labels and the edges that they are labeling.",
        ]
    )

    write(md, string(mdtable(df, latex=false)))
    write(md, """
    ## Aliases
    Certain keyword arguments have aliases, so GraphRecipes "does what you mean, not
    what you say".

    So for example, `nodeshape=:rect` and `node_shape=:rect` are equivalent. To see the
    available aliases, type `GraphRecipes.graph_aliases`. If you are unhappy with the provided
    aliases, then you can add your own:
    ```julia
    using GraphRecipes, Plots

    push!(GraphRecipes.graph_aliases[:nodecolor],:nc)

    # These two calls produce the same plot, modulo some randomness in the layout.
    plot(graphplot([0 1; 0 0], nodecolor=:red), graphplot([0 1; 0 0], nc=:red))
    ```
    """)

    write(md, "\n(Automatically generated: $(now()))")
    close(md)
end

end # module
