# Objective 4: trivial CLI entry point for Circuitscape.jl -- see run_omniscape.jl's header
# comment for why this exists as a subprocess entry point rather than an in-process R<->Julia
# call. Invoked as: `julia -t N run_circuitscape.jl path/to/config.ini`.
using Circuitscape

if length(ARGS) != 1
    println(stderr, "Usage: julia run_circuitscape.jl <config.ini>")
    exit(1)
end

compute(ARGS[1])
