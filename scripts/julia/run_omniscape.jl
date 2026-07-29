# Objective 4: trivial CLI entry point for Omniscape.jl -- deliberately does nothing beyond
# calling the package's own documented INI-config API. All input prep (resistance/source
# GeoTIFFs, INI config text) and output consumption happen in R
# (scripts/r/R/connectivity_run.R) via file I/O; this script exists only because Omniscape.jl
# runs in-process in Julia and JuliaCall/RCall (the usual R<->Julia bridge) is broken on R 4.5+
# (RCall.jl issue #566 -- R 4.5 hid the SET_SYMVALUE C symbol RCall.jl depends on). Invoked as a
# plain subprocess: `julia -t N run_omniscape.jl path/to/config.ini`.
using Omniscape

if length(ARGS) != 1
    println(stderr, "Usage: julia run_omniscape.jl <config.ini>")
    exit(1)
end

run_omniscape(ARGS[1])
